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
            .noNetwork(since: t0),
            .noNetworkSustained(since: t0),
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
        XCTAssertEqual(s, .noNetwork(since: t0))
        // A failure while the device has no path stays "no network" — blaming
        // the host for the phone's radio shows the user the wrong remedy.
        XCTAssertEqual(HostStateMachine.reduce(s, .failed(reason: "x"), now: at(1)), .noNetwork(since: t0))
        // Restoring the path is not evidence the host is up — it must not go
        // `.live`, and it must not banner either.
        let restored = HostStateMachine.reduce(s, .networkRestored, now: at(2))
        XCTAssertFalse(restored.isLive)
        XCTAssertFalse(restored.showsOfflineBanner)
    }

    // MARK: defect A — a transient path loss must not banner instantly

    /// The cellular bug in one test. `NWPathMonitor` reports brief unsatisfied
    /// paths routinely on 5G (handover, VPN re-attach); this used to paint "No
    /// network connection" on the FIRST one, with no debounce at all, while
    /// every other failure route got 30s of grace.
    func testATransientPathLossIsDebouncedLikeEveryOtherFailure() {
        let lost = HostStateMachine.reduce(.live, .networkLost, now: t0)
        XCTAssertFalse(lost.showsOfflineBanner, "one path blip must not banner")
        XCTAssertFalse(HostStateMachine.settle(lost, now: at(29)).showsOfflineBanner)
        XCTAssertTrue(HostStateMachine.settle(lost, now: at(30)).showsOfflineBanner,
                      "sustained path loss must still reach the banner")
    }

    func testAPathBlipThatClearsNeverBannersAndReturnsToLive() {
        var s = HostStateMachine.reduce(.live, .networkLost, now: t0)
        s = HostStateMachine.settle(s, now: at(1.5))
        XCTAssertFalse(s.showsOfflineBanner)
        s = HostStateMachine.reduce(s, .networkRestored, now: at(2))
        XCTAssertFalse(s.showsOfflineBanner)
        s = HostStateMachine.reduce(s, .receiving, now: at(2.4))
        XCTAssertEqual(s, .live)
    }

    /// Repeated flapping must still converge on the banner — otherwise a phone
    /// with genuinely no usable signal reads "connected" forever. This is the
    /// path-monitor twin of `testRedialingDoesNotResetTheFailureClock`: the
    /// first version of the debounce let `networkRestored` clear the clock, so
    /// a lost→restored→lost cycle restarted its own grace window every few
    /// seconds and never banner.
    func testRepeatedPathFlappingStillReachesTheBanner() {
        var s: HostState = .live
        s = HostStateMachine.reduce(s, .networkLost, now: t0)
        for t in stride(from: 4.0, through: 40.0, by: 4.0) {
            s = HostStateMachine.reduce(s, .networkRestored, now: at(t))
            s = HostStateMachine.reduce(s, .networkLost, now: at(t + 1))
            s = HostStateMachine.settle(s, now: at(t + 1))
        }
        XCTAssertTrue(s.showsOfflineBanner)
        XCTAssertEqual(s.failingSince, t0, "flapping must not restart its own grace window")
    }

    /// …but a blip that ends with real bytes must never banner, and must never
    /// blame the radio once the radio is demonstrably back.
    func testRestoredPathStopsBlamingTheRadioButKeepsTheClock() {
        var s = HostStateMachine.reduce(.live, .networkLost, now: t0)
        XCTAssertTrue(s.isNetworkPathProblem)
        s = HostStateMachine.reduce(s, .networkRestored, now: at(2))
        XCTAssertFalse(s.isNetworkPathProblem,
                       "the device has a path — telling the user to check their signal is wrong")
        XCTAssertEqual(s.failingSince, t0, "the clock survives; only the reason changed")
        XCTAssertFalse(s.showsOfflineBanner)
        s = HostStateMachine.reduce(s, .receiving, now: at(2.4))
        XCTAssertEqual(s, .live)
    }

    func testSustainedPathLossIsStillDistinguishableFromAHostOutage() {
        let net = HostStateMachine.settle(
            HostStateMachine.reduce(.live, .networkLost, now: t0), now: at(31))
        let host = HostStateMachine.settle(
            HostStateMachine.reduce(.live, .failed(reason: "boom"), now: t0), now: at(31))
        XCTAssertTrue(net.showsOfflineBanner)
        XCTAssertTrue(host.showsOfflineBanner)
        XCTAssertTrue(net.isNetworkPathProblem)
        XCTAssertFalse(host.isNetworkPathProblem)
    }

    func testPathLossRecheckIsScheduledLikeADegradedHost() throws {
        let lost = HostStateMachine.reduce(.live, .networkLost, now: t0)
        XCTAssertEqual(try XCTUnwrap(HostStateMachine.timeUntilOffline(lost, now: at(10))), 20, accuracy: 0.001)
        XCTAssertNil(HostStateMachine.timeUntilOffline(
            HostStateMachine.settle(lost, now: at(31)), now: at(60)),
            "already sustained needs no re-check")
    }

    // MARK: defect C — a path verdict measured before suspension is stale

    /// iOS tears the network path down for a suspended process on cellular, so
    /// the `noNetwork` latched at background time describes the radio as it was
    /// minutes ago. It used to survive into the first frame after reopening.
    func testForegroundingDiscardsAPathVerdictMeasuredBeforeSuspension() {
        var s = HostStateMachine.settle(
            HostStateMachine.reduce(.live, .networkLost, now: t0), now: at(31))
        XCTAssertTrue(s.showsOfflineBanner)
        s = HostStateMachine.reduce(s, .foregrounded, now: at(600))
        XCTAssertEqual(s, .connecting, "reopening must not assert the old radio verdict")
        XCTAssertFalse(s.showsOfflineBanner)
    }

    func testForegroundingDoesNotEraseAGenuineHostOutage() {
        // Contrast with the above: the host being down is not invalidated by the
        // app having been suspended, so this state must survive untouched.
        let down = HostStateMachine.settle(
            HostStateMachine.reduce(.live, .failed(reason: "host down"), now: t0), now: at(31))
        XCTAssertEqual(HostStateMachine.reduce(down, .foregrounded, now: at(600)), down)
    }

    func testForegroundingAHealthyHostChangesNothing() {
        XCTAssertEqual(HostStateMachine.reduce(.live, .foregrounded, now: at(5)), .live)
        XCTAssertEqual(HostStateMachine.reduce(.unknown, .foregrounded, now: at(5)), .unknown)
        XCTAssertEqual(HostStateMachine.reduce(.connecting, .foregrounded, now: at(5)), .connecting)
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

/// Reads and writes route differently on purpose. Sharing one rule is what made
/// an offline host's sessions unopenable.
final class ReadRouteTests: XCTestCase {
    let pro = LFGCore.Host(url: "http://pro")
    let air = LFGCore.Host(url: "http://air")

    func up(_ ids: Set<String>) -> (LFGCore.Host) -> Bool { { ids.contains($0.id) } }

    func testReadPrefersTheOwnerWhenItIsUp() {
        XCTAssertEqual(MultiHost.readRouteHost(owner: air, reachable: up(["http://air"]), agnostic: pro)?.id,
                       "http://air")
    }

    func testReadFallsBackToAReachablePeerWhenTheOwnerIsDown() {
        // The whole point: the Air is down, the Pro is up and has the same synced
        // transcript. The read must go to the Pro.
        XCTAssertEqual(MultiHost.readRouteHost(owner: air, reachable: up(["http://pro"]), agnostic: pro)?.id,
                       "http://pro")
    }

    func testAWriteStillGoesToTheDownOwnerForALiveSession() {
        // Contrast: only the owner has the tmux pane, so a send must not be
        // rerouted — it has to fail honestly rather than address another agent.
        XCTAssertEqual(MultiHost.routeHost(owner: air, isClosed: false,
                                           reachable: up(["http://pro"]), agnostic: pro)?.id,
                       "http://air")
    }

    func testReadFallsBackToTheOwnerWhenNothingIsReachable() {
        // Single-host setup, host down: still hand back a client so the caller
        // can try and then fall through to its local-store hydration.
        XCTAssertEqual(MultiHost.readRouteHost(owner: air, reachable: up([]), agnostic: nil)?.id,
                       "http://air")
    }

    func testReadWithNoOwnerUsesTheAgnosticHost() {
        XCTAssertEqual(MultiHost.readRouteHost(owner: nil, reachable: up(["http://pro"]), agnostic: pro)?.id,
                       "http://pro")
    }
}
