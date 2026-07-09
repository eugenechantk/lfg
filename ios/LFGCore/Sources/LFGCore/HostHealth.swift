import Foundation

/// Per-host probe policy for the multi-host poll loop.
///
/// An offline Tailscale peer is a black hole: packets are dropped with no RST, so a
/// request to it does not fail fast — it hangs for the full request timeout. Probing
/// such a host on every 3s tick, at the 15s user-initiated timeout, is what turned a
/// 3s poll into an ~18s one. This policy makes a repeatedly-failing host cheap: short
/// timeout, and probed only occasionally.
public struct HostProbePolicy: Sendable, Equatable {
    /// Consecutive failures after which a host is considered "cold" and backs off.
    ///
    /// **Must stay strictly greater than `SessionStore.failureThreshold`** (the
    /// separate debounce that decides when a host is *shown* as offline). Backing off
    /// stops incrementing the failure count on skipped ticks, so if a host went cold at
    /// or below the display threshold it would freeze one short of "offline" and the
    /// banner would never appear.
    public let failureThreshold: Int
    /// Once cold, probe only on ticks where `tick % coldProbeEveryNTicks == 0`.
    public let coldProbeEveryNTicks: Int
    /// Per-host timeout for the poll path. Deliberately far below `LFGClient`'s 15s
    /// user-initiated timeout: a poll that takes longer than this is useless anyway,
    /// the next tick is 3s away.
    public let pollTimeout: TimeInterval

    public init(failureThreshold: Int = 4, coldProbeEveryNTicks: Int = 10, pollTimeout: TimeInterval = 4) {
        self.failureThreshold = failureThreshold
        self.coldProbeEveryNTicks = coldProbeEveryNTicks
        self.pollTimeout = pollTimeout
    }

    /// 3s poll cadence → cold hosts are retried every ~30s.
    public static let `default` = HostProbePolicy()
}

/// Pure probe/health decisions for the fan-out. No networking, no UIKit — `swift test`
/// verifies the back-off and aggregation rules deterministically; `SessionStore` is the
/// thin shell that applies them.
public enum HostHealth {
    /// Whether a host is cold (backing off) given its consecutive-failure count.
    public static func isCold(consecutiveFailures: Int, policy: HostProbePolicy = .default) -> Bool {
        consecutiveFailures >= policy.failureThreshold
    }

    /// Whether to probe a host on this poll tick.
    ///
    /// Healthy hosts are probed every tick. Cold hosts are probed only every
    /// `coldProbeEveryNTicks` ticks, so a dead machine costs one short-timeout request
    /// per ~30s instead of one per 3s. `tick` is expected to start at 1 and increment
    /// once per poll; a cold host is therefore probed on the first tick divisible by N.
    public static func shouldProbe(consecutiveFailures: Int, tick: Int,
                                   policy: HostProbePolicy = .default) -> Bool {
        guard isCold(consecutiveFailures: consecutiveFailures, policy: policy) else { return true }
        guard policy.coldProbeEveryNTicks > 0 else { return true }
        return tick % policy.coldProbeEveryNTicks == 0
    }

    /// The aggregate reachability shown in the connection banner, derived from the
    /// PERSISTED per-host health map — never from "who was probed on this tick".
    ///
    /// A cold host that was skipped this tick has no fresh result, but it still has a
    /// remembered state. Deriving the aggregate from the tick's results would make an
    /// all-cold fleet report "No host configured" (there were no results) and flash the
    /// wrong banner. Rules:
    ///   - no hosts configured        → `.badResponse("No host configured")`
    ///   - any host `.ok`             → `.ok`
    ///   - all known-bad              → the first configured host's remembered failure
    ///   - configured but none known yet (cold launch, nothing probed) → `nil` (unknown)
    ///
    /// `hostIds` must be in configured order so the surfaced failure is deterministic.
    public static func aggregate(hostIds: [String],
                                 health: [String: Reachability]) -> Reachability? {
        guard !hostIds.isEmpty else { return .badResponse("No host configured") }
        if hostIds.contains(where: { health[$0] == .ok }) { return .ok }
        for id in hostIds { if let r = health[id] { return r } }
        return nil
    }
}
