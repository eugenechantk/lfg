import XCTest
@testable import LFGCore

final class TranscriptWindowTests: XCTestCase {

    // MARK: startIndex

    func testWindowShorterThanTranscriptRendersTheNewestTail() {
        // The session must open at the newest message, so the window is always
        // anchored to the END of the transcript.
        XCTAssertEqual(TranscriptWindow.startIndex(total: 3075, window: 200), 2875)
    }

    func testWindowLongerThanTranscriptRendersEverything() {
        XCTAssertEqual(TranscriptWindow.startIndex(total: 40, window: 200), 0)
    }

    func testEmptyTranscriptStartsAtZero() {
        XCTAssertEqual(TranscriptWindow.startIndex(total: 0, window: 200), 0)
    }

    func testNonPositiveWindowStillRendersSomething() {
        // A degenerate window must never produce a negative or out-of-range
        // start index — the view slices a real array with it.
        XCTAssertEqual(TranscriptWindow.startIndex(total: 10, window: 0), 9)
        XCTAssertEqual(TranscriptWindow.startIndex(total: 10, window: -5), 9)
    }

    // MARK: hasOlder

    func testHasOlderIsTrueOnlyWhenHistorySitsAboveTheWindow() {
        XCTAssertTrue(TranscriptWindow.hasOlder(total: 3075, window: 200))
        XCTAssertFalse(TranscriptWindow.hasOlder(total: 200, window: 200))
        XCTAssertFalse(TranscriptWindow.hasOlder(total: 12, window: 200))
        XCTAssertFalse(TranscriptWindow.hasOlder(total: 0, window: 200))
    }

    // MARK: extended

    func testExtendAddsOnePage() {
        XCTAssertEqual(TranscriptWindow.extended(window: 200, total: 3075), 400)
    }

    func testExtendStopsAtTheStartOfTheTranscript() {
        // Extending past the transcript would leave `hasOlder` true forever and
        // the loader row would keep re-firing at the top.
        XCTAssertEqual(TranscriptWindow.extended(window: 200, total: 260), 260)
        XCTAssertFalse(TranscriptWindow.hasOlder(
            total: 260, window: TranscriptWindow.extended(window: 200, total: 260)))
    }

    func testRepeatedExtendsWalkAllTheWayBackAndThenStop() {
        var window = TranscriptWindow.pageSize
        let total = 1050
        var extends = 0
        while TranscriptWindow.hasOlder(total: total, window: window) {
            window = TranscriptWindow.extended(window: window, total: total)
            extends += 1
            XCTAssertLessThan(extends, 50, "window extension failed to converge")
        }
        XCTAssertEqual(TranscriptWindow.startIndex(total: total, window: window), 0)
    }

    // MARK: grown

    func testGrowKeepsTheOldestRenderedMessageInPlaceWhenTurnsArrive() {
        // Reading history while the agent streams: three new turns land at the
        // bottom, and the row the user is looking at must not shift.
        let total = 3075
        let window = 200
        let before = TranscriptWindow.startIndex(total: total, window: window)
        let grown = TranscriptWindow.grown(window: window, byAppended: 3)
        XCTAssertEqual(TranscriptWindow.startIndex(total: total + 3, window: grown), before)
    }

    func testGrowIgnoresNegativeDeltas() {
        XCTAssertEqual(TranscriptWindow.grown(window: 200, byAppended: -4), 200)
    }

    // MARK: reconciled

    func testOlderHistoryPrependDoesNotGrowTheTailWindow() {
        XCTAssertEqual(
            TranscriptWindow.reconciled(
                window: 200,
                previousIDs: ["m3", "m4"],
                currentIDs: ["m0", "m1", "m2", "m3", "m4"]
            ),
            200
        )
    }

    func testNewLiveMessagesGrowTheWindowByOnlyTheAppendedRows() {
        XCTAssertEqual(
            TranscriptWindow.reconciled(
                window: 200,
                previousIDs: ["m0", "m1", "m2"],
                currentIDs: ["m0", "m1", "m2", "m3", "m4"]
            ),
            202
        )
    }

    func testMixedHistoryAndLiveGrowthIgnoresRowsPrependedAboveTheViewport() {
        XCTAssertEqual(
            TranscriptWindow.reconciled(
                window: 200,
                previousIDs: ["m2", "m3"],
                currentIDs: ["m0", "m1", "m2", "m3", "m4"]
            ),
            201
        )
    }

