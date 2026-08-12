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
