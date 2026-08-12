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
