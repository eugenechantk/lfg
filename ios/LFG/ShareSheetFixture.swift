#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
import LFGCore

/// Opens the real system activity controller and installed share extension.
/// Only a local fixture host is used; no real session receives these messages.
struct ShareSheetFixture: View {
    @State private var activity: ShareFixtureActivity?
    @State private var pending = false
    @State private var seeded = false
    @State private var error: String?
    @Environment(AppSettings.self) private var settings
    @Environment(SessionStore.self) private var store
    var body: some View {
        NavigationStack {
            List {
                Section("Real share extension") {
                    Button("Share link") { activity = .init(items: [URL(string: "https://developer.apple.com/design/human-interface-guidelines/sheets")!]) }
                        .accessibilityIdentifier("fixture_share_link")
                    Button("Share selected text") { activity = .init(items: ["A sheet should hold one scoped task.\nhttps://developer.apple.com/design/human-interface-guidelines/sheets"]) }
                        .accessibilityIdentifier("fixture_share_text")
                    Button("Share two images") { shareImages() }.accessibilityIdentifier("fixture_share_images")
                    Button("Share PDF") { sharePDF() }.accessibilityIdentifier("fixture_share_pdf")
                    Button("Review pending shares") { ShareAppBridge.shared.resume(settings: settings, store: store); pending = true }
                        .accessibilityIdentifier("fixture_share_pending")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Text(seeded ? "Configured for local fixture host on port 18894." : "Preparing…").font(.footnote)
                Section("Received messages") {
                    Button("Refresh received messages") { Task { await refreshReceived() } }.accessibilityIdentifier("fixture_received_refresh")
                    ForEach(received, id: \.self) { Text($0).accessibilityIdentifier("fixture_received_message") }
                }
            }.navigationTitle("Share extension test")
                .sheet(item: $activity) { ShareFixtureActivityController(items: $0.items) }
                .sheet(isPresented: $pending) { PendingSharesView() }
                .task { seed(); await refreshReceived() }
        }
    }
    @State private var received: [String] = []
    private func refreshReceived() async {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18894/fixture/received")!),
              let messages = try? JSONDecoder().decode([String].self, from: data) else { return }
        received = messages
    }
    private func seed() {
        guard let spool = ShareEnvironment.spool else { error = "App Group unavailable"; return }
        let pro = Host(url: "http://127.0.0.1:18894", hostId: "share-fixture", name: "Pro", isDefault: true)
        let air = Host(url: "http://127.0.0.1:18895", name: "Air")
        let now = Date().timeIntervalSince1970 * 1000
        let rows = [
            ShareRecipient(host: pro, session: Session(sessionId: "11111111-1111-4111-8111-111111111111", title: "Fork session feature", project: "lfg", cwd: "/work/lfg", lastActivityAt: now, lastUserAt: now, busy: true)),
            ShareRecipient(host: pro, session: Session(sessionId: "22222222-2222-4222-8222-222222222222", title: "Ship lfg to TestFlight", project: "lfg", cwd: "/work/lfg", lastUserAt: now - 1000, prompt: AgentPrompt(question: "Upload build now?", options: []))),
            ShareRecipient(host: pro, session: Session(sessionId: "33333333-3333-4333-8333-333333333333", title: "Liquid Glass tab bar", agent: "codex", project: "lfg", cwd: "/work/lfg", lastUserAt: now - 2000)),
            ShareRecipient(host: air, session: Session(sessionId: "44444444-4444-4444-8444-444444444444", title: "Search Console audit", agent: "codex", project: "inbox", cwd: "/work/inbox", lastUserAt: now - 3000), isReachable: false),
            ShareRecipient(host: pro, session: Session(sessionId: "55555555-5555-4555-8555-555555555555", title: "Shinkai room decorator", project: "SleepingBeauty", cwd: "/work/SleepingBeauty", lastUserAt: now - 4000)),
            ShareRecipient(host: pro, session: Session(sessionId: "66666666-6666-4666-8666-666666666666", title: "Readwise import fix", cwd: "/work/readwise", closed: true)),
        ]
        do {
            try spool.saveConfiguration(ShareConfiguration(hosts: [pro, air], recipients: rows, recentDirs: ["/work/lfg", "/work/inbox"], agent: "claude"))
            settings.hosts = [pro, air]; seeded = true
        } catch { self.error = error.localizedDescription }
    }
    private func shareImages() {
        let items = [UIColor.systemBlue, UIColor.systemOrange].enumerated().compactMap { index, color -> URL? in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320))
            let data = renderer.pngData { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
                ("Share image \(index + 1)" as NSString).draw(at: CGPoint(x: 30, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.white])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-image-\(index + 1).png")
            try? data.write(to: url); return url
        }
        activity = .init(items: items)
    }
    private func sharePDF() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-brief.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
        let data = renderer.pdfData { context in
            context.beginPage(); ("LFG share brief" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        try? data.write(to: url); activity = .init(items: [url])
    }
}
private struct ShareFixtureActivity: Identifiable { let id = UUID(); let items: [Any] }
private struct ShareFixtureActivityController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
