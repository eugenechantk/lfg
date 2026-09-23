import Foundation

public enum SessionHandoff {
    public struct ModelSection: Sendable {
        public let agent: AgentKind
        public let title: String
        public var models: [String] { agent.models }
    }

    public static func modelSections(current: AgentKind, closed: Bool = false) -> [ModelSection] {
        let other: AgentKind = current == .claude ? .codex : .claude
        return [
            ModelSection(agent: current, title: closed ? "Resume with model" : "Switch in place"),
            ModelSection(agent: other, title: "Switch to \(other == .claude ? "Claude Code" : "Codex")"),
        ]
    }

    public enum ModelSwitchRoute: Equatable, Sendable { case inPlace, resume, handoff }

    public static func modelSwitchRoute(from source: AgentKind, to target: AgentKind, closed: Bool) -> ModelSwitchRoute {
        if source != target { return .handoff }
        return closed ? .resume : .inPlace
    }

    /// Live sources stay on their owner. Closed sessions have no live routing
    /// entry: use a reachable host that actually advertised this transcript.
    public static func sourceHost(
        sessionId: String,
        liveOwner: Host?,
        copies: [(host: Host, sessions: [ResumableSession])],
        isReachable: (Host) -> Bool
    ) -> Host? {
        if let liveOwner { return liveOwner }
        var best: (host: Host, timestamp: Double)?
        for copy in copies where isReachable(copy.host) {
            for session in copy.sessions where session.sessionId == sessionId {
                let timestamp = session.mtime ?? 0
                if best == nil || timestamp > best!.timestamp { best = (copy.host, timestamp) }
            }
        }
        return best?.host
    }
}
