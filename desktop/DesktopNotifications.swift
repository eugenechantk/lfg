import AppKit
import SwiftUI
import UserNotifications

struct DesktopNotificationTarget: Codable, Equatable, Sendable {
    let sessionID: String
    let hostID: String
    let hostURL: String

    init(_ item: SessionItem) {
        sessionID = item.session.sessionId ?? ""
        hostID = item.hostId
        hostURL = item.hostURL
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let data = userInfo["lfgTarget"] as? Data,
              let target = try? JSONDecoder().decode(Self.self, from: data),
              !target.sessionID.isEmpty, !target.hostID.isEmpty, !target.hostURL.isEmpty else { return nil }
        self = target
    }

    var userInfo: [AnyHashable: Any] { ["lfgTarget": (try? JSONEncoder().encode(self)) ?? Data()] }

    /// Prefer the issuing host; a session may have moved since the alert arrived.
    func resolve(in items: [SessionItem]) -> SessionItem? {
        let live = items.filter { $0.session.sessionId == sessionID && !$0.session.closed && !$0.hostOffline }
        return live.first { $0.hostId == hostID } ?? (live.count == 1 ? live.first : nil)
    }
}

struct DesktopNotificationSettingsView: View {
    @ObservedObject private var notifications = DesktopNotificationController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Session notifications").font(.headline)
                Spacer()
                Button(notifications.permission == .notDetermined ? "Enable Notifications" : "Notification Settings…") {
                    if notifications.permission == .notDetermined {
                        Task { await notifications.requestPermission() }
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.eugenechan.lfg-desktop") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .accessibilityIdentifier("desktop_notification_settings")
            }
            Text(notifications.permission == .denied
                 ? "Notifications are off in macOS. Enable them to receive session alerts."
                 : "Get alerts when an agent finishes or needs input. Click an alert to open its iTerm session.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = notifications.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task { await notifications.requestPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.requestPermission() }
        }
    }
}

/// Uses the same payload, posting, and routing as production without a fake
/// provider turn. Discovery mode only reads the current terminal attachments.
enum DesktopNotificationProbeCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.dropFirst().first == "--notification-probe", args.count >= 3 else { return }
        var finished = false
        Task { @MainActor in
            let controller = DesktopNotificationController.shared
            if args[2] == "status" {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                print("notification authorization: \(settings.authorizationStatus.rawValue)")
            } else {
                let store = SessionStore()
                await store.refresh()
                if let item = store.notificationItems.first(where: { $0.session.sessionId == args[2] }) {
                    if args.dropFirst(3).first == "discover" {
                        let found = await Task.detached { DesktopITerm.discover(item) }.value
                        var payload: [String: Any] = ["sessionID": args[2], "host": item.hostLabel,
                            "local": item.hostIsLocal, "ttys": found.ttys.sorted(), "ids": found.ids.sorted()]
                        if let error = found.error { payload["error"] = error }
                        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                           let json = String(data: data, encoding: .utf8) { print(json) }
                    } else if args.dropFirst(3).first == "open" {
                        print(await store.openNotification(DesktopNotificationTarget(item)) ?? "opened")
                    } else {
                        controller.start(store: store)
                        await controller.requestPermission()
                        controller.post(DesktopSessionNotification(item: item, kind: .finished))
                        try? await Task.sleep(for: .seconds(2))
                        print(controller.error ?? "notification submitted")
                    }
                } else { print("session not found") }
            }
            finished = true
        }
        while !finished { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        fflush(stdout)
        Darwin.exit(0)
    }
}

struct DesktopAssistantPreview: Decodable, Hashable {
    let role: String
    let kind: String
    let text: String
    let ts: Double?
}

struct DesktopSessionNotice: Decodable, Hashable, Sendable {
    let id: String
    let status: String
    let title: String
    let message: String
    let createdAt: Double
    let turnStartedAt: Double?
    var label: String {
        switch status {
        case "completed": return "Completed"
        case "needs-input": return "Needs input"
        case "blocked": return "Blocked"
        case "reminder": return "Reminder"
        default: return "Working"
        }
    }
    var kind: DesktopNotificationKind {
        switch status {
        case "completed": return .finished
        case "needs-input", "blocked": return .needsInput
        default: return .status
        }
    }
    func completes(_ session: APISession) -> Bool {
        status == "completed" && (session.lastUserAt == nil || createdAt >= session.lastUserAt!)
    }
}

enum DesktopNotificationKind: String { case finished, needsInput = "needs-input", status }

extension APISession {
    var completionReceipt: DesktopSessionNotice? {
        completionNotification ?? (notification?.status == "completed" ? notification : nil)
    }
}

