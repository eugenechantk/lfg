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
                case .setup: setup
                case .login: login
                case .review: review
                case .result: outcome
                }
            }
            .navigationTitle("Sign in on Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .result ? "Done" : "Cancel") { dismiss() }
                        .disabled(busy && phase == .review)
                        .accessibilityIdentifier("phone_sign_in_close")
                }
                if phase == .login {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") { Task { await reviewCookies() } }
                            .disabled(browser.loading || busy)
                            .accessibilityIdentifier("phone_sign_in_review")
                    }
                }
            }
            .overlay {
                if scenePhase != .active && phase != .setup {
                    Color(uiColor: .systemBackground).overlay(Label("Sign-in hidden", systemImage: "lock.fill"))
                }
            }
        }
        .interactiveDismissDisabled(busy && phase == .review)
        .accessibilityIdentifier("phone_sign_in_view")
        .task {
            guard let host = store.host(forSession: sessionID), let resolved = settings.client(for: host) else {
                error = "The session’s host is unavailable."; return
            }
            client = resolved; hostName = resolved.logLabel
            await refreshTargets()
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
                Spacer()
                Button { browser.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload").accessibilityIdentifier("phone_sign_in_reload")
            }.padding()
            if browser.loading { ProgressView().accessibilityIdentifier("phone_sign_in_loading") }
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
            Text(result?.message ?? "Delivery could not be confirmed. Check the destination browser.")
                .multilineTextAlignment(.center).accessibilityIdentifier("phone_sign_in_result")
            Button("Start another sign-in") { result = nil; error = nil; phase = .setup; Task { await refreshTargets() } }
                .accessibilityIdentifier("phone_sign_in_restart")
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
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
