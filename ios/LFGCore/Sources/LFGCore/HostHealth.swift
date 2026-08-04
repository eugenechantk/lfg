import Foundation

/// Per-host probe policy for the multi-host poll loop.
///
/// An offline Tailscale peer is a black hole: packets are dropped with no RST, so a
/// request to it does not fail fast — it hangs for the full request timeout. Probing
/// such a host on every 3s tick, at the 15s user-initiated timeout, is what turned a
/// 3s poll into an ~18s one. This policy makes a repeatedly-failing host cheap: short
/// timeout, and probed only occasionally.
/// Every value here used to be an independent constant, with the relationships
/// between them written in English in a *different* module from the numbers they
/// constrained — so nothing failed when one drifted. Two had already drifted:
/// `coldProbeEveryNTicks` was sized for a 3s poll that became 60s, and
/// `pollTimeout` justified itself with "the next tick is 3s away".
///
/// Now the only free values are the ones a human actually chooses, expressed in
/// the units a human thinks in (seconds, not ticks). Everything with an
/// invariant attached is *derived*, so it cannot drift.
public struct HostProbePolicy: Sendable, Equatable {
    /// Consecutive failures after which the UI *shows* a host as offline.
    /// This is the human-facing debounce; the probe threshold follows from it.
    public let displayFailureThreshold: Int

    /// Consecutive failures after which a host is considered "cold" and backs off.
    ///
    /// Derived, never set: it **must** be strictly greater than the display
    /// threshold. Backing off stops incrementing the failure count on skipped
    /// ticks, so a host that went cold at or below the display threshold would
    /// freeze one short of "offline" and the banner would never appear. Deriving
    /// it makes that invariant impossible to break by editing one number.
    public var failureThreshold: Int { displayFailureThreshold + 1 }

    /// How long a cold host waits between probes, in **seconds**.
    public let coldProbeInterval: TimeInterval
    /// The reconcile loop's period, in **seconds** (`SessionStore.start()`).
    public let pollInterval: TimeInterval

    /// Derived tick count for the cold back-off. Expressing the cadence in
    /// seconds and dividing here is what stops the 3s-poll/60s-poll drift: change
    /// `pollInterval` and the tick count re-derives itself.
    public var coldProbeEveryNTicks: Int {
        guard pollInterval > 0 else { return 1 }
        return max(1, Int((coldProbeInterval / pollInterval).rounded()))
    }

    /// Per-host timeout for the poll path. Deliberately far below `LFGClient`'s 15s
    /// user-initiated timeout: this loop is a background reconcile, not a user-
    /// initiated fetch, so a poll slower than this is worth abandoning — the
    /// `HostLink`s are what actually keep a host live.
    public let pollTimeout: TimeInterval

    public init(displayFailureThreshold: Int = 3,
                coldProbeInterval: TimeInterval = 300,
                pollInterval: TimeInterval = 60,
                pollTimeout: TimeInterval = 4) {
        self.displayFailureThreshold = displayFailureThreshold
        self.coldProbeInterval = coldProbeInterval
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    /// Defaults reproduce the previously hand-tuned numbers exactly: display 3,
    /// probe 4, and 300s/60s = every 5th tick. The back-off only governs the slow
    /// background reconcile — the links reconnect on their own schedule, and
    /// foreground refreshes bypass it entirely (`SessionStore` clears the failure
    /// counts when the app comes forward).
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
