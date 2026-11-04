import Foundation

// The S2 Sessions list: which section a row lands in, what its second line says,
// and what its meta line lists. Pure, so the list's rules are tested here rather
// than eyeballed in the simulator. Design: LFG UI Map canvas, board `s2-list`.

/// A row's display state, as the app's grouping ladder resolves it. Mirrors
/// `SessionStore.Group` one-to-one; the app maps between them in one switch.
public enum SessionRowGroup: Sendable, Equatable {
    case needsInput, paused, restarting, working, unread, idle, closed
}

/// The five sections the S2 list shows. Paused (an API error) needs you, so it
/// folds into Needs input; Restarting is on its way to Working, so it folds there.
public enum SessionListSection: String, CaseIterable, Sendable, Identifiable {
    case needsInput, working, unread, idle, closed

    public var id: String { rawValue }

    public init(_ group: SessionRowGroup) {
        switch group {
        case .needsInput, .paused: self = .needsInput
        case .restarting, .working: self = .working
        case .unread: self = .unread
        case .idle: self = .idle
        case .closed: self = .closed
        }
    }

    public var title: String {
        switch self {
        case .needsInput: return "Needs input"
        case .working: return "Working"
        case .unread: return "Unread"
        case .idle: return "Idle"
        case .closed: return "Closed"
        }
    }

    /// Idle and Closed are long and rarely acted on, so they start folded.
    public var collapsedByDefault: Bool { self == .idle || self == .closed }
}

/// Which sections the user has folded, persisted as a small JSON string. Until
/// the user touches anything the defaults apply; after that their choice wins.
public struct SessionListCollapse: Equatable, Sendable {
    private var collapsed: Set<String>

    public init(stored: String?) {
        if let stored, let data = stored.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            collapsed = Set(ids)
        } else {
            collapsed = Set(SessionListSection.allCases.filter(\.collapsedByDefault).map(\.rawValue))
        }
    }

    public func isCollapsed(_ section: SessionListSection) -> Bool {
        collapsed.contains(section.rawValue)
    }

    public mutating func toggle(_ section: SessionListSection) {
        if collapsed.contains(section.rawValue) { collapsed.remove(section.rawValue) }
        else { collapsed.insert(section.rawValue) }
    }

    public var stored: String {
        let data = (try? JSONEncoder().encode(collapsed.sorted())) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// The row's second line: what state the session is in. Deliberately no live
/// step text and no message preview (Eugene, 2026-10-15: not needed, and both
/// cost server work).
public struct SessionRowLine: Equatable, Sendable {
    public enum Icon: Equatable, Sendable { case none, question, signIn, liveDot }
    /// Attention is amber, live is green, ending is red, and secondary is grey.
    public enum Tone: Equatable, Sendable { case attention, live, ending, primary, secondary }

    public enum State: Equatable, Sendable {
        case ending
        case needsInput(question: String?, signInSite: String?)
        case paused(reason: String?)
        case restarting
        case working(runningSinceMs: Double?)
        case unread
        case idle
        case closed(lastActivityMs: Double?)
    }

    public let icon: Icon
    public let text: String
    public let tone: Tone

    public init(icon: Icon, text: String, tone: Tone) {
        self.icon = icon; self.text = text; self.tone = tone
    }

    public static func resolve(_ state: State, nowMs: Double, calendar: Calendar = .current) -> SessionRowLine {
        switch state {
        case .ending:
            return SessionRowLine(icon: .none, text: "Ending session…", tone: .ending)
        case let .needsInput(question, site):
            if let site = site?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty {
                return SessionRowLine(icon: .signIn, text: "Sign in to \(site)", tone: .attention)
            }
            let q = oneLine(question ?? "")
            return SessionRowLine(icon: .question, text: q.isEmpty ? "Needs your input" : "Asks: \(q)", tone: .attention)
        case let .paused(reason):
            let r = (reason ?? "").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            return SessionRowLine(icon: .none, text: r.isEmpty ? "Paused" : "Paused · \(r)", tone: .attention)
        case .restarting:
            return SessionRowLine(icon: .liveDot, text: "Restarting…", tone: .live)
        case let .working(since):
            let text = since.map { "Working \(compactDuration(from: $0, to: nowMs))" } ?? "Working"
            return SessionRowLine(icon: .none, text: text, tone: .live)
        case .unread:
            return SessionRowLine(icon: .none, text: "New reply", tone: .primary)
        case .idle:
            return SessionRowLine(icon: .none, text: "", tone: .secondary)
        case .closed:
            return SessionRowLine(icon: .none, text: "", tone: .secondary)
        }
    }

    /// "45s", "3m", "2h", "1d", "3w" — the same steps the list's time used before.
    public static func compactDuration(from startMs: Double, to nowMs: Double) -> String {
        let seconds = max(0, Int((nowMs - startMs) / 1000))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }

    /// Wake a row only when its compact age can change. A one-hour-old row
    /// needs one update per hour, rather than 3,600 identical body updates.
    public static func nextDurationUpdate(from startMs: Double, after nowMs: Double) -> Double? {
        guard startMs.isFinite, nowMs.isFinite else { return nil }
        let elapsed = max(0, (nowMs - startMs) / 1_000)
        let unit: Double
        switch elapsed {
        case ..<60: unit = 1
        case ..<3_600: unit = 60
        case ..<86_400: unit = 3_600
        case ..<604_800: unit = 86_400
        default: unit = 604_800
        }
        // Date's seconds-to-milliseconds round trip can land just below an
        // exact boundary. Always advance so TimelineView cannot repeat it.
        return max(nowMs + 1, startMs + (floor(elapsed / unit) + 1) * unit * 1_000)
    }

    /// Collapses whitespace and newlines to single spaces (shared with the desktop row).
    public static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func endedPhrase(lastMs: Double, nowMs: Double, calendar: Calendar) -> String {
        let last = calendar.startOfDay(for: Date(timeIntervalSince1970: lastMs / 1000))
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: nowMs / 1000))
        let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }
}

