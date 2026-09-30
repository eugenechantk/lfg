import Foundation

/// Selects the clock shown on a session list row. A live process can keep
/// working across many messages, so message age is not its running duration.
public enum SessionListTime: Equatable, Sendable {
    case runningSince(Double)
    case lastActivity(Double)

    public static func resolve(session: Session, isWorking: Bool) -> Self? {
        if isWorking {
            guard let startedAt = session.startedAt else { return nil }
            return .runningSince(startedAt)
        }
        guard let lastActivityAt = session.lastActivityAt else { return nil }
        return .lastActivity(lastActivityAt)
    }

    public var timestamp: Double {
        switch self {
        case .runningSince(let timestamp), .lastActivity(let timestamp): timestamp
        }
    }
}