    func testReplacementWithoutStableIdentityDoesNotGuessAtWindowGrowth() {
        XCTAssertEqual(
            TranscriptWindow.reconciled(
                window: 200,
                previousIDs: ["old-0", "old-1"],
                currentIDs: ["new-0", "new-1", "new-2"]
            ),
            200
        )
    }

    // MARK: followLatest

    func testOpeningFollowsLatestWhileTheBottomAnchorIsTemporarilyAbsent() {
        XCTAssertTrue(TranscriptWindow.shouldFollowLatest(
            isAtBottom: false,
            isOpening: true
        ))
    }

    func testManualScrollUpStopsFollowingAfterOpeningCompletes() {
        XCTAssertFalse(TranscriptWindow.shouldFollowLatest(
            isAtBottom: false,
            isOpening: false
        ))
    }

    func testAtBottomContinuesFollowingAfterOpeningCompletes() {
        XCTAssertTrue(TranscriptWindow.shouldFollowLatest(
            isAtBottom: true,
            isOpening: false
        ))
    }

    func testOpeningSettlesAsSoonAsTheNewestTailCanRender() {
        XCTAssertTrue(TranscriptWindow.shouldSettleInitialPin(
            isOpening: true,
            hasRenderedTail: true
        ))
    }

    func testOpeningKeepsWaitingWhileTheTranscriptIsEmpty() {
        XCTAssertFalse(TranscriptWindow.shouldSettleInitialPin(
            isOpening: true,
            hasRenderedTail: false
        ))
    }

    func testCompletedOpeningCannotScheduleAnotherInitialPin() {
        XCTAssertFalse(TranscriptWindow.shouldSettleInitialPin(
            isOpening: false,
            hasRenderedTail: true
        ))
    }
}

// MARK: - Keyboard viewport policy
//
// Regression cover for the two defects measured against the real keyboard on
// TestFlight 1.3.0 — see `.codex/feature/transcript-keyboard-scroll-stability.md`
// and the frame measurements in `.claude/evidence/20260822-keyboard-scroll`.

final class KeyboardViewportPolicyTests: XCTestCase {

    /// The at-bottom defect: the keyboard rose 301pt and the transcript did not
    /// move, hiding the newest message behind the composer.
    func testBottomPinnedReaderIsRepinnedWhenTheKeyboardResizesTheViewport() {
        XCTAssertTrue(KeyboardViewportPolicy.shouldRepinToLatest(
            isAtBottom: true,
            isOpening: false
        ))
    }

    /// The scrolled-up defect, and the thing the fix must NOT overcorrect into:
    /// a reader in history is never moved by the keyboard, in either direction.
    func testReaderInHistoryIsNeverMovedByTheKeyboard() {
        XCTAssertFalse(KeyboardViewportPolicy.shouldRepinToLatest(
            isAtBottom: false,
            isOpening: false
        ))
    }

    func testOpeningStillOutranksBottomAnchorVisibility() {
        XCTAssertTrue(KeyboardViewportPolicy.shouldRepinToLatest(
            isAtBottom: false,
            isOpening: true
        ))
    }

    /// The anchor may only be enforced during a page reveal. Enforcing it the
    /// rest of the time is what threw the reader 407pt off the top of the screen
    /// when the keyboard appeared.
    func testHistoryAnchorIsEnforcedOnlyWhileRevealingAPage() {
        XCTAssertTrue(KeyboardViewportPolicy.enforcesHistoryAnchor(isRevealingPage: true))
        XCTAssertFalse(KeyboardViewportPolicy.enforcesHistoryAnchor(isRevealingPage: false))
    }

    func testRepinSpansTheReportedKeyboardAnimation() {
        // 0.25s + 0.08s settle at 16ms per frame.
        XCTAssertEqual(KeyboardViewportPolicy.repinFrameCount(animationDuration: 0.25), 20)
        XCTAssertEqual(KeyboardViewportPolicy.repinFrameCount(animationDuration: 0.5), 36)
    }