/// The row's third line, minus the task icon and host, which the view draws.
public enum SessionRowMeta {
    public static func text(project: String, model: String?, subagents: Int,
                            backgroundProcesses: Int, time: String?) -> String {
        var parts = [project]
        if let model, !model.isEmpty { parts.append(model) }
        if subagents > 0 { parts.append("\(subagents) subagent\(subagents == 1 ? "" : "s")") }
        if backgroundProcesses > 0 { parts.append("\(backgroundProcesses) background") }
        if let time { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    public static func projectLabel(cwd: String?, project: String?) -> String {
        if let cwd, !cwd.isEmpty, let leaf = cwd.split(separator: "/").last { return String(leaf) }
        if let project, !project.isEmpty { return project }
        return "No directory"
    }
}

/// The scheduled task that started a session (server: `src/task-origin.ts`).
public struct TaskOrigin: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }

    /// The task list scopes its identities by configured host, not machine ID.
    public func hostedTaskID(hostID: String) -> String? {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "\(hostID):\(id)"
    }
}

/// Presentation membership only. Keep the source population for chat routing,
/// notifications and deep links, including closed results returned by older hosts.
public enum SessionListMembership {
    public static func includes(kind: String? = nil, sessionID: String? = nil,
                                parentSessionID: String? = nil, purpose: String? = nil,
                                cwd: String? = nil, hideChatSessions: Bool = true) -> Bool {
        guard purpose != "task-edit" else { return false }
        guard hideChatSessions else { return true }
        guard kind != "chat",
              sessionID?.hasPrefix("chat-") != true,
              parentSessionID?.hasPrefix("chat-") != true else { return false }
        // The server normally suppresses provider workers. Match only its exact
        // durable-chat directory shape; ordinary projects named chat stay visible.
        if let cwd, cwd.range(of: #"[/-]chat-sessions[/-]chat-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}[/-]provider(?:$|[/-])"#,
                              options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return true
    }
}
