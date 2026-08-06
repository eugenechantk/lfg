import Foundation

/// Which of two disagreeing sources of a session's `busy` should win: the live
/// journal event stream, or the REST `/api/sessions` snapshot.
///
/// THE PROBLEM THIS SOLVES. The two sources have opposite failure modes and
/// neither is simply better.
///
/// The journal is *event*-shaped and change-only: `src/journal-pump.ts` appends a
/// `busy` event only when the value differs from the last one it appended. That
/// makes it the fresher source the instant a session transitions — but it also
/// means **silence is ambiguous**. A quiet stream reads identically whether
/// nothing changed or the producer stopped.
///
/// The snapshot is *level*-shaped: every `/api/sessions` response recomputes
/// `busy` from scratch. It cannot go stale, but it arrives only as often as the
/// client polls, so between polls a journal event is genuinely newer.
///
/// Preferring the journal unconditionally was the first design, and silence
/// killed it. On 2026-08-06 the server's poll loop stopped; two codex sessions
/// that happened to be mid-turn at that instant had `busy: true` as the journal's
/// last word, and the client rendered them "Running" for hours — while every
/// snapshot in between correctly said `busy: false`. The correct answer was in
/// hand on every refresh and a permanent veto discarded it.
///
/// Preferring the snapshot unconditionally fails the other way: a session already
/// running when the client connected emits no event (no change), so the client
/// would clobber a correct live value with a poll-old one and flicker.
///
/// So: the journal wins **while its last word is recent enough to still be the
/// fresher one**, and the snapshot wins after that. Time is the only thing that
/// distinguishes "quiet because nothing changed" from "quiet because nobody is
/// talking", so time is what the rule is written in.
public enum JournalFreshness {
    /// How long a journal value keeps out-voting the snapshot.
    ///
    /// The pump sweeps every second, so a live pump re-states any *change* orders
    /// of magnitude inside this window. 60s is far enough out that ordinary
    /// refresh jitter can never let a stale snapshot clobber a fresh event, and
    /// near enough that a dead pump self-corrects within one look at the screen.
    public static let defaultTTL: TimeInterval = 60

    /// True when the REST snapshot's `busy` should be applied.
    ///
    /// - `statedAt`: when the journal last emitted a `busy` event for this
    ///   session, or `nil` if it never has (a session already in whatever state
    ///   it is in since before this client connected — the snapshot is then the
    ///   *only* source and must always be taken).
    public static func snapshotWins(
        journalStatedAt statedAt: Date?,
        now: Date,
        ttl: TimeInterval = defaultTTL
    ) -> Bool {
        guard let statedAt else { return true }
        // A `statedAt` in the future means the device clock moved backwards
        // (NTP correction, timezone-independent but real). Treat it as fresh
        // rather than as an enormous age, so a clock skip can't flap the list.
        let age = now.timeIntervalSince(statedAt)
        if age < 0 { return false }
        return age >= ttl
    }
}
