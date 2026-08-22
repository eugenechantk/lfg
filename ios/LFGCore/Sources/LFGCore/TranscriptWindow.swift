import Foundation

/// The honest state of the row above the oldest currently rendered transcript
/// message. Network paging and revealing rows already buffered in memory are
/// different operations: only the former should imply that the transcript is
/// still incomplete.
public enum TranscriptHistoryTopRow: Equatable, Sendable {
    case hidden
    case loadingNetwork
    case revealingBuffered

    public static func resolve(
        isNetworkLoading: Bool,
        hasBufferedEarlierMessages: Bool
    ) -> Self {
        if isNetworkLoading { return .loadingNetwork }
        if hasBufferedEarlierMessages { return .revealingBuffered }
        return .hidden
    }
}

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

    /// Reconcile a reading window after the transcript changes, growing only
    /// for rows that landed *after* the previously known conversation tail.
    ///
    /// History pages are merged into the same array as live turns, so a raw
    /// count delta cannot say where the new rows landed. Treating a 500-row
    /// history prepend as 500 appended live turns expands the rendered window
    /// by 500 and lays all of those rows above the reader. Stable identity lets
    /// us find the last retained old row and count only rows after it.
    public static func reconciled<ID: Hashable>(
        window: Int,
        previousIDs: [ID],
        currentIDs: [ID]
    ) -> Int {
        guard !previousIDs.isEmpty, currentIDs.count > previousIDs.count else {
            return max(1, window)
        }

        let previous = Set(previousIDs)
        guard let lastRetainedIndex = currentIDs.lastIndex(where: previous.contains) else {
            // A wholesale identity replacement gives us no safe positional
            // inference. Keeping the current tail is stable; guessing growth is
            // exactly the behavior that causes viewport jumps.
            return max(1, window)
        }

        let appended = currentIDs.distance(
            from: currentIDs.index(after: lastRetainedIndex),
            to: currentIDs.endIndex
        )
        return grown(window: window, byAppended: appended)
    }

    /// Whether transcript mutations should keep the newest content visible.
    /// Opening is an explicit request to see the latest state, so it temporarily
    /// outranks bottom-anchor visibility while async history changes the layout.
    /// Once opening completes, only an actually bottom-pinned reader follows.
    public static func shouldFollowLatest(
        isAtBottom: Bool,
        isOpening: Bool
    ) -> Bool {
        isOpening || isAtBottom
    }

    /// The opening pin exists only to establish the newest visible tail. Older
    /// pages may continue loading above it after control returns to the reader.
    public static func shouldSettleInitialPin(
        isOpening: Bool,
        hasRenderedTail: Bool
    ) -> Bool {
        isOpening && hasRenderedTail
    }
    /// The row that must stay put when a transcript mutation changes which rows
    /// are rendered, or `nil` when the rendered set's top is unaffected.
    ///
    /// The render window is a count taken from the newest end, so `startIndex`
    /// moves whenever the total changes. Early in a load that genuinely reveals
    /// OLDER rows above the reader — measured on a real session, `startIndex`
    /// walked 0 → 282 → 640 → 1035 → 1221 as history pages landed, each step
    /// laying more rows above whatever was on screen and shoving it down.
    /// `reconciled` keeps the *count* honest but says nothing about the fact
    /// that the top of the rendered slice moved.
    ///
    /// Returns the id that was first-rendered before the mutation, so the caller
    /// can re-anchor to it in the same transaction — the discipline
    /// `extendWindow` already uses for a user-driven reveal, applied to the
    /// arrival-driven one.
    public static func anchorAfterMutation<ID: Hashable>(
        previousIDs: [ID],
        currentIDs: [ID],
        previousWindow: Int,
        currentWindow: Int
    ) -> ID? {
        let oldStart = startIndex(total: previousIDs.count, window: previousWindow)
        let newStart = startIndex(total: currentIDs.count, window: currentWindow)
        guard oldStart < previousIDs.count, newStart < currentIDs.count else { return nil }
        let oldFirst = previousIDs[oldStart]
        // Unchanged top: nothing moved above the reader, so do not touch the
        // scroll position (re-anchoring needlessly is its own source of jitter).
        guard currentIDs[newStart] != oldFirst else { return nil }
        // Only anchor to a row that still exists, otherwise the scroll target is
        // meaningless and SwiftUI would pick something arbitrary.
        return currentIDs.contains(oldFirst) ? oldFirst : nil
    }

    /// Whether the opening pin may believe it has arrived at the newest message.
    ///
    /// Stricter than `isScrolledToEnd` on purpose. `isScrolledToEnd` answers
    /// "trivially yes" when the content is shorter than the viewport, which is
    /// correct for auto-follow but catastrophic for an *open*: the pin fires as
    /// soon as the transcript is non-empty, and on a cold open that is the two
    /// messages the live stream happened to deliver first. Measured: the pin
    /// released at `msgs=2`, the remaining ~600 rows arrived afterwards, and the
    /// reader was left parked mid-transcript with auto-follow already off.
    ///
    /// So an open is only confirmed once there is genuinely something to be at
    /// the end OF.
    public static func confirmsOpenArrival(
        contentHeight: Double,
        containerHeight: Double,
        offsetY: Double,
        bottomInset: Double = 0,
        threshold: Double = 40
    ) -> Bool {
        guard contentHeight + bottomInset > containerHeight else { return false }
        return isScrolledToEnd(
            contentHeight: contentHeight,
            containerHeight: containerHeight,
            offsetY: offsetY,
            bottomInset: bottomInset,
            threshold: threshold
        )
    }

    /// How many frames the open-at-newest pin may keep re-asserting itself while
    /// it waits for the scroll view to actually arrive at the end.
    ///
    /// The pin used to fire `scrollTo` twice and then release, without ever
    /// checking that it worked. A `LazyVStack` still measuring its rows — the
    /// cold-open case, and more so once hydration delivers hundreds of rows at
    /// once — lands `scrollTo` approximately, so the open could finish parked
    /// mid-transcript. Measured on a long live session: the newest rows sat
    /// ~800 pt below the fold and stayed there.
    ///
    /// - Parameter canVerifyGeometry: whether the caller can observe real scroll
    ///   geometry (iOS 18+). Without it there is nothing to wait *for*, so the
    ///   budget stays close to the original two-pin behaviour rather than
    ///   blocking the reader from taking control of a view that may already be
    ///   where it belongs.
    public static func openPinFrameBudget(
        canVerifyGeometry: Bool,
        frameInterval: Double = 0.016
    ) -> Int {
        let seconds = canVerifyGeometry ? 1.44 : 0.128
        return max(1, Int((seconds / max(0.001, frameInterval)).rounded()))
    }

    /// Whether the transcript is scrolled to (or within a hair of) its newest
    /// end, from real scroll geometry.
    ///
    /// `isAtBottom` was previously inferred only from a 1 pt `BOTTOM` anchor's
    /// `onAppear` / `onDisappear`. In a `LazyVStack` those fire when SwiftUI
    /// *creates* a row, not when it is on screen, so a large transcript mutation
    /// can re-create the anchor while the reader is hundreds of points up and
    /// latch "at bottom" on. Every subsequent arriving message then scrolls
    /// toward the newest end, walking the transcript out from under the reader —
    /// measured at −146 pt per arrival, which is what makes a session being
    /// typed into "disappear above the viewable area". Geometry cannot lie about
    /// this the way row lifecycle can.
    ///
    /// `threshold` is generous on purpose: auto-follow should survive a few
    /// points of rubber-banding, and the cost of a false negative (a live
    /// message does not scroll into view) is far lower than a false positive
    /// (the reader is dragged away from what they were reading).
    public static func isScrolledToEnd(
        contentHeight: Double,
        containerHeight: Double,
        offsetY: Double,
        bottomInset: Double = 0,
        threshold: Double = 40
    ) -> Bool {
        // Content shorter than the viewport is trivially "at the end".
        guard contentHeight + bottomInset > containerHeight else { return true }
        let distanceFromEnd = (contentHeight + bottomInset) - (offsetY + containerHeight)
        return distanceFromEnd <= threshold
    }
}

