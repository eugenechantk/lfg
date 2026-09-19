import SwiftUI
import WebKit
import LFGCore

/// Owns one ephemeral login browser. No website data enters app persistence.
@MainActor @Observable private final class PhoneLoginBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView?
    var currentURL: URL?
    var error: String?
    var loading = false
    var canGoBack = false

    func start(_ url: URL) {
        destroy()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.accessibilityIdentifier = "phone_sign_in_webview"
        webView = web
        currentURL = url
        web.load(URLRequest(url: url))
    }
    func destroy() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        currentURL = nil
        error = nil
        loading = false
    }
    func cookies() async -> [PhoneSignInCookie] {
        guard let webView else { return [] }
        let values = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return values.map(PhoneSignInCookie.init(cookie:))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url; loading = false; canGoBack = webView.canGoBack
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        loading = false
        if (error as NSError).code != NSURLErrorCancelled {
            self.error = "Could not load this page. Some sign-in providers require signing in directly on your Mac."
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              (try? PhoneSignInPolicy.loginURL(url.absoluteString)) != nil else {
            error = "This sign-in needs another app or an unsupported URL. Sign in directly on your Mac for this site."
            return .cancel
        }
        if url.host == "accounts.google.com" {
            error = "Google sign-in does not support this embedded browser. Sign in directly on your Mac."
            loading = false; return .cancel
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request); return .cancel
        }
        if navigationAction.targetFrame?.isMainFrame == true { currentURL = url }
        return .allow
    }
}
private struct PhoneLoginWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct PhoneSignInView: View {
    let sessionID: String
    /// A waiting agent request to fulfil. Only the id is needed: the view fetches the
    /// request itself, so callers can open the browser straight from a prompt.
    var agentRequestID: String? = nil
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = PhoneLoginBrowser()
    @State private var client: LFGClient?
    @State private var hostName = ""
    @State private var targets: [PhoneSignInTarget] = []
    @State private var targetID = ""
    @State private var address = ""
    @State private var loginURL: URL?
    @State private var cookies: [PhoneSignInCookie] = []
    @State private var domains: Set<String> = []
    @State private var phase = Phase.setup
    @State private var error: String?
    @State private var busy = false
    @State private var requestOutcome: PhoneSignInAgentRequest?
    @State private var result: PhoneSignInResult?
    private enum Phase { case setup, login, review, result }
    private var target: PhoneSignInTarget? { targets.first { $0.id == targetID } }
    private var availableDomains: [String] { Array(Set(cookies.map { PhoneSignInPolicy.domain($0.domain) })).sorted() }
    private var selectedCookies: [PhoneSignInCookie] { PhoneSignInPolicy.selectedCookies(cookies, domains: domains) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error { Text(error).font(.callout).foregroundStyle(.red).padding().accessibilityIdentifier("phone_sign_in_error") }
                switch phase {
                case .setup:
                    if agentRequestID != nil { ProgressView("Opening sign-in…").frame(maxWidth: .infinity, maxHeight: .infinity) } else { setup }
                case .login: login
                case .review: review
                case .result: outcome
                }
            }
            .navigationTitle("Sign in on Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { Task { await closeSignIn() } } label: { Image(systemName: "xmark") }
                        .disabled(busy)
                        .accessibilityLabel(phase == .result ? "Close" : "Cancel")
                        .accessibilityIdentifier("phone_sign_in_close")
                }
                if phase == .login {
                    // Done is always available for an agent request: it sends whatever
                    // cookies the browser holds right now and lets the agent judge.
                    ToolbarItem(placement: .confirmationAction) {
                        Button(agentRequestID == nil ? "Review" : (busy ? "Sending…" : "Done")) { Task {
                            if agentRequestID != nil { await completeRequestedSignIn() } else { await reviewCookies() }
                        } }
                            .disabled(busy)
                            .accessibilityIdentifier(agentRequestID == nil ? "phone_sign_in_review" : "phone_sign_in_done")
                    }
                }
            }
            .overlay {
                if scenePhase != .active && phase != .setup {
                    Color(uiColor: .systemBackground).overlay(Label("Sign-in hidden", systemImage: "lock.fill"))
                }
            }
        }
        .interactiveDismissDisabled(agentRequestID != nil || busy)
        .accessibilityIdentifier("phone_sign_in_view")
        .task {
            guard let host = store.host(forSession: sessionID), let resolved = settings.client(for: host) else {
                error = "The session’s host is unavailable."; return
            }
            client = resolved; hostName = resolved.logLabel
            if let requestID = agentRequestID {
                do {
                    let current = try await resolved.phoneSignInRequestStatus(requestID)
                    guard current.sessionId == sessionID, current.isWaiting else {
                        requestOutcome = current; phase = .result; return
                    }
                    targets = [current.target]; targetID = current.target.id; address = current.url
                    openLogin()
                } catch { self.error = "This request is unavailable. Ask the agent to request sign-in again."; phase = .result }
            } else { await refreshTargets() }
        }
        .onDisappear { browser.destroy(); cookies = []; domains = [] }
    }

    private var setup: some View {
        Form {
            Section {
                TextField("https://example.com", text: $address)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().accessibilityIdentifier("phone_sign_in_url")
            } header: { Text("Website") } footer: {
                Text("Sign in here, then send the login to your browser. Google sign-in and sites with device-bound sessions may require signing in directly on your Mac.")
            }
            Section {
                if targets.isEmpty {
                    Text("No browsers connected").accessibilityIdentifier("phone_sign_in_no_targets")
                    Text("Connect the LFG Chrome extension on your Mac, or start a Playwright sign-in bridge.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("Browser", selection: $targetID) {
                        Text("Choose a browser").tag("")
                        ForEach(targets) { item in Text(item.name).tag(item.id) }
                    }.accessibilityIdentifier("phone_sign_in_target")
                }
                Button("Refresh browsers") { Task { await refreshTargets() } }
                    .disabled(busy).accessibilityIdentifier("phone_sign_in_refresh")
            } header: { Text(hostName.isEmpty ? "Destination" : "Destination · \(hostName)") }
            Section {
                Button("Open sign-in page") { openLogin() }
                    .disabled(target == nil || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    .accessibilityIdentifier("phone_sign_in_open")
            } footer: { Text("The login goes to the selected browser profile. Pause any automation using that site before replacing its login.") }
        }
    }
    private var login: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack).accessibilityLabel("Back")
                    .accessibilityIdentifier("phone_sign_in_back")
                Text(browser.currentURL?.host ?? "").font(.footnote).lineLimit(1).textSelection(.enabled)
                    .accessibilityIdentifier("phone_sign_in_current_host")
                // Inline so a page load never adds a row and shifts the web view.
                ProgressView().controlSize(.small)
                    .opacity(browser.loading ? 1 : 0)
                    .accessibilityHidden(!browser.loading)
                    .accessibilityIdentifier("phone_sign_in_loading")
                Spacer()
                Button { browser.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload").accessibilityIdentifier("phone_sign_in_reload")
            }.padding()
            if let message = browser.error { Text(message).font(.callout).padding().accessibilityIdentifier("phone_sign_in_browser_error") }
            if let webView = browser.webView { PhoneLoginWebView(webView: webView) }
        }
    }
    private var review: some View {
        Form {
            Section {
                LabeledContent("Browser", value: target?.name ?? "Unavailable")
                LabeledContent("Website", value: loginURL?.host ?? "")
                Text("This replaces matching login cookies in that browser. Your password is not included in the transfer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Domains to send") {
                ForEach(availableDomains, id: \.self) { domain in
                    Toggle(domain, isOn: Binding(get: { domains.contains(domain) }, set: { if $0 { domains.insert(domain) } else { domains.remove(domain) } }))
                        .accessibilityIdentifier("phone_sign_in_domain_\(domain)")
                }
            }
            Section {
                Button(busy ? "Sending…" : "Send sign-in (\(selectedCookies.count) cookies)") { Task { await transfer() } }
                    .disabled(busy || selectedCookies.isEmpty || target == nil)
                    .accessibilityIdentifier("phone_sign_in_send")
                Button("Back to website") { cookies = []; domains = []; phase = .login }
                    .disabled(busy).accessibilityIdentifier("phone_sign_in_return")
            } footer: { Text("Only selected domains are sent. Delivery confirms cookie installation; the website may still ask you to sign in again.") }
        }.disabled(busy)
    }
    private var outcome: some View {
        VStack(spacing: 20) {
            Image(systemName: result?.state == "installed" ? "checkmark.circle" : "exclamationmark.circle")
                .font(.largeTitle)
            Text(requestOutcome?.message ?? result?.message ?? "Delivery could not be confirmed. Check the destination browser.")
                .multilineTextAlignment(.center).accessibilityIdentifier("phone_sign_in_result")
            if agentRequestID == nil {
                Button("Start another sign-in") { result = nil; error = nil; phase = .setup; Task { await refreshTargets() } }
                    .accessibilityIdentifier("phone_sign_in_restart")
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func closeSignIn() async {
        guard !busy else { return }
        if let requestID = agentRequestID, phase != .result, let client {
            busy = true
            try? await client.cancelPhoneSignInRequest(requestID)
            busy = false
        }
        dismiss()
    }
    private func completeRequestedSignIn() async {
        guard let requestID = agentRequestID, let client, !busy else { return }
        busy = true; error = nil
        let all = await browser.cookies()
        let cookies = PhoneSignInPolicy.selectedCookies(all, domains: Set(all.map { PhoneSignInPolicy.domain($0.domain) }))
        guard !cookies.isEmpty else { busy = false; error = "Finish signing in before pressing Done."; return }
        defer { busy = false }
        do {
            let completed = try await client.completePhoneSignInRequest(requestID, cookies: cookies)
            requestOutcome = completed; result = completed.result
        } catch {
            // A dropped response does not prove the browser missed the cookies.
            // Read metadata once; never repeat the credential-bearing POST.
            requestOutcome = try? await client.phoneSignInRequestStatus(requestID)
            result = requestOutcome?.result
        }
        browser.destroy()
        if requestOutcome?.state == "installed" {
            dismiss()
        } else {
            // Keep failed or ambiguous delivery actionable without retrying the POST.
            phase = .result
        }
    }
    private func refreshTargets() async {
        guard let client else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            targets = try await client.phoneSignInTargets()
            if !targets.contains(where: { $0.id == targetID }) { targetID = "" }
        } catch { targets = []; targetID = ""; self.error = "Could not load browsers. Check the host connection and refresh." }
    }
    private func openLogin() {
        do {
            guard let client else { return }
            _ = try PhoneSignInPolicy.loginURL(client.baseURL.absoluteString)
            let url = try PhoneSignInPolicy.loginURL(address)
            loginURL = url; error = nil; browser.start(url); phase = .login
        } catch { self.error = "Enter a valid HTTPS website and use a secure connection to your Mac." }
    }
    private func reviewCookies() async {
        busy = true; defer { busy = false }
        cookies = await browser.cookies()
        cookies = PhoneSignInPolicy.selectedCookies(cookies, domains: Set(cookies.map { PhoneSignInPolicy.domain($0.domain) }))
        guard !cookies.isEmpty else { error = "No login cookies yet. Finish signing in, then tap Review."; return }
        let host = loginURL?.host?.lowercased() ?? ""
        domains = Set(availableDomains.filter { host == $0 || host.hasSuffix("." + $0) })
        error = nil; phase = .review
    }
    private func transfer() async {
        guard let client, let loginURL, target != nil else { return }
        let payload = PhoneSignInTransfer(targetId: targetID, url: loginURL.absoluteString, domains: domains.sorted(), cookies: selectedCookies)
        busy = true; error = nil
        defer { busy = false; cookies = []; domains = []; browser.destroy(); phase = .result }
        do { result = try await client.sendPhoneSignIn(payload) }
        catch { result = nil }
    }
}

/// Session-scoped metadata history. A completed entry never replays a cookie transfer.
struct PhoneSignInRequestsSheet: View {
    let sessionID: String
    let initialRequestID: String?
    @Environment(SessionStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var requests: [PhoneSignInAgentRequest] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var openedInitial = false
    @State private var path: [String] = []
    @State private var login: Login?

    private enum Login: Identifiable {
        case manual
        case requested(PhoneSignInAgentRequest)
        var id: String {
            switch self {
            case .manual: "manual"
            case .requested(let request): request.id
            }
        }
    }
    private var client: LFGClient? {
        guard let host = store.host(forSession: sessionID) else { return nil }
        return settings.client(for: host)
    }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !loaded && error == nil {
                    ProgressView("Loading sign-in requests…")
                } else if requests.isEmpty {
                    ContentUnavailableView(
                        error == nil ? "No sign-in requests" : "Could not load requests",
                        systemImage: "key",
                        description: Text(error ?? "Websites requested by this session will appear here.")
                    )
                } else {
                    List {
                        if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                        ForEach(requests) { request in
                            Button { open(request) } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: request.statusSystemImage)
                                        .foregroundStyle(request.historyTint)
                                        .frame(width: 22, height: 22)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(request.website)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack(spacing: 5) {
                                            Text(request.target.name)
                                            Text("·")
                                            Text(request.statusTitle)
                                                .foregroundStyle(request.historyTint)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("phone_sign_in_history_row_\(request.id)")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Sign-in requests")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let request = requests.first(where: { $0.id == id }) {
                    List {
                        LabeledContent("Website", value: request.website)
                        LabeledContent("Browser", value: request.target.name)
                        LabeledContent("Status", value: request.statusTitle)
                        LabeledContent("Requested") { Text(request.requestedAt, format: .dateTime.month(.abbreviated).day().hour().minute()) }
                        Text(request.message).foregroundStyle(.secondary)
                    }
                    .navigationTitle(request.website)
                    .accessibilityIdentifier("phone_sign_in_history_detail")
                } else {
                    ContentUnavailableView("Request unavailable", systemImage: "key")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { login = .manual } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Sign in to another website")
                        .accessibilityIdentifier("phone_sign_in_history_manual")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("phone_sign_in_history_done")
                }
            }
            .refreshable { await refresh() }
        }
        .accessibilityIdentifier("phone_sign_in_history")
        .sheet(item: $login, onDismiss: { Task { await refresh() } }) { selection in
            switch selection {
            case .manual:
                PhoneSignInView(sessionID: sessionID).presentationDetents([.large])
            case .requested(let request):
                PhoneSignInView(sessionID: sessionID, agentRequestID: request.id).presentationDetents([.large])
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }
    private func open(_ request: PhoneSignInAgentRequest) {
        if request.isWaiting { login = .requested(request) } else { path.append(request.id) }
    }
    private func refresh() async {
        guard let client else { error = "Reconnect to this session’s host to see its requests."; return }
        do {
            requests = try await client.phoneSignInRequests(sessionID: sessionID)
            loaded = true; error = nil
            if !openedInitial {
                openedInitial = true
                if let initialRequestID, let request = requests.first(where: { $0.id == initialRequestID }) { open(request) }
            }
        } catch { self.error = "Could not refresh requests. Check the host connection." }
    }
}

private extension PhoneSignInAgentRequest {
    var historyTint: Color {
        switch state {
        case "waiting", "delivering": .blue
        case "installed": .green
        case "failed", "partial", "offline": .orange
        default: .secondary
        }
    }
}
