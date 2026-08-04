import Foundation

/// One host's connection health, as a single value.
///
/// Before this, "is this host up" was spread across ~8 representations owned by
/// three files: `reachabilityByHost`, `failuresByHost` + a display threshold,
/// `HostProbePolicy.failureThreshold`, `HostLink.isHealthy`,
/// `HostLink.unhealthySince`, `SessionStore.unhealthySinceByHost`,
/// `networkPathSatisfied`, and `lastElementAt` + `quietRedialAfter`.
///
/// The tell was `unhealthySinceByHost`, whose own comment read *"Unlike
/// `HostLink.unhealthySince`, this survives link teardown/rebuild while the app
/// remains alive."* That is a second clock added because the first one lived in
/// an object with the wrong lifetime — and once there are two clocks, "the host
/// recovered" stops being a transition anyone can assert. It becomes a claim
/// about two values agreeing, which is why the disconnect banner could latch.
///
/// So: the clock moves out of the per-connection object and lives here, in the
/// state itself. `HostLink` reports *events* and holds no health opinion.
public enum HostState: Equatable, Sendable {
    /// Configured, but nothing observed yet (cold launch before the first dial).
    /// Deliberately distinct from `offline` — showing "Offline" for a host we
    /// simply have not asked about yet is the false-banner bug in miniature.
    case unknown
    /// Dialing, with no failure behind it. Neutral: not healthy, not offline.
    case connecting
    /// Bytes are flowing.
    case live
    /// Failing since `since`, but still inside the grace window — the UI keeps
    /// showing whatever it showed before. One clock, carried by the state.
    ///
    /// Carries `reason` because the grace window nearly always outlives the
    /// failure that started it: by the time this promotes to `offline`, the
    /// original cause is gone unless the state held onto it. (A test caught
    /// exactly that — the banner reported a generic "Connection lost" instead
    /// of what actually happened.)
    case degraded(since: Date, reason: String)
    /// Failing for longer than the grace window. This is what paints the banner.
    case offline(since: Date, reason: String)
    /// The device has no network path at all. Distinct from `offline` because
    /// it is not the host's fault and the remedy the user is shown differs.
    case noNetwork

    /// True when this host is usable right now.
    public var isLive: Bool { self == .live }

    /// When the current failure began, if any. The single clock.
    public var failingSince: Date? {
        switch self {
        case .degraded(let since, _): return since
        case .offline(let since, _): return since
        case .unknown, .connecting, .live, .noNetwork: return nil
        }
    }

    /// Whether the UI should paint the "unreachable" treatment.
    public var showsOfflineBanner: Bool {
        switch self {
        case .offline, .noNetwork: return true
        case .unknown, .connecting, .live, .degraded: return false
        }
    }
}

/// Everything that can change a host's health. `HostLink` and the REST reconcile
/// both emit these; neither interprets them.
public enum HostSignal: Equatable, Sendable {
    /// A dial started with no prior failure behind it.
    case connecting
    /// Bytes arrived — an event, or a heartbeat. The only evidence of health.
    case receiving
    /// A dial failed, or a live stream died.
    case failed(reason: String)
    /// The link was deliberately torn down (backgrounding, host removed).
    case stopped
    /// The REST reconcile reached the host.
    case probeSucceeded
    /// The REST reconcile could not reach the host.
    case probeFailed(reason: String)
    /// Device-level network path changes.
    case networkLost
    case networkRestored
}

/// The pure reducer. No networking, no UIKit, no clock of its own — `now` is
/// always injected, so every transition is deterministic under test.
public enum HostStateMachine {
    /// Fold one signal into a host's state.
    public static func reduce(
        _ state: HostState,
        _ signal: HostSignal,
        now: Date,
        graceWindow: TimeInterval = HostLinkPolicy.bannerAfter
    ) -> HostState {
        switch signal {
        case .receiving, .probeSucceeded:
            // Evidence of health always wins immediately, from any state. This
            // is "recovered" as a single assertable transition — the thing two
            // clocks could not express.
            return .live

        case .networkLost:
            return .noNetwork

        case .networkRestored:
            // The device has a path again, but nothing has been heard from the
            // host yet. Neutral, not healthy — and not offline either.
            return state == .noNetwork ? .connecting : state

        case .connecting:
            switch state {
            case .live, .unknown, .connecting:
                return .connecting
            case .degraded, .offline:
                // A redial does NOT reset the failure clock. Resetting it on
                // every retry is how a host that reconnects-and-dies in a loop
                // never reaches the banner.
                return state
            case .noNetwork:
                return .noNetwork
            }

        case .failed(let reason), .probeFailed(let reason):
            if state == .noNetwork { return .noNetwork }
            // Keep the ORIGINAL failure time; only the first failure starts the
            // clock. Then let elapsed time decide degraded vs offline.
            let since = state.failingSince ?? now
            return settle(.degraded(since: since, reason: reason), now: now, graceWindow: graceWindow)

        case .stopped:
            // A deliberate teardown is not a failure. But it must not erase an
            // in-progress failure clock either: backgrounding during an outage
            // and returning must not restart the grace window (the teardown/
            // rebuild case `unhealthySinceByHost` existed to cover).
            switch state {
            case .degraded, .offline, .noNetwork: return state
            case .unknown, .connecting, .live: return .unknown
            }
        }
    }

    /// Promote `degraded` to `offline` once the grace window has elapsed.
    ///
    /// This transition is driven by time, not by a signal, which is why the
    /// store still schedules a re-check — but the *decision* is here and pure.
    /// Call it on every signal and on that timer; it is idempotent.
    public static func settle(
        _ state: HostState,
        now: Date,
        graceWindow: TimeInterval = HostLinkPolicy.bannerAfter
    ) -> HostState {
        let reason: String
        switch state {
        case .degraded(_, let r): reason = r
        case .offline(_, let r): reason = r
        default: return state
        }
        guard let since = state.failingSince else { return state }
        return now.timeIntervalSince(since) >= graceWindow
            ? .offline(since: since, reason: reason)
            : .degraded(since: since, reason: reason)
    }

    /// Seconds until `settle` would flip this state to `offline`, or nil if it
    /// never would. The store uses this to schedule its re-check instead of
    /// recomputing the deadline at the call site.
    public static func timeUntilOffline(
        _ state: HostState,
        now: Date,
        graceWindow: TimeInterval = HostLinkPolicy.bannerAfter
    ) -> TimeInterval? {
        guard case .degraded(let since, _) = state else { return nil }
        return max(0, graceWindow - now.timeIntervalSince(since))
    }

    /// Aggregate fleet reachability for the global banner, in configured order.
    /// Mirrors `HostHealth.aggregate`'s rules on the new type: any live host
    /// means the fleet is usable; otherwise the first configured host's state
    /// speaks for it; nothing observed yet is `nil` (unknown), not offline.
    public static func aggregate(hostIds: [String], states: [String: HostState]) -> HostState? {
        guard !hostIds.isEmpty else { return nil }
        if hostIds.contains(where: { states[$0]?.isLive == true }) { return .live }
        for id in hostIds {
            if let s = states[id], s != .unknown { return s }
        }
        return nil
    }
}
