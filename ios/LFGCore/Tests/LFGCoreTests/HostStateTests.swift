import XCTest
@testable import LFGCore

/// The behaviours two clocks could not express. Each test names the real bug it
/// pins down rather than restating the implementation.
final class HostStateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: recovery is one transition

    func testAnyEvidenceOfHealthRecoversImmediatelyFromEveryState() {
        let states: [HostState] = [
            .unknown, .connecting, .live,
            .degraded(since: t0, reason: "x"),
            .offline(since: t0, reason: "Connection lost"),
            .noNetwork,
        ]
        for s in states {
            XCTAssertEqual(HostStateMachine.reduce(s, .receiving, now: at(60)), .live,
                           "receiving must recover from \(s)")
            XCTAssertEqual(HostStateMachine.reduce(s, .probeSucceeded, now: at(60)), .live,
                           "a successful probe must recover from \(s)")
        }
    }

    // MARK: the clock

    func testFirstFailureStartsTheClockAndLaterFailuresDoNotRestartIt() {
        var s = HostStateMachine.reduce(.live, .failed(reason: "boom"), now: t0)
        XCTAssertEqual(s.failingSince, t0)
        s = HostStateMachine.reduce(s, .failed(reason: "boom again"), now: at(10))
        XCTAssertEqual(s.failingSince, t0, "a second failure must not restart the grace window")
        s = HostStateMachine.reduce(s, .failed(reason: "and again"), now: at(20))
        XCTAssertEqual(s.failingSince, t0)
    }

    func testRedialingDoesNotResetTheFailureClock() {
        // The reconnect-and-die loop: without this, a host that retries every
        // few seconds keeps restarting its own grace window and never banners.
        var s = HostStateMachine.reduce(.live, .failed(reason: "died"), now: t0)
        for i in 1...10 {
            s = HostStateMachine.reduce(s, .connecting, now: at(Double(i) * 2))
            s = HostStateMachine.reduce(s, .failed(reason: "died"), now: at(Double(i) * 2 + 1))
        }
        XCTAssertEqual(s.failingSince, t0)
        XCTAssertTrue(HostStateMachine.settle(s, now: at(31)).showsOfflineBanner)
    }

    func testGraceWindowDelaysTheBannerThenShowsIt() {
        let failed = HostStateMachine.reduce(.live, .failed(reason: "lost"), now: t0)
        XCTAssertFalse(HostStateMachine.settle(failed, now: at(29)).showsOfflineBanner,
                       "a blip inside the grace window must not paint the banner")
        XCTAssertTrue(HostStateMachine.settle(failed, now: at(30)).showsOfflineBanner)
        XCTAssertTrue(HostStateMachine.settle(failed, now: at(300)).showsOfflineBanner)
    }

    // MARK: the teardown/rebuild case unhealthySinceByHost existed for

    func testBackgroundTeardownDuringAnOutageKeepsTheClockRunning() {
        // This is precisely what the duplicated `unhealthySinceByHost` clock was
        // added to cover: the link object is destroyed and rebuilt, and the
        // failure clock must survive it.
        var s = HostStateMachine.reduce(.live, .failed(reason: "lost"), now: t0)
        s = HostStateMachine.reduce(s, .stopped, now: at(5))          // backgrounded
        XCTAssertEqual(s.failingSince, t0, "teardown must not erase an in-flight outage")
        s = HostStateMachine.reduce(s, .connecting, now: at(25))      // foregrounded, redial
        XCTAssertEqual(s.failingSince, t0)
        XCTAssertTrue(HostStateMachine.settle(s, now: at(31)).showsOfflineBanner)
    }

    func testTeardownFromAHealthyStateIsNotAFailure() {
        // Backgrounding a healthy app must not manufacture an outage.
        XCTAssertEqual(HostStateMachine.reduce(.live, .stopped, now: t0), .unknown)
        XCTAssertEqual(HostStateMachine.reduce(.connecting, .stopped, now: t0), .unknown)
        XCTAssertFalse(HostStateMachine.reduce(.live, .stopped, now: t0).showsOfflineBanner)
    }

    // MARK: unknown is not offline

    func testNothingObservedYetIsNotOffline() {
        XCTAssertFalse(HostState.unknown.showsOfflineBanner)
        XCTAssertFalse(HostState.connecting.showsOfflineBanner)
        XCTAssertNil(HostStateMachine.aggregate(hostIds: ["a"], states: ["a": .unknown]),
                     "a host we have not asked about yet is unknown, never offline")
    }

    // MARK: device network

    func testNoNetworkOverridesAndRestoreGoesToNeutralNotHealthy() {
        let s = HostStateMachine.reduce(.live, .networkLost, now: t0)
        XCTAssertEqual(s, .noNetwork)
        // A failure while the device has no path stays "no network" — blaming
        // the host for the phone's radio shows the user the wrong remedy.
        XCTAssertEqual(HostStateMachine.reduce(s, .failed(reason: "x"), now: at(1)), .noNetwork)
        // Restoring the path is not evidence the host is up.
        XCTAssertEqual(HostStateMachine.reduce(s, .networkRestored, now: at(2)), .connecting)
    }

    // MARK: settle is idempotent and preserves the original reason

    func testSettleIsIdempotentAndKeepsTheFirstReason() {
        let failed = HostStateMachine.reduce(.live, .failed(reason: "first reason"), now: t0)
        let once = HostStateMachine.settle(failed, now: at(31))
        let twice = HostStateMachine.settle(once, now: at(99))
        XCTAssertEqual(once, twice)
        if case .offline(_, let reason) = twice { XCTAssertEqual(reason, "first reason") }
        else { XCTFail("expected offline, got \(twice)") }
    }

    func testTimeUntilOfflineDrivesTheRecheckDeadline() throws {
        let failed = HostStateMachine.reduce(.live, .failed(reason: "lost"), now: t0)
        XCTAssertEqual(try XCTUnwrap(HostStateMachine.timeUntilOffline(failed, now: at(10))), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(HostStateMachine.timeUntilOffline(failed, now: at(30))), 0, accuracy: 0.001)
        XCTAssertNil(HostStateMachine.timeUntilOffline(.live, now: t0))
        XCTAssertNil(HostStateMachine.timeUntilOffline(.offline(since: t0, reason: "x"), now: at(60)),
                     "already offline needs no re-check")
    }

    // MARK: fleet aggregate

    func testOneLiveHostMakesTheFleetUsable() {
        let states: [String: HostState] = ["a": .offline(since: t0, reason: "x"), "b": .live]
        XCTAssertEqual(HostStateMachine.aggregate(hostIds: ["a", "b"], states: states), .live)
    }

    func testAllBadReportsTheFirstConfiguredHostInOrder() {
        let states: [String: HostState] = [
            "a": .offline(since: t0, reason: "first"),
            "b": .offline(since: t0, reason: "second"),
        ]
        XCTAssertEqual(HostStateMachine.aggregate(hostIds: ["a", "b"], states: states),
                       .offline(since: t0, reason: "first"))
    }

    func testNoHostsConfiguredIsNil() {
        XCTAssertNil(HostStateMachine.aggregate(hostIds: [], states: [:]))
    }
}
