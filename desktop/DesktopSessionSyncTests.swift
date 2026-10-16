import Foundation

@MainActor
enum DesktopSessionSyncTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run() throws -> Int {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            count += 1
            if !condition() { throw Failure(description: message) }
        }
        let url = "http://status-fixture.invalid"
        func session(_ id: String, busy: Bool) -> APISession {
            APISession(agent: "codex", pid: 1, cwd: "/tmp", project: "fixture", title: id,
                       sessionId: id, busy: busy, lastActivityAt: 1, tmuxName: "fixture",
                       model: "gpt-6.1-sol", status: nil, lastUserText: nil)
        }
        func item(_ host: HostState, _ id: String) -> SessionItem {
            SessionItem(session: host.sessions.first { $0.sessionId == id }!, hostURL: url,
                        hostId: "fixture", hostLabel: "Fixture", hostIsLocal: true, hostSSHTarget: nil,
                        needsInput: host.needsInputSessionIds.contains(id), hostOffline: host.error != nil)
        }
        var host = HostState(url: url, sshTarget: nil,
                             sessions: [session("finished", busy: true), session("active", busy: false)])
        var reconciliation = DesktopStatusReconciliation()
        let beforeRequest = reconciliation.revision
        reconciliation.record(.busy("finished", false), host: url)
        reconciliation.record(.busy("active", true), host: url)
        reconciliation.apply(to: &host, after: beforeRequest)
        try check(item(host, "finished").status == .idle, "completion immediately removes Working")
        try check(item(host, "active").status == .working, "start immediately enters Working")

        // A request started before the two edges returns its old booleans.
        var stale = HostState(url: url, sshTarget: nil,
                              sessions: [session("finished", busy: true), session("active", busy: false)])
        reconciliation.apply(to: &stale, after: beforeRequest)
        try check(item(stale, "finished").status == .idle, "late REST cannot reopen a finished turn")
        try check(item(stale, "active").status == .working, "late REST cannot clear a newer start")

        let afterEdges = reconciliation.revision
        var repaired = HostState(url: url, sshTarget: nil, sessions: [session("active", busy: false)])
        reconciliation.apply(to: &repaired, after: afterEdges)
        try check(item(repaired, "active").status == .idle, "fresh REST repairs a missing completion edge")
        reconciliation.discard(host: url, through: afterEdges)
        reconciliation.apply(to: &repaired, after: 0)
        try check(!repaired.sessions[0].busy, "old journal overrides are retired after reconciliation")

        reconciliation.record(.prompt("active", DesktopPrompt(question: "Approve?")), host: url)
        reconciliation.apply(to: &host, after: 0)
        try check(item(host, "active").status == .needsInput, "prompt takes precedence over Working")
        try check(host.sessions[1].prompt?.question == "Approve?", "prompt text reaches the row")
        let promptRevision = reconciliation.revision
        reconciliation.record(.prompt("active", nil), host: url)
        reconciliation.apply(to: &host, after: promptRevision)
        try check(item(host, "active").status == .working, "clearing a prompt restores the active turn")
        try check(host.sessions[1].prompt == nil, "clearing a prompt removes its old text")

        var foreign = HostState(url: "http://other-host.invalid", sshTarget: nil,
                                sessions: [session("active", busy: false)])
        reconciliation.apply(to: &foreign, after: 0)
        try check(!foreign.sessions[0].busy, "one host never changes another host's matching session ID")

        var metadata = session("metadata", busy: false)
        metadata.prompt = DesktopPrompt(question: "Keep me")
        let updated = metadata.replacingBusy(true)
        try check(updated.prompt == metadata.prompt && updated.title == metadata.title && updated.model == metadata.model,
                  "status updates preserve row metadata")
        try check(DesktopStatusEvent.decode(SSEFrame(event: "busy", data: "{\"sid\":\"active\",\"busy\":true}"))?.sessionID == "active",
                  "valid busy frame decodes")
        try check(DesktopStatusEvent.decode(SSEFrame(event: "busy", data: "{\"sid\":\"active\",\"busy\":\"true\"}")) == nil,
                  "malformed busy values cannot invent state")
        try check(DesktopStatusEvent.decode(SSEFrame(event: "prompt", data: "{\"sid\":\"active\"}")) == nil,
                  "missing prompt payload cannot clear a waiting session")
        try check(DesktopStatusEvent.decode(SSEFrame(event: "msg", data: "{\"sid\":\"active\",\"busy\":true}")) == nil,
                  "message contents never become a status signal")

        let store = SessionStore()
        store.configuredHosts = [Config.HostEntry(url: url)]
        store.hosts = [HostState(url: url, sshTarget: nil, sessions: [session("active", busy: false)])]
        store.receiveStatus(.busy("active", true), host: url)
        try check(store.items.first?.status == .working, "production store updates while no views exist")
        store.receiveStatus(.busy("active", false), host: url)
        try check(store.items.first?.status == .idle, "production store clears Working while no views exist")
        store.receiveStatus(.busy("active", true), host: "http://removed-host.invalid")
        try check(store.items.first?.status == .idle, "late events from a removed host are ignored")
        return count
    }
}

/// Read-only observation of the production store, including its real journal
/// transport. A dedicated config directory points integration tests at fixtures.
@MainActor
enum DesktopStatusSyncProbeCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--session-sync-probe" else { return }
        let duration = args.dropFirst(2).first.flatMap(Double.init) ?? 20
        let store = SessionStore()
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            store.startStatusSync()
            let start = Date()
            var previous: Data?
            while Date().timeIntervalSince(start) < duration {
                let rows = store.items.filter { !$0.session.closed }.map { item in
                    ["host": item.hostURL, "id": item.session.sessionId ?? item.id,
                     "status": String(describing: item.status)]
                }.sorted { ($0["host"]! + $0["id"]!) < ($1["host"]! + $1["id"]!) }
                if let signature = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                   signature != previous {
                    previous = signature
                    let value: [String: Any] = ["elapsed": Date().timeIntervalSince(start), "rows": rows,
                                                "connected": store.statusFeed?.connected.sorted() ?? []]
                    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                       let line = String(data: data, encoding: .utf8) {
                        print(line); fflush(stdout)
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            store.stopStatusSync()
            done.signal()
        }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        Darwin.exit(0)
    }
}