    /// A missing or nonsensical duration must still pin at least once —
    /// returning 0 would make the whole fix a no-op without failing anything.
    func testRepinAlwaysRunsAtLeastOnce() {
        XCTAssertGreaterThanOrEqual(
            KeyboardViewportPolicy.repinFrameCount(animationDuration: nil), 1)
        XCTAssertGreaterThanOrEqual(
            KeyboardViewportPolicy.repinFrameCount(animationDuration: 0), 1)
        XCTAssertGreaterThanOrEqual(
            KeyboardViewportPolicy.repinFrameCount(animationDuration: -1), 1)
        XCTAssertGreaterThanOrEqual(
            KeyboardViewportPolicy.repinFrameCount(animationDuration: .nan), 1)
    }
}

// MARK: - Bottom proximity from real scroll geometry
//
// Regression cover for the third defect measured on 2026-08-22: a spurious
// `BOTTOM.onAppear` in a LazyVStack latched "at bottom" while the reader was
// scrolled up, after which every arriving message dragged the transcript −146pt.

final class ScrolledToEndTests: XCTestCase {

    private let container = 700.0

    func testExactlyAtTheEndCounts() {
        XCTAssertTrue(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container, offsetY: 4300))
    }

    func testWithinTheThresholdStillCounts() {
        // 30pt of rubber-banding must not drop auto-follow.
        XCTAssertTrue(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container, offsetY: 4270))
    }

    /// The case the anchor got wrong: reader parked far up the transcript.
    func testReaderScrolledUpIsNotAtTheEnd() {
        XCTAssertFalse(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container, offsetY: 1200))
    }

    /// One page-worth off the end is emphatically not "at bottom" — this is the
    /// state in which the old code kept calling scrollTo("BOTTOM").
    func testJustOverTheThresholdIsNotAtTheEnd() {
        XCTAssertFalse(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container, offsetY: 4200))
    }

    /// A transcript shorter than the viewport has no "away from the bottom".
    func testContentShorterThanTheViewportIsAlwaysAtTheEnd() {
        XCTAssertTrue(TranscriptWindow.isScrolledToEnd(
            contentHeight: 200, containerHeight: container, offsetY: 0))
    }

    /// The composer's safe-area inset is part of the scrollable extent; ignoring
    /// it would read a genuinely bottom-pinned transcript as scrolled up.
    func testBottomInsetIsPartOfTheScrollableExtent() {
        XCTAssertTrue(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container,
            offsetY: 4400, bottomInset: 100))
        XCTAssertFalse(TranscriptWindow.isScrolledToEnd(
            contentHeight: 5000, containerHeight: container,
            offsetY: 4000, bottomInset: 100))
    }
}

/// Cover for the open-at-newest pin waiting for confirmation instead of guessing.
final class OpenPinBudgetTests: XCTestCase {

    /// Long enough for a cold open on a long transcript to settle, but bounded —
    /// the reader must get control back even if arrival is never confirmed.
    func testGeometryBackedBudgetSpansACodeOpen() {
        XCTAssertEqual(TranscriptWindow.openPinFrameBudget(canVerifyGeometry: true), 90)
    }

    /// Without geometry there is nothing to wait for; stay close to the original
    /// two-pin behaviour rather than blocking the reader.
    func testWithoutGeometryTheBudgetStaysShort() {
        XCTAssertEqual(TranscriptWindow.openPinFrameBudget(canVerifyGeometry: false), 8)
    }

    /// The loop must always run at least once, whatever the frame interval.
    func testBudgetIsNeverZero() {
        for interval in [0.016, 1.0, 100.0, 0.0] {
            XCTAssertGreaterThanOrEqual(
                TranscriptWindow.openPinFrameBudget(canVerifyGeometry: true, frameInterval: interval), 1)
            XCTAssertGreaterThanOrEqual(
                TranscriptWindow.openPinFrameBudget(canVerifyGeometry: false, frameInterval: interval), 1)
        }
    }
}

/// Cover for the open-arrival check being stricter than the follow check.
///
/// Regression: the opening pin accepted a trivially-at-end reading on a
/// 2-message transcript and released before the real ~600 rows arrived.
final class OpenArrivalConfirmationTests: XCTestCase {

    private let container = 700.0

