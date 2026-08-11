import Foundation

/// How far away a host is, in round-trip time, and the timeout scaling that
/// follows from it.
///
/// Every connection timeout in this client was sized against a ~5ms LAN, because
/// that is the path the phone gets on home Wi-Fi: it and the host are on the same
/// subnet, so Tailscale connects them directly. On cellular there is no LAN, the
/// direct UDP path has to be NAT-punched, and when that punch fails everything
/// falls back to a **DERP relay** — hundreds of milliseconds, tunnelled over TCP,
/// so one lost packet head-of-line blocks the whole connection. Against those
/// numbers a 4s probe timeout is not a liveness check; it is a coin flip.
///
/// RTT was already measured (`LFGClient.keepalivePing`) and the meaning was
/// already written down — "a direct Tailscale path is single-digit ms on LAN and
/// tens of ms on a punched cellular path, while a relayed one lands in the
/// hundreds". Nothing consumed it. This is the consumer.
///
/// See `.claude/diagnosis-cellular-vs-wifi-20260811.md`.
public struct PathQuality: Sendable, Equatable {
    /// How many recent samples the median is taken over. At the 10s keepalive
    /// cadence this is a ~50s window: long enough that one stalled ping cannot
    /// triple every timeout, short enough to follow a Wi-Fi→cellular handoff
    /// within a minute.
    public static let sampleWindow = 5

    /// The RTT a timeout was originally sized for. Scaling is relative to this,
    /// so anything at or below it reproduces today's constants exactly.
    public static let referenceRTT: TimeInterval = 0.05

    /// Most recent first. Bounded to `sampleWindow`.
    public private(set) var samples: [TimeInterval] = []

    public init() {}

    /// Seed with known samples. Test-facing; the app records one at a time.
    public init(samples: [TimeInterval]) {
        for s in samples.reversed() { record(rtt: s) }
    }

    /// Fold in one keepalive round-trip.
    public mutating func record(rtt: TimeInterval) {
        guard rtt.isFinite, rtt >= 0 else { return }
        samples.insert(rtt, at: 0)
        if samples.count > Self.sampleWindow { samples.removeLast(samples.count - Self.sampleWindow) }
    }

    /// Median of the window, or nil before the first sample.
    ///
    /// Median rather than mean on purpose: a single ping that lands during a
    /// relay stall is the *common* case on a bad path, and a mean would let that
    /// one sample stretch every timeout for the next 50 seconds.
    public var typicalRTT: TimeInterval? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Multiplier for a timeout sized against `referenceRTT`, clamped to
    /// `[1, maxScale]`.
    ///
    /// The floor at 1.0 is the safety property of this whole change: a derived
    /// timeout can only ever get **longer** than the constant it replaces, never
    /// shorter. A fast path — the LAN case that works today — is therefore
    /// bit-for-bit unchanged, and no amount of RTT noise can make the client
    /// more trigger-happy than it already is.
    ///
    /// `maxScale` is per-call rather than a property because the cost of waiting
    /// too long differs per timeout: an over-long probe wastes a background tick,
    /// an over-long stall watchdog shows the user dead air.
    public func scale(max maxScale: Double) -> Double {
        guard let rtt = typicalRTT, maxScale > 1 else { return 1 }
        return min(max(rtt / Self.referenceRTT, 1), maxScale)
    }

    /// Coarse label for the connection log. The point of logging it is that
    /// "the connection is iffy on 5G" becomes a value you can read back, instead
    /// of something you have to be holding the phone to notice.
    public enum Grade: String, Sendable, Equatable {
        /// Nothing measured yet.
        case unknown
        /// Same-subnet or a well-punched direct path.
        case direct
        /// A punched path with real distance, or a lightly loaded relay.
        case far
        /// Relay territory — hundreds of milliseconds.
        case relayed
    }

    public var grade: Grade {
        guard let rtt = typicalRTT else { return .unknown }
        if rtt <= Self.referenceRTT { return .direct }
        if rtt < 0.15 { return .far }
        return .relayed
    }

    /// One-line summary for the connection log.
    public var summary: String {
        guard let rtt = typicalRTT else { return "grade=unknown (no samples)" }
        return String(format: "grade=%@ rtt=%.0fms", grade.rawValue, rtt * 1000)
    }
}
