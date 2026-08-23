import Foundation

/// What to do with a durable outbox row found at launch.
///
/// The durable outbox exists so a send survives being killed mid-flight. The
/// cost is an afterlife: `retryableOutbox()` returns everything not `delivered`,
/// so every launch re-materialises every row that ever failed. Rows past the
/// retry cap were resurrected as red "Not sent" bubbles with **no exit** — never
/// matched against the transcript, never pruned — so sends from the flaky
/// Cloudflare days greeted the user forever, despite their text having been
/// delivered long ago by a later retry.
///
/// Two things were missing, and this models both: a row can be *proven
/// delivered* by the transcript, and a row that cannot be proven delivered still
/// has to stop asking eventually.
public enum OutboxResurrection: Equatable, Sendable {
    /// The transcript already carries this turn — an earlier attempt (possibly
    /// under a different clientId) landed it. Delete the row and its sidecars
    /// and show nothing at all: no bubble, no banner.
    case retire
    /// Recent enough that the drain should simply try again.
    case retry
    /// Terminal, and recent enough to still be actionable: show the bubble with
    /// Retry so the user can decide.
    case surface
    /// Terminal and ancient. Nobody is going to act on it; delete it silently
    /// rather than greet every launch with it.
    case prune
}

public enum OutboxResurrectionPolicy {
    /// Below this age a failed row is still worth an automatic attempt.
    public static let retryWindowMs: Double = 24 * 60 * 60 * 1_000
    /// Above this age a never-delivered row stops surfacing. Seven days: long
    /// enough that a week away from the app still shows what did not send,
    /// short enough that it cannot become permanent furniture.
    public static let afterlifeMs: Double = 7 * 24 * 60 * 60 * 1_000

    /// - Parameters:
    ///   - ageMs: now − the row's **`createdAt`**, in milliseconds. It must NOT
    ///     be derived from `updatedAt`: `LFGStore.markOutbox` rewrites
    ///     `updatedAt` on every state write, so marking a stale row `failed`
    ///     resets its age to zero. That is how a 3-day-old row past the retry
    ///     cap got auto-re-POSTed the moment its host became reachable — the age
    ///     the cap was checking had been destroyed by the act of recording the
    ///     failure. `createdAt` is when the user actually wrote the message and
    ///     nothing rewrites it.
    ///   - deliveredInTranscript: the session transcript contains a matching
    ///     user turn. Deliberately independent of the row's `clientId` and of
    ///     its recorded `state`: the bug is precisely that a row can be `failed`
    ///     on disk while its text was delivered by a *different* attempt.
    public static func decide(
        ageMs: Double,
        deliveredInTranscript: Bool,
        retryWindowMs: Double = retryWindowMs,
        afterlifeMs: Double = afterlifeMs
    ) -> OutboxResurrection {
        // Proof of delivery outranks everything, at any age. A delivered row is
        // finished whether it is ten seconds or ten months old.
        if deliveredInTranscript { return .retire }
        if ageMs <= retryWindowMs { return .retry }
        if ageMs >= afterlifeMs { return .prune }
        return .surface
    }

    /// How deep to search the transcript when reconciling a resurrected row.
    ///
    /// The live reconcile path looks at the last 30 user turns, which is right
    /// for a send made seconds ago. A row being resurrected can be days old and
    /// hundreds of turns back, and that shallow window is one of the reasons
    /// these rows never retired. The reverse scan still stops as soon as it
    /// crosses the row's own timestamp, so this bound is a backstop, not the
    /// normal cost.
    public static let resurrectionSearchLimit = 5_000
}

/// Who asked for this send.
public enum OutboxSendTrigger: Equatable, Sendable {
    /// A human tapped Retry / Send now. They are looking at the message and have
    /// asked for it explicitly, so age does not disqualify it.
    case userInitiated
    /// Anything the client decided on its own — launch replay, reconnect drain,
    /// the recovered-host sweep, and whatever gets added next.
    case automatic
}

/// The single invariant every outbox POST must satisfy.
///
/// This exists because per-call-site gating failed **twice**. Each time, the
/// policy was correct and applied at every path we knew about, and each time a
/// path nobody had enumerated posted the row anyway — most recently
/// `resendFailedSends`, which reaches the network through `retryPending` and so
/// never passed any of the outbox gates at all.
///
/// The lesson is structural, not diligence: a rule enforced at N call sites is
/// only as good as the enumeration of N, and that enumeration has been wrong
/// every time it mattered. Enforced at the POST boundary instead, a new caller
/// is safe by default — the worst it can do is be refused.
public enum OutboxSendGate {

    /// - Returns: whether the row may actually be POSTed.
    ///
    /// Automatic sends require `.retry` — the only decision that means "this is
    /// still live work". `.surface` in particular must NOT send: it is the
    /// terminal-but-recent state whose entire purpose is to sit in the UI with a
    /// Retry button and wait for a human. Auto-sending it is what delivered
    /// three-day-old instructions into live sessions.
    ///
    /// A user-initiated retry is allowed at any age — they can see the message
    /// and asked for it — with one exception: `.retire` means the transcript
    /// already carries this turn, so sending it would duplicate a message that
    /// is demonstrably already there.
    public static func permits(
        _ decision: OutboxResurrection,
        trigger: OutboxSendTrigger
    ) -> Bool {
        switch trigger {
        case .automatic:      return decision == .retry
        case .userInitiated:  return decision != .retire
        }
    }
}
