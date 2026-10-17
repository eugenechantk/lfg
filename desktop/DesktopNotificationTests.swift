import Foundation

@MainActor
enum DesktopNotificationTests {
    static func run() throws -> Int {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            count += 1
            if !condition() { throw DesktopSessionSyncTests.Failure(description: message) }
        }
        func item(_ id: String = "one", host: String = "pro", busy: Bool = false, prompt: Bool = false,
                  offline: Bool = false, closed: Bool = false) -> SessionItem {
            var session = APISession(agent: "codex", pid: 1, cwd: "/tmp", project: "fixture", title: "Test session",
                sessionId: id, busy: busy, lastActivityAt: 1, tmuxName: closed ? nil : "test", model: nil,
                status: nil, lastUserText: nil, closed: closed)
            if prompt { session.prompt = DesktopPrompt(question: "Choose a color?") }
            return SessionItem(session: session, hostURL: "https://\(host).invalid", hostId: host,
                               hostLabel: host, hostIsLocal: host == "pro", hostSSHTarget: host,
                               needsInput: prompt, hostOffline: offline)
        }
        var tracker = DesktopNotificationTracker()
        try check(tracker.observe([item(busy: true), item("old", prompt: true)], now: 0).isEmpty, "startup never announces old work or prompts")
        let done = tracker.observe([item()], now: 1)
        try check(done.count == 1 && done.first?.kind == .finished, "busy to idle emits finished")
        try check(done.first?.title == "✅ Test session" && done.first?.body == "The agent finished its turn.", "finished copy matches phone")
        try check(tracker.observe([item(), item()], now: 2).isEmpty, "duplicate rows and polls do not repeat")
        try check(tracker.observe([item(busy: true, prompt: true)], now: 3).isEmpty, "late prompt waits for cooldown")
        let question = tracker.observe([item(busy: true, prompt: true)], now: 11)
        try check(question.count == 1 && question.first?.kind == .needsInput, "suppressed question retries while agent stays busy")
        try check(question.first?.body == "Choose a color?", "needs-input carries question")
        try check(tracker.observe([item(prompt: true)], now: 22).isEmpty, "stopping on an already announced prompt stays silent")
        _ = tracker.observe([item(busy: true)], now: 23)
        try check(tracker.observe([item(offline: true)], now: 24).isEmpty, "offline is not finished")
        try check(tracker.observe([item()], now: 25).count == 1, "snapshot reconnect repairs a missed finish once")
        try check(tracker.observe([item()], now: 40).isEmpty, "repeated reconnect snapshot stays silent")
        _ = tracker.observe([], now: 41)
        try check(tracker.observe([item(prompt: true)], now: 42).isEmpty, "removed and re-added sessions seed again")
        try check(tracker.observe([item(closed: true)], now: 43).isEmpty, "closed history cannot notify")

        tracker = DesktopNotificationTracker()
        _ = tracker.observe([item(host: "air", busy: true), item(busy: true)], now: 0)
        let remote = tracker.observe([item(host: "air"), item(busy: true)], now: 1)
        try check(remote.count == 1 && remote.first?.target.hostID == "air", "host identity scopes same session ID")
        let target = DesktopNotificationTarget(item(host: "air"))
        try check(DesktopNotificationTarget(userInfo: target.userInfo) == target, "notification target survives property-list round trip")
        try check(DesktopNotificationTarget(userInfo: ["lfgTarget": Data("bad".utf8)]) == nil, "malformed notification is ignored")
        try check(target.resolve(in: [item(), item(host: "air")])?.hostId == "air", "click prefers issuing host")
        try check(target.resolve(in: [item()])?.hostId == "pro", "click follows a moved session")
        try check(target.resolve(in: [item(host: "air", offline: true)]) == nil, "click never uses offline stale rows")
        try check(target.resolve(in: [item(), item(host: "third")]) == nil, "ambiguous moved session is not guessed")

