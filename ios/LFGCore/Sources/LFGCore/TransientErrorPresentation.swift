/// Who may see a transient store error.
///
/// Session and pending-send audiences keep an error raised while no detail is
/// visible from leaking into whichever session the user happens to open next.
public enum TransientErrorAudience: Equatable, Sendable {
    case global
    case session(String)
    case pendingSend(sessionID: String, clientID: String)
}

/// Relevance policy for the short error banner shown over a session detail.
///
/// The event slot can outlive the view that presents it. Presentation therefore
/// has to prove three things at read time: the event is still fresh, it belongs
/// to this session, and (for send failures) the failed row it describes still
/// exists. Otherwise a reconciled send can leave behind a false “not sent”.
public enum TransientErrorPresentation {
    public static func shouldPresent(
        audience: TransientErrorAudience,
        viewingSessionID: String,
        failedPendingClientIDs: Set<String>,
        ageMs: Double,
        lifetimeMs: Double
    ) -> Bool {
        guard ageMs >= 0, ageMs < lifetimeMs else { return false }

        switch audience {
        case .global:
            return true
        case .session(let sessionID):
            return sessionID == viewingSessionID
        case .pendingSend(let sessionID, let clientID):
            return sessionID == viewingSessionID
                && failedPendingClientIDs.contains(clientID)
        }
    }
}
