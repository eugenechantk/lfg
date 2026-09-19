import XCTest
@testable import LFGCore

final class FleetEndGateTests: XCTestCase {
    func testDefaultHoldIsZeroSoATrustworthyZeroEndsAtOnce() {
        XCTAssertEqual(FleetEndGate.hold, 0)
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(), now: 1_000)
        XCTAssertEqual(r.verdict, .end)
    }

    func testDefaultStillNeverEndsAnUntrustworthyZero() {
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: false, state: .init(), now: 1_000)
        XCTAssertEqual(r.verdict, .untouched)
    }

    func testUntrustworthyCountIsUntouchedAndResetsTheClock() {
        // Background launch: card exists, store empty, no live fetch yet.
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: false, state: .init(zeroSince: 100), now: 500, hold: 60)
        XCTAssertEqual(r.verdict, .untouched)
        XCTAssertNil(r.state.zeroSince)
    }

    func testUntrustworthyWithActivityIsStillUntouched() {
        let r = FleetEndGate.step(activeTotal: 3, countTrustworthy: false, state: .init(), now: 500, hold: 60)
        XCTAssertEqual(r.verdict, .untouched)
    }

    func testActiveResetsTheClockAndKeeps() {
        let r = FleetEndGate.step(activeTotal: 2, countTrustworthy: true, state: .init(zeroSince: 100), now: 500, hold: 60)
        XCTAssertEqual(r.verdict, .keep)
        XCTAssertNil(r.state.zeroSince)
    }

    func testFirstTrustworthyZeroStartsTheHoldWithoutEnding() {
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(), now: 1_000, hold: 60)
        XCTAssertEqual(r.verdict, .keep)
        XCTAssertEqual(r.state.zeroSince, 1_000)
    }

    func testZeroInsideTheHoldKeeps() {
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(zeroSince: 1_000), now: 1_059, hold: 60)
        XCTAssertEqual(r.verdict, .keep)
        XCTAssertEqual(r.state.zeroSince, 1_000)
    }

    func testZeroPastTheHoldEnds() {
        let r = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(zeroSince: 1_000), now: 1_060, hold: 60)
        XCTAssertEqual(r.verdict, .end)
    }

    func testActivityInsideTheHoldCancelsIt() {
        let held = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(), now: 1_000, hold: 60).state
        let back = FleetEndGate.step(activeTotal: 1, countTrustworthy: true, state: held, now: 1_030, hold: 60)
        XCTAssertEqual(back.verdict, .keep)
        XCTAssertNil(back.state.zeroSince)
        let zeroAgain = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: back.state, now: 1_070, hold: 60)
        XCTAssertEqual(zeroAgain.verdict, .keep) // clock restarted at 1_070
        XCTAssertEqual(zeroAgain.state.zeroSince, 1_070)
    }

    func testHostGoingDownMidHoldResetsTheClock() {
        let held = FleetEndGate.step(activeTotal: 0, countTrustworthy: true, state: .init(), now: 1_000, hold: 60).state
        let down = FleetEndGate.step(activeTotal: 0, countTrustworthy: false, state: held, now: 1_050, hold: 60)
        XCTAssertEqual(down.verdict, .untouched)
        XCTAssertNil(down.state.zeroSince)
    }
}
