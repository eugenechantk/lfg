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
}
