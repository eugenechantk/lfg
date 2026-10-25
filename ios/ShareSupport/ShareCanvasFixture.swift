#if DEBUG
import UIKit
import LFGCore

/// Review-only inputs for the real share extension. Remove canvas-state.json
/// from its App Group to return to normal sharing. Never compiled into Release.
@MainActor
enum ShareCanvasFixture {
    static func apply(to model: ShareComposerModel) -> Bool {
        let control = model.spool.root.appendingPathComponent("canvas-state.json")
        guard let data = try? Data(contentsOf: control),
              let input = try? JSONDecoder().decode(Input.self, from: data) else { return false }
        let state = input.state
        let pro = Host(url: "http://127.0.0.1:18997", name: "Pro", isDefault: true)
        let air = Host(url: "http://127.0.0.1:18998", name: "Air")
        let now = Date().timeIntervalSince1970 * 1000
        let rows = [
            ShareRecipient(host: pro, session: Session(sessionId: "11111111-1111-4111-8111-111111111111", title: "Fork session feature", project: "lfg", cwd: "/work/lfg", lastActivityAt: now, lastUserAt: now, busy: true)),
            ShareRecipient(host: pro, session: Session(sessionId: "22222222-2222-4222-8222-222222222222", title: "Ship lfg to TestFlight", project: "lfg", cwd: "/work/lfg", lastUserAt: now-1000, prompt: AgentPrompt(question: "Upload build now?", options: []))),
            ShareRecipient(host: pro, session: Session(sessionId: "33333333-3333-4333-8333-333333333333", title: "Liquid Glass tab bar", agent: "codex", project: "lfg", cwd: "/work/lfg", lastUserAt: now-2000)),
            ShareRecipient(host: air, session: Session(sessionId: "44444444-4444-4444-8444-444444444444", title: "Search Console audit", agent: "codex", project: "inbox", cwd: "/work/inbox", lastUserAt: now-3000), isReachable: false),
            ShareRecipient(host: pro, session: Session(sessionId: "55555555-5555-4555-8555-555555555555", title: "Shinkai room decorator", project: "SleepingBeauty", cwd: "/work/SleepingBeauty", lastUserAt: now-4000)),
            ShareRecipient(host: pro, session: Session(sessionId: "66666666-6666-4666-8666-666666666666", title: "Readwise import fix", project: "readwise", cwd: "/work/readwise", closed: true)),
        ]
        model.configuration = ShareConfiguration(hosts: [pro, air], recipients: rows, recentDirs: ["/work/lfg", "/work/inbox"], agent: "claude")
        model.recipients = rows
        model.hostID = pro.id; model.cwd = "/work/lfg"; model.agent = "claude"
        model.directories = ["/work", "/work/lfg", "/work/inbox"]
        model.loadingInput = false
        model.reachableHostIDs = [pro.id]
        model.text = "https://developer.apple.com/design/human-interface-guidelines/sheets"
        model.previewTitle = "Sheets | Apple Developer Documentation"
        if state == "loading" { model.loadingInput = true }
        if state == "refreshing" { model.refreshing = true }
        if state == "setup" { model.configuration.hosts = []; model.recipients = [] }
        if state == "empty" { model.recipients = [] }
        if state == "input-error" { model.inputError = "This attachment could not be read. Share it again from its original app." }
        if state == "all-offline" {
            model.recipients = rows.map { var row = $0; row.isReachable = false; return row }
            model.reachableHostIDs = []
            model.refreshError = "Hosts are offline. Cached sessions are available; shares wait for LFG to reconnect."
        }
        if state == "search" { model.query = "Liquid" }
        if state == "no-results" { model.query = "No matching project" }
        let selection: Int? = ["working":0,"question":1,"idle":2,"closed":5,"offline":3][state]
        if let selection { model.selectedID = rows[selection].id }
        let compose = ["editing", "quote", "text", "images", "pdf", "file", "empty-draft", "sending", "failed", "uncertain", "sent-working", "sent-question", "sent-idle", "sent-closed", "queued"]
        if compose.contains(state) { model.selectedID = rows[0].id }
        if state == "editing" { model.text = "Use this sheet pattern for the fork confirmation.\n" + model.text }
        if state == "quote" { model.text = "A sheet should hold one scoped task that stays close to what people were doing.\n" + model.text }
        if state == "text" { model.text = "Please review the iPad share sheet layout and its keyboard behavior." }
        if state == "empty-draft" { model.text = "" }
        if state == "images" || state == "sending" {
            model.text = "Review these screenshots."
            for (index, color) in [UIColor.systemBlue, UIColor.systemOrange].enumerated() {
                let url = model.spool.root.appendingPathComponent("canvas-image-\(index).png")
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320))
                let bytes = renderer.pngData { context in
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
                    ("Share image \(index+1)" as NSString).draw(at: CGPoint(x: 30,y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 32),.foregroundColor: UIColor.white])
                }
                try? bytes.write(to: url)
                if let file = try? model.spool.stage(url, jobID: model.inputID, filename: "screenshot-\(index+1).png", contentType: "image/png") { model.files.append(file) }
            }
        }
        if state == "pdf" || state == "file" {
            let url = model.spool.root.appendingPathComponent("canvas-document")
            try? Data("Review fixture attachment".utf8).write(to: url)
            if let file = try? model.spool.stage(url, jobID: model.inputID, filename: state == "pdf" ? "share-brief.pdf" : "workout-demo.mov", contentType: state == "pdf" ? "application/pdf" : "video/quicktime") { model.files = [file] }
            model.text = "Please review this file."
        }
        if state.hasPrefix("new") || state == "sent-new" {
            model.selectedID = "new"
            if state == "new-no-folder" { model.cwd = "" }
            if state == "new-options" { model.showingOptions = true }
        }
        if state == "sent-question" { model.selectedID = rows[1].id }
        if state == "sent-idle" { model.selectedID = rows[2].id }
        if state == "sent-closed" { model.selectedID = rows[5].id }
        if state == "queued" { model.selectedID = rows[3].id }
        if state == "sending" { model.sending = true }
        let status: ShareJob.Status? = state.hasPrefix("sent-") ? .sent : ["failed": .failed, "uncertain": .uncertain, "queued": .queued][state]
        if let status {
            var job = ShareJob(id: model.inputID, host: state == "queued" ? air : pro, sessionID: model.selected?.session.id, recipientTitle: model.recipientTitle, text: model.text, files: model.files)
            job.status = status
            if status == .failed { job.error = "Not sent. The computer could not resume this session. Try again." }
            model.delivery = job
        }
        return true
    }
    private struct Input: Decodable { let state: String }
}
#endif
