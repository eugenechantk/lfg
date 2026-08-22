import Foundation

public enum ChildAgentStatus: String, Codable, Sendable, Hashable {
    case running
    case completed
    case failed
    case stopped
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }

    public var isActive: Bool { self == .running }
}

public struct ChildAgentSession: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var description: String
    public var agentType: String
    public var spawnDepth: Int
    public var status: ChildAgentStatus
    public var startedAt: Double?
    public var lastActivityAt: Double?
    public var finishedAt: Double?

    public init(
        id: String,
        description: String = "Child agent",
        agentType: String = "Agent",
        spawnDepth: Int = 1,
        status: ChildAgentStatus = .unknown,
        startedAt: Double? = nil,
        lastActivityAt: Double? = nil,
        finishedAt: Double? = nil
    ) {
        self.id = id
        self.description = description
        self.agentType = agentType
        self.spawnDepth = spawnDepth
        self.status = status
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.finishedAt = finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? "Child agent"
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType) ?? "Agent"
        spawnDepth = try container.decodeIfPresent(Int.self, forKey: .spawnDepth) ?? 1
        status = try container.decodeIfPresent(ChildAgentStatus.self, forKey: .status) ?? .unknown
        startedAt = try container.decodeIfPresent(Double.self, forKey: .startedAt)
        lastActivityAt = try container.decodeIfPresent(Double.self, forKey: .lastActivityAt)
        finishedAt = try container.decodeIfPresent(Double.self, forKey: .finishedAt)
    }
}

public struct ChildAgentSessionsResponse: Codable, Sendable {
    public var id: String?
    public var agents: [ChildAgentSession]

    public init(id: String? = nil, agents: [ChildAgentSession] = []) {
        self.id = id
        self.agents = agents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        agents = try container.decodeIfPresent([ChildAgentSession].self, forKey: .agents) ?? []
    }
}

public struct ChildAgentCollectionPresentation: Sendable, Equatable {
    public let title: String
    public let compactStatus: String
    public let runningCount: Int

    public init(agents: [ChildAgentSession]) {
        let count = agents.count
        title = "\(count) child session\(count == 1 ? "" : "s")"
        let counts = Dictionary(grouping: agents, by: \ChildAgentSession.status)
            .mapValues(\.count)
        runningCount = counts[.running] ?? 0

        if count == 1, let only = agents.first {
            compactStatus = only.status.label
            return
        }

        var parts: [String] = []
        if runningCount > 0 { parts.append("\(runningCount) running") }
        let failed = counts[.failed] ?? 0
        if failed > 0 { parts.append("\(failed) failed") }
        if runningCount == 0 {
            let completed = counts[.completed] ?? 0
            let stopped = counts[.stopped] ?? 0
            let unknown = counts[.unknown] ?? 0
            if completed > 0 { parts.append("\(completed) completed") }
            if stopped > 0 { parts.append("\(stopped) stopped") }
            if unknown > 0 { parts.append("\(unknown) unknown") }
        }
        compactStatus = parts.isEmpty ? "No activity" : parts.prefix(2).joined(separator: " · ")
    }
}

/// Whether the child-sessions bar above the composer should be on screen.
///
/// The bar used to show whenever a session had *ever* spawned a child agent, so
/// once an agent finished it sat above the composer forever — clutter from a
/// turn that ended, in the one place the user is trying to type. But it cannot
/// simply hide on completion either: a finished agent the user has not yet
/// acknowledged is exactly what they may want to open.
///
/// The rule that resolves both: sending a follow-up is the acknowledgement.
/// After a send, work belonging to the *previous* turn is stale and the bar goes
/// away; anything that has been active since the send (including agents the new
/// turn spawns) brings it back. The toolbar's "Child sessions (N)" entry remains
/// the always-available way in, so hiding the bar never loses access.
public enum ChildSessionsBarVisibility {

    /// The most recent moment this agent did anything. Prefers the strongest
    /// signal available; a row may carry any subset of these.
    public static func latestActivity(of agent: ChildAgentSession) -> Double? {
        [agent.finishedAt, agent.lastActivityAt, agent.startedAt]
            .compactMap { $0 }
            .max()
    }

    /// - Parameter lastUserSendAt: epoch **milliseconds** of the most recent
    ///   follow-up the user sent to this session, or nil if they have not sent
    ///   one. Same unit as `ChildAgentSession`'s timestamps and
    ///   `SessionStore.PendingSend.ts` — mixing seconds in here would make every
    ///   send look older than every agent and the bar would never hide.
    public static func shouldShow(
        agents: [ChildAgentSession],
        lastUserSendAt: Double?
    ) -> Bool {
        guard !agents.isEmpty else { return false }
        // Running work is always worth surfacing, no matter what was sent when.
        if agents.contains(where: { $0.status.isActive }) { return true }
        // Never sent anything: nothing has superseded this work yet.
        guard let lastUserSendAt else { return true }
        // Every agent is finished. Show it only if some of that work happened
        // after the last thing the user said; otherwise it belongs to a turn
        // they have already moved on from.
        guard let newestActivity = agents.compactMap(latestActivity(of:)).max() else {
            // No timestamps at all to reason with. A send is the more recent
            // known event, so treat the agents as the older news.
            return false
        }
        return lastUserSendAt < newestActivity
    }
}

public enum SessionWorkListPresentation {
    public static func childAgentLabel(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) child agent\(count == 1 ? "" : "s") running"
    }

    public static func backgroundProcessLabel(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) background process\(count == 1 ? "" : "es") running"
    }
}
