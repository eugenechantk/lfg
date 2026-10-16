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
    var canGoForward = false

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
    #if DEBUG
    /// The S2 sign-in fixture: two harmless cookies on two domains, so the
    /// review step has something to list without signing in anywhere.
    func seedFixtureCookies() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        for (name, domain) in [("s2fx_session", "example.com"), ("s2fx_pref", "example.org")] {
            if let cookie = HTTPCookie(properties: [.name: name, .value: "1", .domain: domain, .path: "/", .secure: "TRUE"]) {
                await store.setCookie(cookie)
            }
        }
    }
    #endif
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url; loading = false; canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
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
                // The login phase shows its error under its own top bar.
                if let error, phase != .login {
                    Text(error).font(.callout).foregroundStyle(.red).padding().accessibilityIdentifier("phone_sign_in_error")
                }
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
            }
            .toolbar(phase == .login ? .hidden : .visible, for: .navigationBar)
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
                #if DEBUG
                // The S2 sign-in fixture (`LFG_S2_VIEW_FIXTURE=signin`) has no host
                // request behind it: open a harmless page in its browser instead.
                if requestID == "s2fx" {
                    targets = [PhoneSignInTarget(id: "s2fx", name: "Chrome", kind: "extension")]
                    targetID = "s2fx"; address = "https://example.com"
                    openLogin()
                    await browser.seedFixtureCookies()
                    return
                }
                #endif
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
    /// Board `s2-signin`: close · an address pill naming the site, why the
    /// agent asked and where the sign-in goes · reload; the website; then back,
    /// forward and "I'm signed in".
    private var login: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SignInRoundButton(size: 40, label: "Close", identifier: "phone_sign_in_close") {
                    Task { await closeSignIn() }
                } glyph: {
                    SheetGlyph(kind: .close)
                        .stroke(SessionSheet.chromeInk, style: StrokeStyle(lineWidth: 2.8 * 14 / 24, lineCap: .round))
                        .frame(width: 14, height: 14)
                }
                .disabled(busy)
                addressPill
                SignInRoundButton(size: 40, label: "Reload", identifier: "phone_sign_in_reload") {
                    browser.webView?.reload()
                } glyph: {
                    SignInGlyph(kind: .reload)
                        .stroke(SessionSheet.chromeInk, style: StrokeStyle(lineWidth: 2.4 * 16 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16)
                }
            }
            // Board: a 46pt bar 10pt below the sheet's top, 8pt above the page.
            .frame(height: 46)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .accessibilityIdentifier("phone_sign_in_error")
            }
            if let message = browser.error {
                Text(message).font(.callout).foregroundStyle(S2.ink).padding()
                    .accessibilityIdentifier("phone_sign_in_browser_error")
            }
            if let webView = browser.webView {
                PhoneLoginWebView(webView: webView)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                SignInRoundButton(size: 44, label: "Back", identifier: "phone_sign_in_back") {
                    browser.webView?.goBack()
                } glyph: {
                    SignInGlyph(kind: .back)
                        .stroke(browser.canGoBack ? SessionSheet.chromeInk : signInDisabledInk,
                                style: StrokeStyle(lineWidth: 2.4 * 18 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                }
                .disabled(!browser.canGoBack)
                SignInRoundButton(size: 44, label: "Forward", identifier: "phone_sign_in_forward") {
                    browser.webView?.goForward()
                } glyph: {
                    SignInGlyph(kind: .forward)
                        .stroke(browser.canGoForward ? SessionSheet.chromeInk : signInDisabledInk,
                                style: StrokeStyle(lineWidth: 2.4 * 18 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                }
                .disabled(!browser.canGoForward)
                Button { Task { await reviewCookies() } } label: {
                    Text(agentRequestID == nil ? "Review" : "I’m signed in")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(S2.send))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier(agentRequestID == nil ? "phone_sign_in_review" : "phone_sign_in_done")
            }
            // Board: a 56pt bar 8pt below the page, whose bottom sits 28pt above
            // the screen's edge, 6pt into the home-indicator inset.
            .frame(height: 56)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, -6)
        }
        .background(S2.surface.ignoresSafeArea())
    }

    /// "accounts.google.com" with a lock, over "For Search Console audit · goes
    /// to Air" (the session it is for, and the host that receives it).
    private var addressPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                SignInGlyph(kind: .lock)
                    .stroke(S2.secondaryInk, style: StrokeStyle(lineWidth: 2.8 * 11 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 11)
                Text(browser.currentURL?.host ?? loginURL?.host ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(S2.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("phone_sign_in_current_host")
                if browser.loading {
                    ProgressView().controlSize(.mini)
                        .accessibilityIdentifier("phone_sign_in_loading")
                }
            }
            // Board: the host's line box is 16pt and the purpose line follows
            // with no gap.
            .frame(height: 16)
            Text(purposeLine)
                .font(.system(size: 11))
                .foregroundStyle(S2.color(dark: 0xFFB340, light: 0xC93400))
                .lineLimit(1)
                .truncationMode(.middle)
                .cssLineBox(size: 11, lineHeight: 13)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S2.chip))
    }

    /// The host that receives the sign-in, by the name the app shows for it.
    private var destination: String {
        store.host(forSession: sessionID)?.label ?? (hostName.isEmpty ? "your Mac" : hostName)
    }
    private var purposeLine: String {
        let title = store.session(sessionID)?.title ?? ""
        return title.isEmpty ? "Goes to \(destination)" : "For \(title) · goes to \(destination)"
    }
    private var review: some View {
        Form {
            Section {
                if agentRequestID != nil {
                    Text("Send this sign-in to \(destination)?")
                        .font(.headline)
                        .accessibilityIdentifier("phone_sign_in_review_title")
                }
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
                Button(busy ? "Sending…" : sendLabel) { Task {
                    if agentRequestID != nil { await completeRequestedSignIn() } else { await transfer() }
                } }
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
    private var sendLabel: String {
        let n = selectedCookies.count
        return agentRequestID != nil ? "Send \(n) \(n == 1 ? "cookie" : "cookies")" : "Send sign-in (\(n) cookies)"
    }

    /// Sends only the cookies for the domains switched on in the review step.
    private func completeRequestedSignIn() async {
        guard let requestID = agentRequestID, let client, !busy else { return }
        let cookies = selectedCookies
        guard !cookies.isEmpty else { error = "Switch on at least one domain to send."; return }
        busy = true; error = nil
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
        guard !cookies.isEmpty else {
            error = agentRequestID == nil ? "No login cookies yet. Finish signing in, then tap Review."
                : "No login cookies yet. Finish signing in, then tap I’m signed in."
            return
        }
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

/// A round chrome button of the sign-in browser (board `s2-signin`: #2C2C2E).
/// A disabled back or forward arrow (board `s2-signin`: #636366).
private let signInDisabledInk = S2.color(dark: 0x636366, light: 0xC7C7CC)

private struct SignInRoundButton<Glyph: View>: View {
    let size: CGFloat
    let label: String
    let identifier: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            glyph()
                .frame(width: size, height: size)
                .background(Circle().fill(S2.chip))
                .contentShape(Circle())
        }
        // Board: a disabled arrow only greys its ink (the caller's colour). The
        // plain style would also fade the fill; this one leaves the label alone,
        // and `.disabled` still tells VoiceOver the button is dimmed.
        .buttonStyle(SignInRoundStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct SignInRoundStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The sign-in browser's icons, from the board's SVGs (24-unit box).
private struct SignInGlyph: Shape {
    enum Kind { case back, forward, reload, lock }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        switch kind {
        case .back:
            path.move(to: p(15, 5)); path.addLine(to: p(8, 12)); path.addLine(to: p(15, 19))
        case .forward:
            path.move(to: p(9, 5)); path.addLine(to: p(16, 12)); path.addLine(to: p(9, 19))
        case .reload:
            // M20 12a8 8 0 1 1-2.3-5.6 (clockwise most of the way round), M20 4v5h-5.
            path.addArc(center: p(12, 12), radius: 8 * k, startAngle: .degrees(0), endAngle: .degrees(315),
                        clockwise: false)
            path.move(to: p(20, 4)); path.addLine(to: p(20, 9)); path.addLine(to: p(15, 9))
        case .lock:
            path.addRoundedRect(in: CGRect(x: rect.minX + 5 * k, y: rect.minY + 11 * k, width: 14 * k, height: 10 * k),
                                cornerSize: CGSize(width: 2 * k, height: 2 * k))
            path.move(to: p(8, 11)); path.addLine(to: p(8, 8))
            path.addArc(center: p(12, 8), radius: 4 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: p(16, 11))
        }
        return path
    }
}

