import AppIntents
import Foundation
import LFGCore
import UserNotifications
import os

private let logger = Logger(subsystem: "dev.omg.lfg", category: "StartSessionIntent")

/// The result of "Start Session", for the rest of the Shortcut: typically
/// Show Alert (Title, Message) → Open URLs (Link), so OK opens the session.
struct StartedSession: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Started Session" }

    @Property(title: "Title") var title: String
    @Property(title: "Message") var message: String
    @Property(title: "Link") var link: URL?
    @Property(title: "Session ID") var sessionID: String
    @Property(title: "Project") var project: String
    @Property(title: "Host") var host: String
    @Property(title: "Agent") var agent: String
    @Property(title: "Model") var model: String

    init() {
        title = ""; message = ""; link = nil; sessionID = ""; project = ""; host = ""; agent = ""; model = ""
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(message)")
    }
}

/// Shortcuts action: start a Claude Code / Codex session on a host without opening lfg. Returns a
/// Started Session (title, message, link) for a Show Alert → Open URLs pair; can also post an
/// "Action completed" notification carrying the same `sid` a server push does, so PushManager's
/// existing tap handler opens the session.
///
/// Unlike an `lfg://new` link (which any app can open, so New Session waits for a tap), an App
/// Intent only runs when the user runs it — from Shortcuts, Siri or the Action button — so it
/// starts the session directly.
struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource { "Start Session" }
    static var description: IntentDescription {
        IntentDescription("Starts an lfg session with this prompt without opening the app. Returns a Started Session — show its Title and Message with Show Alert, then Open URLs with its Link to jump to the session. Project, host, agent and model match loosely; anything left empty uses lfg's defaults. Optionally also posts a notification.")
    }
    // lfg supports iOS 18, where `supportedModes` doesn't exist; this runs it in the background.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Prompt") var prompt: String
    @Parameter(title: "Project", description: "A project name, inbox, root, or a path. Empty = Inbox.") var project: String?
    @Parameter(title: "Host", description: "A host's name as lfg shows it. Empty = your default host.") var host: String?
    @Parameter(title: "Agent", description: "claude or codex. Empty = your last choice.") var agent: String?
    @Parameter(title: "Model", description: "e.g. opus, sonnet, astra, gpt-5.5. Empty = default.") var model: String?
    @Parameter(title: "Notify When Done", description: "Also post an “Action completed” notification; tapping it opens the session.", default: false)
    var notify: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$prompt) in lfg") { \.$project; \.$host; \.$agent; \.$model; \.$notify }
    }

    enum StartError: LocalizedError {
        case emptyPrompt, noHost, noDirectory, noSessionId, unreachable(String, String)
        var errorDescription: String? {
            switch self {
            case .emptyPrompt: return "There's no prompt to send."
            case .noHost: return "lfg has no host set up. Open lfg › Settings."
            case .noDirectory: return "Couldn't find the Inbox directory on the host."
            case .noSessionId: return "The host didn't return a session."
            case .unreachable(let host, let why): return "Couldn't reach \(host): \(why)"
            }
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<StartedSession> {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StartError.emptyPrompt }

        let settings = AppSettings()
        let fallback = settings.hosts.first { $0.isDefault } ?? settings.hosts.first
        guard let target = StartSessionPlanner.host(hint: host, hosts: settings.hosts, fallback: fallback),
              let client = settings.client(for: target) else { throw StartError.noHost }

        let dirs: DirsResponse
        do { dirs = try await client.dirs() } catch {
            throw StartError.unreachable(target.label, error.localizedDescription)
        }
        let directory = StartSessionPlanner.directory(hint: project, dirs: dirs)
        guard !directory.path.isEmpty else { throw StartError.noDirectory }
        let catalog = (try? await client.models()) ?? .fallback
        let selection = StartSessionPlanner.selection(agent: agent, model: model, catalog: catalog,
                                                      remembered: settings.lastNewSessionModelSelection)
        let plan = StartSessionPlan(host: target, directory: directory, selection: selection)

        let response = try await client.newSession(NewSessionRequest(
            cwd: directory.path, prompt: text, agent: selection.agent.rawValue,
            model: selection.model, user: settings.defaultOwner))
        guard let sid = response.sessionId, !sid.isEmpty else { throw StartError.noSessionId }
        settings.noteRecentDir(directory.path)
        logger.notice("started \(sid, privacy: .public) in \(directory.path, privacy: .public) on \(target.logLabel, privacy: .public)")

        let note = StartSessionPlanner.notification(prompt: text, plan: plan)
        if notify { await Self.notify(title: note.title, body: note.body, sid: sid) }
        var result = StartedSession()
        result.title = note.title
        result.message = note.body
        result.link = URL(string: "lfg://session/\(sid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sid)")
        result.sessionID = sid
        result.project = directory.name
        result.host = target.label
        result.agent = selection.agent.rawValue
        result.model = selection.model
        return .result(value: result)
    }

    private static func notify(title: String, body: String, sid: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sid": sid]          // PushNotification(userInfo:) → open this session on tap
        try? await center.add(UNNotificationRequest(identifier: "start-\(sid)", content: content, trigger: nil))
    }
}

/// Lists "Start Session" in Shortcuts, Spotlight and Siri without building a Shortcut first.
struct LFGShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: ["Start a session in \(.applicationName)", "Start an \(.applicationName) session"],
            shortTitle: "Start Session",
            systemImageName: "terminal"
        )
    }
}
