import XCTest
@testable import LFGCore

final class FleetActivityDedupeTests: XCTestCase {
    private func card(_ id: String, _ updatedAt: Double) -> FleetActivityDedupe.Card {
        FleetActivityDedupe.Card(id: id, updatedAt: updatedAt)
    }

    func testSingleCardIsKeptAndNothingEnds() {
        let r = FleetActivityDedupe.partition([card("a", 10)])
        XCTAssertEqual(r.keep, "a")
        XCTAssertEqual(r.end, [])
    }

    func testNoCardsKeepsNothing() {
        let r = FleetActivityDedupe.partition([])
        XCTAssertNil(r.keep)
        XCTAssertEqual(r.end, [])
    }

    func testNewestUpdatedAtSurvivesRegardlessOfOrder() {
        let r = FleetActivityDedupe.partition([card("old", 10), card("newest", 30), card("mid", 20)])
        XCTAssertEqual(r.keep, "newest")
        XCTAssertEqual(Set(r.end), ["old", "mid"])
    }

    func testTieBreaksOnLargerIdDeterministically() {
        let forward = FleetActivityDedupe.partition([card("a", 5), card("b", 5)])
        let reversed = FleetActivityDedupe.partition([card("b", 5), card("a", 5)])
        XCTAssertEqual(forward.keep, "b")
        XCTAssertEqual(reversed.keep, "b")
        XCTAssertEqual(forward.end, ["a"])
        XCTAssertEqual(reversed.end, ["a"])
    }

    func testEndListNeverContainsTheSurvivor() {
        let r = FleetActivityDedupe.partition([card("x", 1), card("y", 2), card("z", 3), card("w", 3)])
        XCTAssertEqual(r.keep, "z")
        XCTAssertFalse(r.end.contains("z"))
        XCTAssertEqual(r.end.count, 3)
    }
}