struct DesktopSessionNotification {
    let item: SessionItem
    let kind: DesktopNotificationKind
    var custom: DesktopSessionNotice? = nil
    var target: DesktopNotificationTarget { DesktopNotificationTarget(item) }
    var title: String {
        if let custom { return custom.title }
        let name = [item.session.title, item.session.tmuxName ?? "", String((item.session.sessionId ?? "").prefix(8)), "Session"]
            .first { !$0.isEmpty }!
        return (kind == .finished ? "✅ " : "🙋 ") + Self.clip(name, limit: 48)
    }
    var body: String {
        if let custom { return "\(custom.label): \(custom.message)" }
        if kind == .finished, let last = item.session.last, last.role == "assistant", last.kind == "text",
           let ts = last.ts, let userAt = item.session.lastUserAt, ts >= userAt, !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = last.text.replacingOccurrences(of: "<oai-mem-citation>[\\s\\S]*?</oai-mem-citation>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
            return "Finished: \(Self.clip(text, limit: 350))"
        }
        return kind == .finished ? "The agent finished its turn."
            : item.session.prompt?.question.flatMap { $0.isEmpty ? nil : Self.clip($0, limit: 140) }
                ?? "An agent is waiting for your input."
    }
    private static func clip(_ value: String, limit: Int) -> String {
        let value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.count > limit ? String(value.prefix(limit - 1)) + "…" : value
    }
}

/// Mirrors src/push/watcher.ts reduceTransition. First observations only seed;
/// prompts suppressed by the ten-second cooldown remain pending for the next tick.
struct DesktopNotificationTracker {
    struct Key: Hashable { let host: String; let session: String }
    struct State {
        var busy: Bool; var prompt: Bool; var lastNotified: TimeInterval = -.infinity
        var notificationID: String? = nil
        var completionID: String? = nil
        var completionAnnounced = false
        var completedThrough: Double? = nil
        var lastUserAt: Double? = nil
    }
    private var prior: [Key: State] = [:]

    mutating func seedMissing(_ items: [SessionItem]) {
        for item in items where !item.hostOffline && !item.session.closed {
            guard let sid = item.session.sessionId, !sid.isEmpty else { continue }
            let key = Key(host: item.hostId, session: sid)
            if prior[key] == nil {
                let completion = item.session.completionReceipt
                prior[key] = State(busy: item.session.busy, prompt: item.needsInput || item.session.prompt != nil,
                                   notificationID: item.session.notification?.id,
                                   completionID: completion?.id,
                                   completionAnnounced: item.session.suppressCompletionNotification || completion?.completes(item.session) == true,
                                   completedThrough: completion?.createdAt,
                                   lastUserAt: item.session.lastUserAt)
            }
        }
    }

    mutating func observe(_ items: [SessionItem], now: TimeInterval = Date().timeIntervalSince1970) -> [DesktopSessionNotification] {
        var seen = Set<Key>()
        var notifications: [DesktopSessionNotification] = []
        for item in items {
            guard let sid = item.session.sessionId, !sid.isEmpty, !item.session.closed else { continue }
            let key = Key(host: item.hostId, session: sid)
            guard seen.insert(key).inserted, !item.hostOffline else { continue }
            let busy = item.session.busy
            let prompt = item.needsInput || item.session.prompt != nil
            let completion = item.session.completionReceipt
            var next = State(busy: busy, prompt: prompt, notificationID: item.session.notification?.id,
                             completionID: completion?.id,
                             completionAnnounced: item.session.suppressCompletionNotification || completion?.completes(item.session) == true,
                             completedThrough: completion?.createdAt,
                             lastUserAt: item.session.lastUserAt)
            guard let previous = prior[key] else { prior[key] = next; continue }
            next.lastNotified = previous.lastNotified
            next.completionAnnounced = previous.completionAnnounced
            next.completedThrough = previous.completedThrough
            next.completionID = completion?.id ?? previous.completionID
            // A new interval can start before REST refreshes its user timestamp.
            // Clear the latch on that edge as well as a newer known user turn.
            if (!previous.busy && busy) || (next.lastUserAt != nil && previous.completedThrough != nil && next.lastUserAt! > previous.completedThrough!) {
                next.completionAnnounced = false
                next.completedThrough = nil
            }
            if let completion, completion.id != previous.completionID, completion.completes(item.session) {
                // A separate receipt repairs missed events even if the latest
                // alert is now a reminder. Old receipts cannot rearm a new turn.
                next.completionAnnounced = true
                next.completedThrough = completion.createdAt
            }
            if let custom = item.session.notification, previous.notificationID != custom.id {
                next.lastNotified = now
                notifications.append(DesktopSessionNotification(item: item, kind: custom.kind, custom: custom))
                prior[key] = next
                continue
            }
            let candidate: DesktopNotificationKind? = !previous.prompt && prompt ? .needsInput
                : previous.busy && !busy && !prompt && !next.completionAnnounced ? .finished : nil
            if let candidate, now - previous.lastNotified >= 10 {
                next.lastNotified = now
                notifications.append(DesktopSessionNotification(item: item, kind: candidate))
            } else if candidate == .needsInput {
                next.prompt = false
            }
            prior[key] = next
        }
        // Keep offline hosts' last state, but discard removed hosts and sessions.
        prior = prior.filter { seen.contains($0.key) }
        return notifications
    }
}

