import Foundation

/// Two rules for moving a session between hosts, kept out of `SessionTransfer.swift`
/// so they can be read (and changed) on their own.
public extension SessionTransfer {
    /// Whether the move should run **without the source host**: resume on the
    /// target first (forced past the source's lease), re-point the session view,
    /// and close the source copy later — immediately if its host is reachable,
    /// otherwise whenever it comes back (`DeferredSourceCloses`).
    ///
    /// Eugene, 2026-09-20: "the move should be client side instead if the session
    /// is idle anyways … let the client just switch the host in the session view
    /// and clean up the original session and close it after the host is back
    /// online." An idle session has no turn in flight to lose, so there is nothing
    /// the source must do first; making the move wait on the source only meant
    /// that a source which was down but not yet *known* down (inside its grace
    /// window) failed the whole move with a Cloudflare 530.
    ///
    /// A session with a pending prompt is NOT idle: its asking turn is still in
    /// flight and exists only on the source's pane.
    static func movesWithoutSource(sourceKnownDown: Bool, busy: Bool, promptPending: Bool) -> Bool {
        sourceKnownDown || (!busy && !promptPending)
    }

    /// Whether an HTTP failure was answered by the **edge**, not by lfg.
    ///
    /// Every client request goes through a Cloudflare tunnel, so a dead host does
    /// not fail at the transport layer: the edge answers 530 (tunnel down), 502/504
    /// (origin not answering) or 52x with an HTML error page. lfg itself always
    /// answers JSON — including its deliberate JSON 502 for codex resume errors —
    /// so the body is what tells the two apart.
    static func isEdgeOriginDown(status: Int, body: String) -> Bool {
        let edgeStatuses: Set<Int> = [502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 527, 530]
        guard edgeStatuses.contains(status) else { return false }
        let head = body.drop(while: { $0.isWhitespace || $0.isNewline }).prefix(64).lowercased()
        if head.hasPrefix("{") || head.hasPrefix("[") { return false }   // lfg's own JSON
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html") || head.contains("cloudflare")
            || body.isEmpty || head.hasPrefix("error code:")
    }
}
