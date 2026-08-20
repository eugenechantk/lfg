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
