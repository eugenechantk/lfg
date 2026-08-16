import Foundation

/// What to do with an optimistic send when the host's outbound queue acks it.
///
/// The rule the queue-poll path (`correlatePending`) has always followed is:
/// *a bubble is only removed once the matching user turn is present in THIS
/// client's transcript.* The server marks an item `delivered` when it has
/// reached the server-side transcript, and the local live stream / history
/// fetch can lag behind that — so dropping the optimistic row on the ack alone
/// leaves a hole in the conversation until history catches up.
///
/// The resume path makes that gap structural rather than occasional: a send to
/// a closed session is recorded as `delivered` and acked the instant the host
/// accepts the resume request, several seconds before the revived agent has
/// written anything. Applying the same rule here is what keeps the message
/// visible — as a queued row — for that whole window.
public enum QueueAckResolution: Equatable, Sendable {
    /// The turn is in the local transcript; drop the optimistic row and let the
    /// real bubble take over.
    case remove
    /// Acked as delivered, but this client hasn't seen the turn yet. Keep the
    /// row exactly as it is and fetch history; reconcile removes it when the
    /// turn lands.
    case awaitTranscript
    /// The host reported a delivery failure.
    case markFailed
    /// Not an ack we act on.
    case ignore

    public static func resolve(
        ackKind: String,
        transcriptHasMatchingUserTurn: Bool
    ) -> QueueAckResolution {
        switch ackKind {
        case "delivered":
            return transcriptHasMatchingUserTurn ? .remove : .awaitTranscript
        case "failed":
            return .markFailed
        default:
            return .ignore
        }
    }
}

/// What the host said when asked to remove a queued message.
public enum QueuedMessageRemovalOutcome: Equatable, Sendable {
    /// The row never reached a host, so there is nothing to ask about.
    case noServerRow
    /// The host removed it.
    case removed
    /// 404 — the host has no message with that id (already pruned, or the
    /// queue was cleared). Nothing under that id can run.
    case unknownToServer
    /// 409 — the message is mid-keystroke or already committed to the agent's
    /// own next-turn queue, so it is still going to execute.
    case rejected
    /// The request itself failed (offline, timeout). Server state is unknown.
    case requestFailed
}

/// Whether a queued-message action may remove its optimistic row locally.
///
/// A row with no server queue id is still local (for example, offline) and can
/// be removed. Once the server has an id, local state may disappear only when
/// the host confirms the message will not execute — either because it removed
/// it, or because it has never heard of it. Native agent queues cannot retract
/// a committed message, so a 409 must leave the row visible instead of
/// pretending the message was cancelled; so must a failed request, which tells
/// us nothing about what the host will do.
public enum QueuedMessageRemovalResolution: Equatable, Sendable {
    case removeLocally
    case keepPending

    public static func resolve(
        outcome: QueuedMessageRemovalOutcome
    ) -> QueuedMessageRemovalResolution {
        switch outcome {
        case .noServerRow, .removed, .unknownToServer: return .removeLocally
        case .rejected, .requestFailed: return .keepPending
        }
    }
}
