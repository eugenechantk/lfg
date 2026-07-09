import XCTest
@testable import LFGCore

/// Verifies SC4 and SC7 of `.claude/feature/multihost-fanout-resilience.md`.
final class HostHealthTests: XCTestCase {

    // MARK: isCold / shouldProbe — SC4

    func testHealthyHostIsProbedEveryTick() {
        for tick in 1...12 {
            XCTAssertFalse(HostHealth.isCold(consecutiveFailures: 0))
            XCTAssertTrue(HostHealth.shouldProbe(consecutiveFailures: 0, tick: tick))
        }
    }

    /// A blip must NOT back off — the transient-blip debounce in `SessionStore.refresh`
    /// depends on the next tick retrying immediately.
    func testFailuresBelowThresholdStillProbedEveryTick() {
        for failures in 1...3 {
            for tick in 1...12 {
                XCTAssertFalse(HostHealth.isCold(consecutiveFailures: failures))
                XCTAssertTrue(HostHealth.shouldProbe(consecutiveFailures: failures, tick: tick))
            }
        }
    }

    func testAtFailureThresholdGoesCold() {
        XCTAssertTrue(HostHealth.isCold(consecutiveFailures: 4))
        XCTAssertTrue(HostHealth.isCold(consecutiveFailures: 99))
    }

    /// The coupling that makes the whole thing correct: backing off stops incrementing
    /// the failure count on skipped ticks. If a host went cold at or below the display
    /// debounce threshold (`SessionStore.failureThreshold == 3`), its count would freeze
    /// one short of "offline" and the connection banner would never appear.
    func testColdThresholdExceedsTheVisibleOfflineDebounceThreshold() {
        let sessionStoreFailureThreshold = 3   // mirrors SessionStore.failureThreshold
        XCTAssertGreaterThan(HostProbePolicy.default.failureThreshold, sessionStoreFailureThreshold)
        // A host is still probed on every tick right up to the display threshold, so it
        // can actually reach it and surface as offline.
        XCTAssertTrue(HostHealth.shouldProbe(consecutiveFailures: sessionStoreFailureThreshold, tick: 7))
    }

    func testColdHostProbedOnlyOnEveryNthTick() {
        let policy = HostProbePolicy.default   // coldProbeEveryNTicks == 10
        let probed = (1...30).filter {
            HostHealth.shouldProbe(consecutiveFailures: 5, tick: $0, policy: policy)
        }
        XCTAssertEqual(probed, [10, 20, 30])
    }

    func testColdBackoffRespectsCustomInterval() {
        let policy = HostProbePolicy(failureThreshold: 2, coldProbeEveryNTicks: 3, pollTimeout: 4)
        let probed = (1...9).filter {
            HostHealth.shouldProbe(consecutiveFailures: 2, tick: $0, policy: policy)
        }
        XCTAssertEqual(probed, [3, 6, 9])
    }

    func testZeroProbeIntervalDegradesToEveryTickAndNeverDividesByZero() {
        let policy = HostProbePolicy(failureThreshold: 1, coldProbeEveryNTicks: 0, pollTimeout: 4)
        for tick in 1...5 {
            XCTAssertTrue(HostHealth.shouldProbe(consecutiveFailures: 3, tick: tick, policy: policy))
        }
    }

    func testRecoveredHostIsProbedOnTheVeryNextTick() {
        // Cold at tick 11 (not divisible by 10) → skipped.
        XCTAssertFalse(HostHealth.shouldProbe(consecutiveFailures: 4, tick: 11))
        // A successful probe resets failures to 0 → the same tick would now probe.
        XCTAssertTrue(HostHealth.shouldProbe(consecutiveFailures: 0, tick: 11))
    }

    /// SC3 — the poll path must not inherit the 15s user-initiated timeout.
    func testPollTimeoutIsFarBelowUserInitiatedTimeout() {
        XCTAssertEqual(HostProbePolicy.default.pollTimeout, 4)
        XCTAssertLessThan(HostProbePolicy.default.pollTimeout, 15)
    }

    // MARK: aggregate — SC7

    func testNoConfiguredHostsAggregatesToNoHostConfigured() {
        XCTAssertEqual(HostHealth.aggregate(hostIds: [], health: [:]),
                       .badResponse("No host configured"))
    }

    func testAnyHealthyHostMakesAggregateOK() {
        let health: [String: Reachability] = ["a": .hostUnreachable("down"), "b": .ok]
        XCTAssertEqual(HostHealth.aggregate(hostIds: ["a", "b"], health: health), .ok)
    }

    func testAllDownSurfacesFirstConfiguredHostsFailure() {
        let health: [String: Reachability] = [
            "a": .hostUnreachable("a down"),
            "b": .badResponse("HTTP 500"),
        ]
        // Configured order drives it, not dictionary order.
        XCTAssertEqual(HostHealth.aggregate(hostIds: ["a", "b"], health: health),
                       .hostUnreachable("a down"))
        XCTAssertEqual(HostHealth.aggregate(hostIds: ["b", "a"], health: health),
                       .badResponse("HTTP 500"))
    }

    /// The regression this function exists to prevent: a cold host skipped on this tick
    /// contributes no fresh result. Deriving the banner from "results this tick" would
    /// report "No host configured" for a fleet that is merely backing off.
    func testColdSkippedHostKeepsRememberedStateAndNeverReadsAsUnconfigured() {
        let health: [String: Reachability] = ["a": .hostUnreachable("asleep")]
        let agg = HostHealth.aggregate(hostIds: ["a"], health: health)
        XCTAssertEqual(agg, .hostUnreachable("asleep"))
        XCTAssertNotEqual(agg, .badResponse("No host configured"))
    }

    func testConfiguredButNothingProbedYetIsUnknownNotFailure() {
        XCTAssertNil(HostHealth.aggregate(hostIds: ["a", "b"], health: [:]))
    }

    func testHealthEntriesForRemovedHostsAreIgnored() {
        let health: [String: Reachability] = ["removed": .ok, "a": .hostUnreachable("down")]
        XCTAssertEqual(HostHealth.aggregate(hostIds: ["a"], health: health),
                       .hostUnreachable("down"))
    }
}