        // Real store + SSE reconciliation, including duplicate delivery.
        let store = SessionStore()
        let entry = Config.HostEntry(url: "https://pro.invalid")
        store.configuredHosts = [entry]
        store.hosts = [HostState(url: entry.url, sshTarget: nil, sessions: [item(busy: true).session])]
        var received: [DesktopNotificationKind] = []
        store.onSessionNotification = { received.append($0.kind) }
        store.receiveStatus(.busy("one", false), host: entry.url)
        store.receiveStatus(.busy("one", false), host: entry.url)
        store.notificationSettleTask?.cancel()
        store.notificationSettleTask = nil
        store.observeNotifications()
        try check(received == [.finished], "live feed delivers exactly one native-notification candidate")
        store.receiveStatus(.busy("one", true), host: "https://removed.invalid")
        try check(received == [.finished], "removed hosts cannot trigger notifications")
        let asking = SessionStore()
        asking.configuredHosts = [entry]
        asking.hosts = [HostState(url: entry.url, sshTarget: nil, sessions: [item(busy: true).session])]
        var kinds: [DesktopNotificationKind] = []
        asking.onSessionNotification = { kinds.append($0.kind) }
        asking.receiveStatus(.busy("one", false), host: entry.url)
        asking.receiveStatus(.prompt("one", DesktopPrompt(question: "Approve?")), host: entry.url)
        asking.notificationSettleTask?.cancel()
        asking.notificationSettleTask = nil
        asking.observeNotifications()
        try check(kinds == [.needsInput], "adjacent busy and prompt frames emit only needs-input")

        try check(DesktopITerm.localTTYs("test\t/dev/ttys001\ntest-other\t/dev/ttys002\n", session: "test") == ["/dev/ttys001"], "local mapping matches exact tmux name")
        let guid = "A345C9E4-CAD6-4A63-8798-191E97702917"
        let parsed = DesktopITerm.parseRemoteDiscovery("ID\tw0t0p0:\(guid)\nARGV\ttmux attach-session -t old-name\nID\tinvalid\n")
        try check(parsed.ids == [guid] && parsed.legacyTargets == ["old-name"], "remote identity strips term coordinates and rejects malformed IDs")
        let command = Opener.remoteAttachCommand(sshTarget: "air", tmuxName: "test's session", moshPath: nil)
        try check(DesktopITerm.matchesRemote(arguments: DesktopITerm.words(command), host: "air", session: "test's session"), "legacy SSH discovery handles shell quoting")
        try check(!DesktopITerm.matchesRemote(arguments: DesktopITerm.words(command), host: "pro", session: "test's session"), "same session name on another host never matches")
        try check(!DesktopITerm.matchesRemote(arguments: DesktopITerm.words(command), host: "air", session: "test"), "prefix session names never match")
        let mosh = Opener.remoteAttachCommand(sshTarget: "air", tmuxName: "test", moshPath: "/usr/local/bin/mosh-bridged")
        try check(DesktopITerm.matchesRemote(arguments: ["/bin/zsh"] + DesktopITerm.words(mosh), host: "air", session: "test"), "legacy Mosh wrapper is recognized")
        let tracked = Opener.remoteAttachCommand(sshTarget: "air", tmuxName: "test", moshPath: "/usr/local/bin/mosh-bridged", trackTerminal: true)
        try check(tracked.contains("LFG_ITERM_SESSION_ID=") && tracked.contains("${lfg_terminal_id:-}") && !tracked.contains("PLACEHOLDER"), "new remote attachments propagate terminal identity through Mosh")
        try check(DesktopITerm.focusScript(ttys: [], ids: [guid]).contains("select s"), "focus selects the pane as well as its tab and window")

