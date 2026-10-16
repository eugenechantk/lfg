import Foundation

/// When a journal event names a session the list does not know, decide whether
/// to refresh the list for it.
///
/// A session that asks a question the moment it starts emits `busy` and
/// `prompt` events and no message until answered. The store used to refresh
/// only for an unknown session's *message* events, so such a session appeared at
/// the next 60 s refresh (75 s observed, 2026-10-16). Any session-scoped event
/// now counts. The limits keep a session that stays unknown (a sidecar, a child
/// agent the list hides, a host that lists it late) from driving a refresh
/// storm: a few tries per id, spaced out, and one refresh in flight at a time.
public struct UnknownSessionRefresh: Sendable {
    public static let maxAttempts = 3
    public static let minSpacing: TimeInterval = 5

    private var attempts: [String: Int] = [:]
    private var lastRefreshAt: Date?

    public init() {}

    /// The session an event is about, when the event could reveal a new session.
    public static func sessionId(of event: LiveEvent) -> String? {
        switch event {
        case .message(let sid, _), .busy(let sid, _), .prompt(let sid, _), .queue(let sid, _):
            return sid
        case .reset, .queueAck, .browserFrame, .heartbeat:
            return nil
        }
    }

    /// Whether to refresh now for `sid`. Records the attempt when it says yes.
    public mutating func shouldRefresh(for sid: String, known: Bool, inFlight: Bool, now: Date) -> Bool {
        if known || inFlight || sid.hasPrefix("local-") { return false }
        if let last = lastRefreshAt, now.timeIntervalSince(last) < Self.minSpacing { return false }
        let tried = attempts[sid, default: 0]
        if tried >= Self.maxAttempts { return false }
        attempts[sid] = tried + 1
        lastRefreshAt = now
        return true
    }

    /// A session the list now knows needs no more tries.
    public mutating func forget(_ sid: String) {
        attempts[sid] = nil
    }
}
