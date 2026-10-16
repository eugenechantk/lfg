import Foundation

// The desktop Sessions list (S2, canvas board `dA2-sessions`, a 400pt window):
// three groups, a time column, a meta line and a status line per row. Pure, so it
// is tested here; desktop/build.sh compiles this file (and SessionListRow.swift,
// for `SessionRowLine`) straight into the Mac app.

/// The three groups the desktop list shows, in order.
public enum DesktopListGroup: String, CaseIterable, Sendable, Identifiable {
    case needsInput, working, recent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsInput: return "Needs input"
        case .working: return "Working"
        case .recent: return "Recent"
        }
    }
}

/// What the desktop knows about one row, in plain values.
public struct DesktopRowFacts: Sendable, Equatable {
    public enum State: Sendable, Equatable { case needsInput, paused, working, idle, closed }

    public var state: State
    public var question: String?
    public var promptKind: String?
    public var permissionCommand: String?
    public var signInWebsite: String?
    public var pausedReason: String?
    public var hostLabel: String
    public var hostOffline: Bool
    public var moving: Bool

    public init(state: State, question: String? = nil, promptKind: String? = nil,
                permissionCommand: String? = nil, signInWebsite: String? = nil,
                pausedReason: String? = nil, hostLabel: String, hostOffline: Bool = false,
                moving: Bool = false) {
        self.state = state; self.question = question; self.promptKind = promptKind
        self.permissionCommand = permissionCommand; self.signInWebsite = signInWebsite
        self.pausedReason = pausedReason; self.hostLabel = hostLabel
        self.hostOffline = hostOffline; self.moving = moving
    }
}

public enum DesktopSessionList {
    /// Paused (an API error) needs you, so it sits with Needs input; idle and
    /// closed sessions are Recent.
    public static func group(_ state: DesktopRowFacts.State) -> DesktopListGroup {
        switch state {
        case .needsInput, .paused: return .needsInput
        case .working: return .working
        case .idle, .closed: return .recent
        }
    }

    /// The line under the meta. An offline host's row says so (the view dims it).
    public static func line(_ f: DesktopRowFacts) -> SessionRowLine {
        if f.moving { return SessionRowLine(icon: .none, text: "Moving…", tone: .secondary) }
        if f.hostOffline { return SessionRowLine(icon: .none, text: "\(f.hostLabel) is offline", tone: .secondary) }
        switch f.state {
        case .needsInput:
            if let site = trimmed(f.signInWebsite) {
                return SessionRowLine(icon: .signIn, text: "Sign in to \(site)", tone: .attention)
            }
            if f.promptKind == "permission", let program = program(in: f.permissionCommand) {
                return SessionRowLine(icon: .question, text: "Asks to run \(program)", tone: .attention)
            }
            if f.promptKind == "plan" {
                return SessionRowLine(icon: .question, text: "Asks to approve a plan", tone: .attention)
            }
            let q = SessionRowLine.oneLine(f.question ?? "")
            return SessionRowLine(icon: .question, text: q.isEmpty ? "Needs your input" : "Asks: \(q)", tone: .attention)
        case .paused:
            return SessionRowLine.resolve(.paused(reason: f.pausedReason), nowMs: 0)
        case .working:
            return SessionRowLine(icon: .liveDot, text: "Working", tone: .live)
        case .idle:
            return SessionRowLine(icon: .none, text: "Ready for your next message", tone: .secondary)
        case .closed:
            return SessionRowLine(icon: .none, text: "Closed", tone: .secondary)
        }
    }

    /// The time column: "2m" over "ago". Under a minute reads "now" with no
    /// second line; past a week it counts weeks, past a year years.
    public static func age(fromMs: Double?, nowMs: Double) -> (value: String, suffix: String) {
        guard let fromMs else { return ("", "") }
        let s = max(0, (nowMs - fromMs) / 1000)
        if s < 60 { return ("now", "") }
        let m = Int(s / 60)
        if m < 60 { return ("\(m)m", "ago") }
        let h = m / 60
        if h < 24 { return ("\(h)h", "ago") }
        let d = h / 24
        if d < 7 { return ("\(d)d", "ago") }
        if d < 365 { return ("\(d / 7)w", "ago") }
        return ("\(d / 365)y", "ago")
    }

    /// "fiftystrong · Pro · Claude Code opus · from a task".
    public static func meta(project: String, host: String, agent: String, model: String?, fromTask: Bool) -> String {
        var agentText = agentLabel(agent)
        if let short = shortModel(model, agent: agent) { agentText += " \(short)" }
        var parts = [project, host, agentText].filter { !$0.isEmpty }
        if fromTask { parts.append("from a task") }
        return parts.joined(separator: " · ")
    }

    public static func agentLabel(_ agent: String) -> String {
        switch agent {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        default: return agent
        }
    }

    /// Claude models read as their family ("opus"); other agents keep the id.
    public static func shortModel(_ model: String?, agent: String) -> String? {
        guard let m = trimmed(model) else { return nil }
        if agent == "claude" {
            let lower = m.lowercased()
            for family in ["opus", "sonnet", "haiku", "fable"] where lower.contains(family) { return family }
        }
        return m
    }

    /// "launchctl" from "sudo /bin/launchctl kickstart -k gui/501/x".
    public static func program(in command: String?) -> String? {
        guard let command = trimmed(command) else { return nil }
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = tokens.first(where: { !$0.contains("=") && $0 != "sudo" && $0 != "env" }) else { return nil }
        let name = first.split(separator: "/").last.map(String.init) ?? first
        return name.isEmpty ? nil : name
    }

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
