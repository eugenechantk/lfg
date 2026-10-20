import Foundation

/// Client-requested closes outlive individual live and history snapshots.
/// Keep a pending row stable until the host acknowledges the request, then
/// suppress that row for this run without deleting its transcript history.
public struct SessionCloseTracking: Sendable {
    private var pending: [String: Session] = [:]
    private var ended: Set<String> = []

    public init() {}

    public static func canEnd(_ session: Session) -> Bool {
        guard let id = session.sessionId, !id.isEmpty, !id.hasPrefix("local-") else { return false }
        return !session.closed && !session.isExternallyOwned
    }

    public var pendingIDs: Set<String> { Set(pending.keys) }
    public func isEnding(_ id: String) -> Bool { pending[id] != nil }
    public func isEnded(_ id: String) -> Bool { ended.contains(id) }

    @discardableResult
    public mutating func begin(_ session: Session) -> Bool {
        guard Self.canEnd(session), !isEnding(session.id), !isEnded(session.id) else { return false }
        pending[session.id] = session
        return true
    }

    public mutating func finish(_ id: String, succeeded: Bool) {
        guard pending.removeValue(forKey: id) != nil else { return }
        if succeeded { ended.insert(id) }
    }

    /// A manually resumed conversation may use the same ID again.
    public mutating func clearEnded(_ id: String) { ended.remove(id) }

    public func preservingPending(in sessions: [Session]) -> [Session] {
        let ids = Set(sessions.map(\.id))
        return sessions.map { pending[$0.id] ?? $0 }
            + pending.keys.sorted().filter { !ids.contains($0) }.compactMap { pending[$0] }
    }
}
