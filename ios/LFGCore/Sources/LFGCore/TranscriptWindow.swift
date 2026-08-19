import Foundation

// MARK: - Transcript render window
//
// A session's transcript is fetched newest-first in bounded pages and merged
// whole (up to 5,000 messages) in SessionStore. Every consumer that reasons
// about the conversation — the Files & Links index, the full-title card,
// optimistic-send reconciliation — depends on having all of it. What must NOT
// be whole is the part handed to SwiftUI.
//
// `LazyVStack` is lazy about *rendering* rows, not about *placing* them: every
// scroll update walks the entire `ForEach` list. Profiled on 2026-08-18 with
// identical gestures on one build (see
// `.claude/feature/ios-session-view-performance.md`):
//
//     150 messages   → 1.1% main-thread busy,   3 samples in placeSubviews
//     3075 messages  → 9.5% main-thread busy, 284 samples in placeSubviews
//
// ~20x the messages, ~95x the placement work — and the client's cap is 5000. So
// the view renders a bounded tail and walks backwards into history on demand,
// while the store keeps the full transcript.

public enum TranscriptWindow {
    /// Rows rendered on open, and the amount added by one extend. Big enough
    /// that reaching the top takes a deliberate scroll rather than happening by
    /// accident on open, small enough that placement cost stays in the flat part
    /// of the curve measured above.
    public static let pageSize = 200

    /// Index of the oldest message to render, for a window of `window` rows over
    /// `total` messages. The window always ends at the newest message — the
    /// session opens at the bottom, and everything that auto-follows (new turns,
    /// optimistic bubbles, the prompt panel) lives at that end.
    public static func startIndex(total: Int, window: Int) -> Int {
        guard total > 0 else { return 0 }
        let size = max(1, window)
        return max(0, total - size)
    }

    /// Whether history exists above the window — drives the "load earlier" row.
    public static func hasOlder(total: Int, window: Int) -> Bool {
        startIndex(total: total, window: window) > 0
    }

    /// One page further back, never past the start of the transcript.
    public static func extended(window: Int, total: Int) -> Int {
        min(max(total, 1), max(1, window) + pageSize)
    }

    /// Window size that keeps the OLDEST rendered message in place after
    /// `appended` new messages land at the newest end.
    ///
    /// Without this the window is a fixed count from the end, so a turn arriving
    /// while the user reads history silently drops a row off the top and shifts
    /// what they were reading. Only applied when the user has scrolled up; at the
    /// bottom the window should slide, not grow.
    public static func grown(window: Int, byAppended appended: Int) -> Int {
        max(1, window) + max(0, appended)
    }
}