    /// The exact failure. Two short rows: `isScrolledToEnd` says yes (correct
    /// for follow), `confirmsOpenArrival` must say no.
    func testShortTranscriptCannotConfirmAnOpen() {
        XCTAssertTrue(TranscriptWindow.isScrolledToEnd(
            contentHeight: 120, containerHeight: container, offsetY: 0))
        XCTAssertFalse(TranscriptWindow.confirmsOpenArrival(
            contentHeight: 120, containerHeight: container, offsetY: 0))
    }

    /// Content exactly filling the viewport is still not "something to be at the
    /// end of" — it is the boundary the short case lives on.
    func testContentEqualToTheViewportCannotConfirm() {
        XCTAssertFalse(TranscriptWindow.confirmsOpenArrival(
            contentHeight: container, containerHeight: container, offsetY: 0))
    }

    func testRealTranscriptAtItsEndConfirms() {
        XCTAssertTrue(TranscriptWindow.confirmsOpenArrival(
            contentHeight: 5000, containerHeight: container, offsetY: 4300))
    }

    func testRealTranscriptNotAtItsEndDoesNotConfirm() {
        XCTAssertFalse(TranscriptWindow.confirmsOpenArrival(
            contentHeight: 5000, containerHeight: container, offsetY: 1200))
    }

    /// The composer inset is part of the scrollable extent here too.
    func testBottomInsetCountsTowardBothChecks() {
        XCTAssertTrue(TranscriptWindow.confirmsOpenArrival(
            contentHeight: 5000, containerHeight: container,
            offsetY: 4400, bottomInset: 100))
    }
}

/// Cover for re-anchoring when history ARRIVING (not the user revealing it)
/// changes which rows are rendered above the reader.
final class AnchorAfterMutationTests: XCTestCase {

    private func ids(_ r: ClosedRange<Int>) -> [String] { r.map { "m\($0)" } }

    /// The measured case: the window is not yet full, a history page lands, and
    /// `startIndex` jumps — laying older rows above whatever is on screen.
    func testWindowStartMovingReturnsThePreviousTopRow() {
        let previous = ids(0...62)          // 63 rows, window 200 -> start 0
        let current = ids(0...481)          // 482 rows, window 200 -> start 282
        // The prepended ids sort before, so the old rows keep their identity.
        let shifted = ids(1000...1418) + previous
        XCTAssertEqual(
            TranscriptWindow.anchorAfterMutation(
                previousIDs: previous, currentIDs: shifted,
                previousWindow: 200, currentWindow: 200),
            "m0")
        XCTAssertEqual(current.count, 482)  // documents the shape above
    }

    /// Steady state: window already full, an older page prepends, the rendered
    /// slice is unchanged — must NOT re-anchor.
    func testUnchangedRenderedTopDoesNotAnchor() {
        let previous = ids(0...399)
        let current = ids(500...599) + previous     // 100 older rows prepended
        // previous: start = 400-200 = 200 -> "m200"
        // current:  start = 500-200 = 300 -> current[300] is also "m200"
        XCTAssertNil(TranscriptWindow.anchorAfterMutation(
            previousIDs: previous, currentIDs: current,
            previousWindow: 200, currentWindow: 200))
    }

    /// Appends with a grown window keep the same top row — no anchor needed.
    func testAppendWithGrownWindowDoesNotAnchor() {
        let previous = ids(0...399)
        let current = previous + ids(400...404)
        XCTAssertNil(TranscriptWindow.anchorAfterMutation(
            previousIDs: previous, currentIDs: current,
            previousWindow: 200, currentWindow: 205))
    }

    /// A wholesale identity replacement has no surviving row to anchor to.
    func testVanishedTopRowYieldsNoAnchor() {
        XCTAssertNil(TranscriptWindow.anchorAfterMutation(
            previousIDs: ids(0...399), currentIDs: ids(900...1399),
            previousWindow: 200, currentWindow: 200))
    }

    func testEmptyInputsAreSafe() {
        XCTAssertNil(TranscriptWindow.anchorAfterMutation(
            previousIDs: [String](), currentIDs: ids(0...9),
            previousWindow: 200, currentWindow: 200))
        XCTAssertNil(TranscriptWindow.anchorAfterMutation(
            previousIDs: ids(0...9), currentIDs: [String](),
            previousWindow: 200, currentWindow: 200))
    }
}
