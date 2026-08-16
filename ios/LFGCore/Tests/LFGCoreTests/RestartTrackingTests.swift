import XCTest
@testable import LFGCore

final class RestartTrackingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testMarkedSessionIsRestarting() {
        var r = RestartTracking()
        r.mark("a", at: t0)
        XCTAssertTrue(r.isRestarting("a", now: t0.addingTimeInterval(3)))
        XCTAssertFalse(r.isRestarting("b", now: t0.addingTimeInterval(3)))
    }

    func testEmptyIdIsNeverMarked() {
        var r = RestartTracking()
        r.mark("", at: t0)
        XCTAssertTrue(r.markedIds.isEmpty)
    }

    /// A host returning a live row for the id is the confirmation that ends the
    /// restart — not a busy flag. An empty resume (no kickoff message) comes back
    /// live and *idle*, so waiting for busy would spin until the timeout.
    func testLiveIdClearsTheMark() {
        var r = RestartTracking()
        r.mark("a", at: t0)
        r.confirmLive(["a", "unrelated"])
        XCTAssertFalse(r.isRestarting("a", now: t0.addingTimeInterval(1)))
    }

    /// Claude resumes into a NEW sessionId, so the mark has to follow the row
    /// when `SessionStore.remap` renames it — otherwise the card that is actually
    /// restarting reverts to "Closed"/"Idle" mid-revival.
    func testMoveCarriesTheMarkAcrossAnIdChange() {
        var r = RestartTracking()
        r.mark("old", at: t0)
        r.move(from: "old", to: "new")
        XCTAssertFalse(r.isRestarting("old", now: t0.addingTimeInterval(1)))
        XCTAssertTrue(r.isRestarting("new", now: t0.addingTimeInterval(1)))
    }

    func testMoveKeepsTheOriginalStartTime() {
        var r = RestartTracking()
        r.mark("old", at: t0)
        r.move(from: "old", to: "new")
        // 44s after the ORIGINAL mark, not after the move.
        XCTAssertTrue(r.isRestarting("new", now: t0.addingTimeInterval(44)))
        XCTAssertFalse(r.isRestarting("new", now: t0.addingTimeInterval(46)))
    }

    func testMoveIsANoOpWhenNothingIsMarked() {
        var r = RestartTracking()
        r.move(from: "old", to: "new")
        XCTAssertTrue(r.markedIds.isEmpty)
    }

    /// A resume that never produces a live row must fall back to the truth rather
    /// than leaving the card claiming "Restarting" forever.
    func testMarkExpiresAfterTheTimeout() {
        var r = RestartTracking()
        r.mark("a", at: t0)
        XCTAssertTrue(r.isRestarting("a", now: t0.addingTimeInterval(44)))
        XCTAssertFalse(r.isRestarting("a", now: t0.addingTimeInterval(46)))
    }

    func testPruneDropsOnlyExpiredMarks() {
        var r = RestartTracking()
        r.mark("stale", at: t0)
        r.mark("fresh", at: t0.addingTimeInterval(40))
        r.prune(now: t0.addingTimeInterval(50))
        XCTAssertEqual(r.markedIds, ["fresh"])
    }

    /// A retry restarts the window — the second ask deserves its own 45s.
    func testRemarkingResetsTheClock() {
        var r = RestartTracking()
        r.mark("a", at: t0)
        r.mark("a", at: t0.addingTimeInterval(40))
        XCTAssertTrue(r.isRestarting("a", now: t0.addingTimeInterval(80)))
    }
}