@MainActor
final class DesktopNotificationController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = DesktopNotificationController()
    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var error: String?
    weak var store: SessionStore?
    private var opening = Set<String>()
    private let center = UNUserNotificationCenter.current()

    func start(store: SessionStore) {
        self.store = store
        center.delegate = self
        store.onSessionNotification = { [weak self] note in self?.post(note) }
        Task { await requestPermission() }
    }

    func requestPermission() async {
        do {
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            }
            permission = await center.notificationSettings().authorizationStatus
        } catch { self.error = error.localizedDescription }
    }

    func post(_ note: DesktopSessionNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.subtitle = note.item.hostLabel
        content.body = note.body
        content.sound = .default
        content.userInfo = note.target.userInfo
        content.threadIdentifier = note.item.id
        let request = UNNotificationRequest(identifier: "lfg-session-\(UUID().uuidString)", content: content, trigger: nil)
        Task {
            do { try await center.add(request) }
            catch { self.error = "Couldn’t send notification: \(error.localizedDescription)" }
        }
    }

    func open(_ target: DesktopNotificationTarget) async {
        guard let store, opening.insert(target.sessionID).inserted else { return }
        defer { opening.remove(target.sessionID) }
        if let failure = await store.openNotification(target) {
            error = failure
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn’t open session"
            alert.informativeText = failure
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let target = DesktopNotificationTarget(userInfo: response.notification.request.content.userInfo) {
            Task { @MainActor in await self.open(target) }
        }
        completionHandler()
    }
}

extension SessionStore {
    var notificationItems: [SessionItem] {
        hosts.flatMap { host in
            host.sessions.filter { !$0.closed }.map { session in
                SessionItem(session: session, hostURL: host.url, hostId: host.info?.hostId ?? host.url,
                            hostLabel: host.label, hostIsLocal: host.isLocal, hostSSHTarget: host.sshTarget,
                            hostRemoteTransport: host.remoteTransport,
                            needsInput: host.needsInputSessionIds.contains(session.sessionId ?? ""), hostOffline: host.error != nil)
            }
        }
    }

    func observeNotifications(now: TimeInterval = Date().timeIntervalSince1970) {
        guard notificationSettleTask == nil else { return }
        for note in notificationTracker.observe(notificationItems, now: now) { onSessionNotification?(note) }
    }

    func settleNotifications() {
        guard notificationSettleTask == nil else { return }
        // busy and prompt are adjacent journal frames. Observe the complete
        // state so a question doesn't first announce a misleading completion.
        notificationSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.notificationSettleTask = nil
            self.observeNotifications()
        }
    }

    func openNotification(_ target: DesktopNotificationTarget) async -> String? {
        guard configuredHosts.contains(where: { $0.url == target.hostURL }) else {
            return "The notification’s host is no longer configured. Add it in Settings to open this session."
        }
        let entry = configuredHosts.first { $0.url == target.hostURL }!
        let source = await Self.fetchHost(entry: entry)
        func items(_ host: HostState) -> [SessionItem] {
            host.sessions.map { SessionItem(session: $0, hostURL: host.url,
                hostId: host.info?.hostId ?? host.url, hostLabel: host.label, hostIsLocal: host.isLocal,
                hostSSHTarget: host.sshTarget, hostRemoteTransport: host.remoteTransport, hostOffline: host.error != nil) }
        }
        if let item = target.resolve(in: items(source)), item.hostId == target.hostID {
            return await Task.detached { Opener.open(item) }.value
        }
        let otherHosts = configuredHosts.filter { $0.url != target.hostURL }
        let otherItems = await withTaskGroup(of: HostState.self, returning: [SessionItem].self) { group in
            for entry in otherHosts { group.addTask { await Self.fetchHost(entry: entry) } }
            var result: [SessionItem] = []
            for await host in group { result += items(host) }
            return result
        }
        if let item = target.resolve(in: otherItems) {
            return await Task.detached { Opener.open(item) }.value
        }
        guard source.info?.hostId == target.hostID, source.error == nil else {
            return "The session’s host is offline. Reconnect it and click the notification again."
        }
        guard !otherItems.contains(where: { $0.session.sessionId == target.sessionID }) else {
            return "More than one host reports this session. Open its current host from LFG."
        }
        let host = source
        // Resume on the original host, preserving remote ownership and cwd.
        guard let url = URL(string: host.url + "/api/sessions/resume") else { return "Invalid host URL." }
        var request = DesktopAPI.request(url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": target.sessionID])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                return body?["error"] as? String ?? "The host couldn’t reopen this session."
            }
            let resumed = try JSONDecoder().decode(DesktopNewSessionResponse.self, from: data)
            let item = try DesktopSessionCreator.createdItem(response: resumed,
                plan: DesktopNewSessionPlan(hostURL: host.url, cwd: resumed.cwd ?? "", agent: resumed.agent ?? "codex", model: ""), host: host)
            return await Task.detached { Opener.open(item) }.value
        } catch { return "Couldn’t reconnect to the session: \(error.localizedDescription)" }
    }
}
