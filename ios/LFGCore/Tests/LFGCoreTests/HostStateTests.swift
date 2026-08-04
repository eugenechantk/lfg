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

/// The end-to-end sequences a real host goes through. These are the shapes that
/// the old two-clock design got wrong; each drives the reducer the way
/// `SessionStore` does, one signal at a time.
final class HostStateSequenceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// Fold a sequence the way the store does: reduce, then settle.
    func run(_ signals: [(TimeInterval, HostSignal)], from: HostState = .unknown) -> HostState {
        var s = from
        for (dt, sig) in signals {
            s = HostStateMachine.reduce(s, sig, now: at(dt))
            s = HostStateMachine.settle(s, now: at(dt))
        }
        return s
    }

    func testColdLaunchAgainstAHealthyHostNeverShowsOffline() {
        let s = run([(0, .connecting), (0.4, .receiving)])
        XCTAssertEqual(s, .live)
        XCTAssertFalse(s.showsOfflineBanner)
    }

    /// The reported symptom: host is up, app was backgrounded, path went cold.
    /// The first dial fails, then succeeds. The banner must never appear.
    func testBackgroundedThenColdPathRecoversWithoutEverBannering() {
        var s = run([(0, .connecting), (1, .receiving)])          // healthy
        s = HostStateMachine.reduce(s, .stopped, now: at(30))     // backgrounded
        s = HostStateMachine.reduce(s, .connecting, now: at(120)) // foregrounded
        XCTAssertFalse(HostStateMachine.settle(s, now: at(120)).showsOfflineBanner)
        s = HostStateMachine.reduce(s, .failed(reason: "cold path"), now: at(121))
        XCTAssertFalse(HostStateMachine.settle(s, now: at(126)).showsOfflineBanner,
                       "a few seconds of cold path must not paint the banner")
        s = HostStateMachine.reduce(s, .receiving, now: at(127))
        XCTAssertEqual(s, .live)
    }

    /// A genuinely down host must reach the banner and stay there.
    func testAGenuinelyDownHostBannersAndStays() {
        var s = run([(0, .connecting), (1, .receiving)])
        s = HostStateMachine.reduce(s, .failed(reason: "host down"), now: at(10))
        for t in stride(from: 12.0, through: 40.0, by: 4.0) {
            s = HostStateMachine.reduce(s, .connecting, now: at(t))
            s = HostStateMachine.reduce(s, .failed(reason: "host down"), now: at(t + 1))
        }
        let final = HostStateMachine.settle(s, now: at(45))
        XCTAssertTrue(final.showsOfflineBanner)
        if case .offline(_, let reason) = final { XCTAssertEqual(reason, "host down") }
        else { XCTFail("expected offline, got \(final)") }
    }

    /// A REST probe failure alone cannot banner a host whose link is streaming:
    /// heartbeats arrive at most 10s apart, well inside the 30s grace window.
    func testProbeFailuresCannotBannerAHostWhoseLinkIsStreaming() {
        var s: HostState = .live
        for t in stride(from: 0.0, through: 180.0, by: 10.0) {
            s = HostStateMachine.reduce(s, .probeFailed(reason: "timeout"), now: at(t))
            s = HostStateMachine.reduce(s, .receiving, now: at(t + 1))   // heartbeat
            s = HostStateMachine.settle(s, now: at(t + 1))
        }
        XCTAssertEqual(s, .live)
        XCTAssertFalse(s.showsOfflineBanner)
    }
}