        let ports = DesktopITerm.parseRemoteDiscovery("PORT\t60119\nPORT\t0\nPORT\t65536\nPORT\tinvalid\n")
        try check(ports.moshPorts == [60119], "remote discovery accepts only valid Mosh server ports")
        let server = "for p in /usr/bin/python3; do exec \"$p\" \"$HOME/.local/bin/mosh-bridge\" server 60119; done"
        func bridge(_ pid: Int32, _ parent: Int32, _ tty: String, _ command: String = server) -> DesktopITerm.TerminalProcess {
            .init(pid: pid, parentPID: parent, tty: tty,
                  arguments: ["/usr/bin/python3", "/home/me/mosh-bridge", "client", "51765", "--", "ssh", "pro", command])
        }
        let wrapper = DesktopITerm.TerminalProcess(pid: 10, parentPID: 1, tty: "/dev/ttys010",
            arguments: ["/bin/zsh", "/home/me/mosh-bridged", "--ssh=ssh -o ConnectTimeout=5", "pro"])
        let carrier = bridge(11, 10, "/dev/ttys010")
        try check(DesktopITerm.bridgeRemotePorts(carrier.arguments) == [60119], "interactive bridge exposes remote port despite having no tmux target")
        let nested = bridge(12, 10, "/dev/ttys010", "ssh me@192.0.2.1 \(Opener.shq(server)) || exec ssh pro \(Opener.shq(server))")
        try check(DesktopITerm.bridgeRemotePorts(nested.arguments) == [60119], "LAN fallback quoting still resolves the remote port")
        try check(DesktopITerm.moshBridgeTTYs([wrapper, carrier], host: "pro", ports: [60119]) == ["/dev/ttys010"], "interactive Mosh attachment maps to its original terminal")
        try check(DesktopITerm.moshBridgeTTYs([wrapper, carrier], host: "air", ports: [60119]).isEmpty, "same remote port on another host does not match")
        try check(DesktopITerm.moshBridgeTTYs([wrapper, carrier], host: "pro", ports: [60118]).isEmpty, "another session on the same host does not match")
        try check(DesktopITerm.moshBridgeTTYs([carrier], host: "pro", ports: [60119]).isEmpty, "an orphan carrier cannot establish host ownership")
        try check(DesktopITerm.moshBridgeTTYs([wrapper, bridge(12, 10, "/dev/ttys011")], host: "pro", ports: [60119]).isEmpty, "a carrier on a different terminal cannot inherit the wrapper identity")
        let second = DesktopITerm.TerminalProcess(pid: 20, parentPID: 1, tty: "/dev/ttys020", arguments: wrapper.arguments)
        try check(DesktopITerm.moshBridgeTTYs([wrapper, carrier, second, bridge(21, 20, second.tty)], host: "pro", ports: [60119]).isEmpty, "ambiguous bridge terminals are not guessed")
        try check(DesktopITerm.moshBridgeTTYs([wrapper, carrier, bridge(12, 10, wrapper.tty)], host: "pro", ports: [60119]) == [wrapper.tty], "duplicate process evidence on one terminal is harmless")
        let cycle = DesktopITerm.TerminalProcess(pid: 30, parentPID: 30, tty: wrapper.tty, arguments: ["/bin/sh"])
        try check(DesktopITerm.moshBridgeTTYs([cycle, bridge(31, 30, wrapper.tty)], host: "pro", ports: [60119]).isEmpty, "ancestry cycles terminate without a match")
        try check(DesktopITerm.bridgeRemotePorts(["/bin/echo", server]).isEmpty, "arbitrary processes mentioning a bridge cannot match")
        try check(DesktopITerm.Discovery(error: "lookup failed").earlyFocusResult == .failed("lookup failed"), "failed connection discovery cannot fall through to opening another window")
        try check(DesktopITerm.Discovery().earlyFocusResult == .notFound, "a successful empty lookup can open a missing window")
        try check(DesktopITerm.Discovery(ttys: ["/dev/ttys010"]).earlyFocusResult == nil, "a found terminal continues to native focus")
        return count
    }
}
