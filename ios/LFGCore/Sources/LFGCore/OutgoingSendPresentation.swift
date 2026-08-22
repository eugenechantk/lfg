import Foundation

/// Where a just-typed message is shown while the host hasn't recorded it yet.
///
/// There is one invariant behind all of this: **an accent-coloured user bubble
/// means the conversation has the message.** Anything still waiting — on a
/// running turn, on a session that has to be woken up, on a host that isn't
/// answering — waits in the pending strip above the composer instead. Keeping
/// the two surfaces distinct is the whole point; a muted bubble sitting inline
/// with delivered ones reads as "sent" no matter what colour it is.
///
/// This used to be four booleans computed inline at the send site, which is how
/// the closed-session case ended up rendering as a bubble that turned blue on
/// the HTTP response rather than on the transcript.
public enum OutgoingSendPresentation: Equatable, Sendable {
    /// The agent takes it immediately (idle, live session) — a finished-looking
    /// accent bubble, replaced by the real user turn on reconcile.
    case sentBubble
    /// Accepted, but the agent is mid-turn or sitting on a prompt, so it runs
    /// after the current turn. Waits in the strip.
    case queuedBehindTurn
    /// The session is closed: this send has to resume the conversation
    /// server-side first (`claude --resume <id> "<prompt>"`, and Claude
    /// continues into a *new* sessionId). Waits in the strip as a queued
    /// message for the whole of that, and becomes a real bubble only once the
    /// reopened session's transcript carries the turn.
    case queuedForResume
    /// The owning host is unreachable — the message never left the phone. The
    /// durable outbox holds it and the reconnect drain sends it.
    case offlineQueued

    /// - Parameters:
    ///   - hostUnreachable: the routed host is known-down right now.
    ///   - sessionNeedsResume: the target is a closed session, or a
    ///     focused/deep-linked snapshot that is no longer in the live list —
    ///     either way the server has to revive a pane before anything runs.
    ///   - agentBusy: the session is mid-turn.
    ///   - awaitingPrompt: the session is sitting on an interactive prompt.
    ///
    /// Precedence is deliberate. An unreachable host beats everything (nothing
    /// can happen at all). A session that needs resuming beats `agentBusy`,
    /// because a stale `busy` latched from before the pane was reaped says
    /// nothing about the revived one.
    public static func classify(
        hostUnreachable: Bool,
        sessionNeedsResume: Bool,
        agentBusy: Bool,
        awaitingPrompt: Bool
    ) -> OutgoingSendPresentation {
        if hostUnreachable { return .offlineQueued }
        if sessionNeedsResume { return .queuedForResume }
        if agentBusy || awaitingPrompt { return .queuedBehindTurn }
        return .sentBubble
    }

    /// Render inline in the transcript rather than as a strip row.
    public var showsAsBubble: Bool { self == .sentBubble }

    /// Whether the backend is known to have taken the message. Only the
    /// immediate path can claim this at send time; every other case has to wait
    /// for the transcript to say so.
    public var isConfirmed: Bool { self == .sentBubble }
}

/// What a send that threw actually means, and whether it is worth interrupting
/// the user about.
///
/// A throw is not by itself bad news. The common one is a cold tailnet path
/// dropping the first packets of a foreground drain: the message is still in
/// the durable outbox, the next pass sends it, and the queued bubble already
/// says so honestly. Announcing that is worse than saying nothing — it trains
/// the user to ignore a banner that will also carry the failures that DO need
/// them.
///
/// So the split is by outcome, not by "did something throw":
///
/// - **Re-queued** — auto-recovering. The UI already shows "will send when
///   reachable". Silent.
/// - **Failed** — terminal. The message is handed back to the human with a
///   Retry button, and nothing further happens unless they tap it. Worth a
///   banner, because otherwise a message the user believes they sent simply
///   never goes.
public enum SendFailureDisposition: Equatable, Sendable {
    case requeued
    case failed

    /// Only terminal outcomes are announced. This is the whole rule.
    public var announcesToUser: Bool { self == .failed }
}

public enum SendFailurePolicy {

    /// - Parameters:
    ///   - hostStillDown: the owning host is not currently live. A throw against
    ///     a host that is itself unreachable says nothing about the message.
    ///   - hasAttachments: the attachment bytes are still on disk as sidecars,
    ///     so the send is replayable no matter why it threw — and burning the
    ///     row would strand the sidecars.
    public static func disposition(
        hostStillDown: Bool,
        hasAttachments: Bool
    ) -> SendFailureDisposition {
        (hostStillDown || hasAttachments) ? .requeued : .failed
    }

    /// One short sentence for the banner. The pending row carries the host's own
    /// words when it has them; a bare "not sent" leaves the user guessing.
    public static func bannerMessage(reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "Message not sent. Tap Retry on the message to try again."
        }
        return "Message not sent — \(trimmed)"
    }
}
