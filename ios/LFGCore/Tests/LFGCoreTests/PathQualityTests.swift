import Testing
import Foundation
@testable import LFGCore

/// Covers `.claude/feature/rtt-adaptive-timeouts.md`.
///
/// The load-bearing property is SC1/SC2: on a fast path every derived timeout
/// must equal the constant it replaced, *exactly*. That is what makes this change
/// safe to ship — the Wi-Fi case that works today cannot regress, because the
/// scale is floored at 1.0 and can only widen.
@Suite("PathQuality")
struct PathQualityTests {

    /// Seconds, to the millisecond. Ratios like `0.15 / 0.05` land at
    /// 2.9999999999999996, so a scaled timeout is 11.999999999999998s rather
    /// than 12s. That is irrelevant to a network timeout and not worth
    /// distorting the implementation to hide — but exact equality is still the
    /// right assertion for the unscaled cases below, where the scale is a
    /// literal 1.0 and the constant must come through untouched.
    private func expectSeconds(_ actual: TimeInterval, _ expected: TimeInterval,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(actual - expected) < 0.001, "\(actual)s ≉ \(expected)s",
                sourceLocation: sourceLocation)
    }

    // MARK: SC1 — no samples reproduces today's constants exactly

    @Test("No samples: scale is exactly 1 and every derived timeout is the constant")
    func coldStartIsUnchanged() {
        let q = PathQuality()
        #expect(q.typicalRTT == nil)
        #expect(q.grade == .unknown)
        #expect(q.scale(max: 3) == 1.0)

        #expect(HostProbePolicy.default.pollTimeout(for: q) == HostProbePolicy.default.pollTimeout)
        #expect(HostLinkPolicy.staleTimeout(for: q) == HostLinkPolicy.staleTimeout)
        #expect(HostLinkPolicy.keepaliveTimeout(for: q) == 5)
    }

    // MARK: SC2 — a LAN path reproduces today's constants exactly

    @Test("LAN RTT leaves every timeout at its LAN value", arguments: [0.001, 0.005, 0.02, 0.05])
    func lanIsUnchanged(rtt: TimeInterval) {
        let q = PathQuality(samples: Array(repeating: rtt, count: 5))
        #expect(q.grade == .direct)
        #expect(q.scale(max: 3) == 1.0)
        #expect(HostProbePolicy.default.pollTimeout(for: q) == 4)
        #expect(HostLinkPolicy.staleTimeout(for: q) == 20)
        #expect(HostLinkPolicy.keepaliveTimeout(for: q) == 5)
    }

    @Test("A punched cellular path (tens of ms) is still 'direct' and still unscaled")
    func punchedCellularIsUnchanged() {
        let q = PathQuality(samples: [0.04, 0.045, 0.038, 0.05, 0.042])
        #expect(q.grade == .direct)
        #expect(HostProbePolicy.default.pollTimeout(for: q) == 4)
    }

    // MARK: SC3 — a relayed path widens each timeout to its cap

    @Test("Relay RTT (150ms) hits every cap")
    func relayHitsCaps() {
        let q = PathQuality(samples: Array(repeating: 0.15, count: 5))
        #expect(q.grade == .relayed)
        // 150ms / 50ms = 3.0, so every cap is reached.
        expectSeconds(HostProbePolicy.default.pollTimeout(for: q), 12)   // 4 × 3
        expectSeconds(HostLinkPolicy.staleTimeout(for: q), 40)           // 20 × 2 (capped)
        expectSeconds(HostLinkPolicy.keepaliveTimeout(for: q), 10)       // min(5 × 2, 10)
    }

    @Test("Between LAN and relay the scaling is proportional, not stepped")
    func midRangeIsProportional() {
        let q = PathQuality(samples: Array(repeating: 0.10, count: 5))  // 2× reference
        #expect(q.grade == .far)
        expectSeconds(HostProbePolicy.default.pollTimeout(for: q), 8)    // 4 × 2
        expectSeconds(HostLinkPolicy.staleTimeout(for: q), 40)           // 20 × 2, at cap
    }

    @Test("The caps are hard — a catastrophic RTT cannot widen a timeout further")
    func capsAreHard() {
        let q = PathQuality(samples: Array(repeating: 5.0, count: 5))  // 100× reference
        #expect(HostProbePolicy.default.pollTimeout(for: q) == 12)
        #expect(HostLinkPolicy.staleTimeout(for: q) == 40)
        #expect(HostLinkPolicy.keepaliveTimeout(for: q) == 10)
        // The invariants the constants were chosen for still hold at the top of
        // the range: the poll must finish inside its own 60s interval and stay
        // under LFGClient's 15s user-initiated timeout.
        #expect(HostProbePolicy.default.pollTimeout(for: q) < HostProbePolicy.default.pollInterval)
        #expect(HostProbePolicy.default.pollTimeout(for: q) < 15)
        // A keepalive can never overlap the next one.
        #expect(HostLinkPolicy.keepaliveTimeout(for: q) <= HostLinkPolicy.keepaliveInterval)
    }

    // MARK: SC4 — robust to a single outlier

    @Test("One stalled ping among four good ones does not move the estimate")
    func medianRejectsOutlier() {
        var q = PathQuality(samples: [0.005, 0.005, 0.005, 0.005])
        q.record(rtt: 8.0)   // one ping caught in a relay stall
        #expect(q.typicalRTT == 0.005)
        #expect(q.grade == .direct)
        #expect(HostProbePolicy.default.pollTimeout(for: q) == 4)

        // A mean would have been (0.005×4 + 8)/5 = 1.604s → every timeout at its
        // cap for the next 50 seconds, off one bad sample.
        let mean = q.samples.reduce(0, +) / Double(q.samples.count)
        #expect(mean > 1.0)
    }

    @Test("A sustained change does move it — the window is not a lock")
    func sustainedChangeMoves() {
        var q = PathQuality(samples: Array(repeating: 0.005, count: 5))
        #expect(q.grade == .direct)
        // Wi-Fi → cellular relay handoff: three samples is a median majority.
        for _ in 0..<3 { q.record(rtt: 0.2) }
        #expect(q.grade == .relayed)
        expectSeconds(HostProbePolicy.default.pollTimeout(for: q), 12)
    }

    // MARK: window & input hygiene

    @Test("The window is bounded and keeps the most recent samples")
    func windowIsBounded() {
        var q = PathQuality()
        for i in 1...20 { q.record(rtt: Double(i) / 1000) }
        #expect(q.samples.count == PathQuality.sampleWindow)
        #expect(q.samples.first == 0.020)
        #expect(q.typicalRTT == 0.018)   // median of 16…20ms
    }

    @Test("Nonsense samples are ignored rather than poisoning the estimate")
    func rejectsNonsense() {
        var q = PathQuality(samples: [0.01, 0.01, 0.01])
        q.record(rtt: -1)
        q.record(rtt: .infinity)
        q.record(rtt: .nan)
        #expect(q.samples.count == 3)
        #expect(q.typicalRTT == 0.01)
    }

    @Test("Even-sized windows take the midpoint of the two middle samples")
    func evenMedian() {
        let q = PathQuality(samples: [0.01, 0.03])
        #expect(q.typicalRTT == 0.02)
    }

    @Test("Summary is readable and carries the grade and the number behind it")
    func summaryReads() {
        #expect(PathQuality().summary == "grade=unknown (no samples)")
        #expect(PathQuality(samples: [0.15]).summary == "grade=relayed rtt=150ms")
        #expect(PathQuality(samples: [0.004]).summary == "grade=direct rtt=4ms")
    }

    // MARK: the safety property, stated directly

    @Test("A derived timeout is never shorter than the constant it replaces",
          arguments: [0.0001, 0.001, 0.05, 0.06, 0.1, 0.15, 1.0, 30.0])
    func neverTightens(rtt: TimeInterval) {
        let q = PathQuality(samples: [rtt])
        #expect(HostProbePolicy.default.pollTimeout(for: q) >= HostProbePolicy.default.pollTimeout)
        #expect(HostLinkPolicy.staleTimeout(for: q) >= HostLinkPolicy.staleTimeout)
        #expect(HostLinkPolicy.keepaliveTimeout(for: q) >= 5)
    }
}