// MARK: - Keyboard viewport policy
//
// The composer hangs off `safeAreaInset(edge: .bottom)`, so showing or hiding
// the keyboard resizes the transcript's viewport by ~300pt mid-session. Two
// separate decisions ride on that, and shipping 1.3.0 got both wrong — measured
// on an iPhone 17 Pro against the real keyboard
// (`.claude/evidence/20260822-keyboard-scroll`):
//
//   - scrolled up reading history: the reader's rows jumped 407pt off the top
//     of the screen, because an identity-backed scroll position was still
//     enforcing its anchor and re-derived the offset against the new layout.
//   - pinned at the newest message: the content did not move at all, so the
//     composer and keyboard rose over the very message being replied to.

public enum KeyboardViewportPolicy {
    /// Whether a keyboard geometry change should re-pin the transcript to its
    /// newest message.
    ///
    /// Only for a reader who is already at the newest end. A reader scrolled up
    /// into history has chosen where to look, and moving them is the bug — for
    /// them the correct response to the keyboard is to do nothing at all.
    public static func shouldRepinToLatest(isAtBottom: Bool, isOpening: Bool) -> Bool {
        TranscriptWindow.shouldFollowLatest(isAtBottom: isAtBottom, isOpening: isOpening)
    }

    /// Whether `.scrollPosition(id:)` may enforce its anchor right now.
    ///
    /// `.scrollPosition(id:)` is a continuous contract, not a one-shot scroll:
    /// while it is bound to a non-nil id SwiftUI keeps re-deriving the content
    /// offset to hold that row at the anchor, across *every* layout change —
    /// including ones with nothing to do with history, like the keyboard. The
    /// history reveal needs it for exactly the transaction that inserts a page,
    /// so it is reported for exactly that long.
    public static func enforcesHistoryAnchor(isRevealingPage: Bool) -> Bool {
        isRevealingPage
    }

    /// Frames to keep re-pinning for while the keyboard animates.
    ///
    /// A single scroll issued from `keyboardWillChangeFrame` targets the
    /// *pre-keyboard* layout — the notification is delivered before the safe
    /// area inset lands — so the pin has to be re-asserted across the
    /// transition. Never returns 0: a missing or nonsensical duration in the
    /// notification must still produce one pin, or the fix silently does
    /// nothing.
    public static func repinFrameCount(
        animationDuration: Double?,
        settle: Double = 0.08,
        frameInterval: Double = 0.016
    ) -> Int {
        let duration = animationDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0.25
        return max(1, Int((duration + settle) / frameInterval))
    }
}
