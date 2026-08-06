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
    /// The device has had no network path since `since`, but still inside the
    /// grace window — the UI keeps showing whatever it showed before. The
    /// path-monitor analogue of `degraded`, and the fix for a real bug: on
    /// cellular `NWPathMonitor` reports transient unsatisfied paths routinely
    /// (5G↔LTE handover, VPN re-attach, resume from suspension), and this state
    /// used to banner INSTANTLY while every other failure route got 30s of
    /// grace. On LAN Wi-Fi the path never flaps, which is exactly why the bug
    /// was invisible at home and constant on 5G.
    case noNetwork(since: Date)
    /// No network path for longer than the grace window. Distinct from
    /// `offline` because it is not the host's fault and the remedy differs.
    case noNetworkSustained(since: Date)

    /// True when this host is usable right now.
    public var isLive: Bool { self == .live }

    /// When the current failure began, if any. The single clock — and it now
    /// covers path loss too, so "the phone lost signal for 2s" and "the host
    /// died" are debounced by the same rule instead of two.
    public var failingSince: Date? {
        switch self {
        case .degraded(let since, _): return since
        case .offline(let since, _): return since
        case .noNetwork(let since): return since
        case .noNetworkSustained(let since): return since
        case .unknown, .connecting, .live: return nil
        }
    }

    /// Whether the UI should paint the "unreachable" treatment.
    public var showsOfflineBanner: Bool {
        switch self {
        case .offline, .noNetworkSustained: return true
        case .unknown, .connecting, .live, .degraded, .noNetwork: return false
        }
    }

    /// Whether this state is a device-path problem rather than a host problem.
    /// The banner uses it to choose the remedy copy.
    public var isNetworkPathProblem: Bool {
        switch self {
        case .noNetwork, .noNetworkSustained: return true
        case .unknown, .connecting, .live, .degraded, .offline: return false
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
    /// The app came back to the foreground.
    ///
    /// Its only job is to discard a *path* verdict measured before the
    /// suspension. iOS tears the network path down for a suspended process on
    /// cellular, so a `noNetwork` state latched at background time says nothing
    /// about the device's connectivity now — yet it used to survive into the
    /// first frame after reopening and paint "No network connection" over a
    /// perfectly good radio. Host-health states (`degraded`/`offline`) are NOT
    /// cleared: those are facts about the host that suspension does not
    /// invalidate.
    case foregrounded
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
            // Debounced like every other failure. Losing the path is evidence
            // of a problem, not proof of a sustained one — and on cellular the
            // overwhelming majority of these clear within a second or two.
            let since = state.failingSince ?? now
            return settle(.noNetwork(since: since), now: now, graceWindow: graceWindow)

        case .networkRestored:
            // The device has a path again, but nothing has been heard from the
            // host yet. Neutral, not healthy — and not offline either.
            //
            // Crucially this does NOT reset the failure clock, for the same
            // reason `.connecting` doesn't: a path that flaps
            // restored→lost→restored every few seconds would otherwise restart
            // its own grace window forever and never reach the banner, leaving
            // a phone with no usable signal reading "connected". What changes is
            // only the *reason* — the device has a path now, so blaming the
            // radio would be the wrong remedy; what we actually know is that we
            // have not heard from the host.
            guard state.isNetworkPathProblem, let since = state.failingSince else { return state }
            return settle(.degraded(since: since, reason: "Network path restored; host not reachable yet"),
                          now: now, graceWindow: graceWindow)

        case .foregrounded:
            // Only a path verdict is stale after suspension; host health is not.
            // The clock goes with it: time spent suspended is not time we spent
            // observing the radio, so counting it would banner on reopening.
            return state.isNetworkPathProblem ? .connecting : state

        case .connecting:
            switch state {
            case .live, .unknown, .connecting:
                return .connecting
            case .degraded, .offline:
                // A redial does NOT reset the failure clock. Resetting it on
                // every retry is how a host that reconnects-and-dies in a loop
                // never reaches the banner.
                return state
            case .noNetwork, .noNetworkSustained:
                return state
            }

        case .failed(let reason), .probeFailed(let reason):
            // A failure while the device has no path stays "no network" —
            // blaming the host for the phone's radio shows the wrong remedy.
            // The clock keeps running underneath, so a real outage still lands.
            if state.isNetworkPathProblem {
                return settle(state, now: now, graceWindow: graceWindow)
            }
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
            case .degraded, .offline, .noNetwork, .noNetworkSustained: return state
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
        // Path loss settles on the same clock, into its own sustained variant so
        // the banner can still offer the right remedy ("check your signal", not
        // "check the host is running").
        if case .noNetwork(let since) = state {
            return now.timeIntervalSince(since) >= graceWindow
                ? .noNetworkSustained(since: since) : state
        }
        if case .noNetworkSustained = state { return state }

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
        let since: Date
        switch state {
        case .degraded(let s, _): since = s
        case .noNetwork(let s): since = s
        default: return nil   // live/unknown need no re-check; already-settled states are final
        }
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

public extension Reachability {
    /// The human-readable cause carried into `HostState.offline(reason:)`.
    /// `Reachability` remains the *transport's* result type — what a single ping
    /// returned — while `HostState` is the host's health over time. This is the
    /// one-way bridge between them.
    var message: String {
        switch self {
        case .ok: return ""
        case .hostUnreachable(let m), .badResponse(let m): return m
        }
    }
}

public extension HostStateMachine {
    /// Hosts that were not live before and are live now. Drives the outbox
    /// replay when a host comes back.
    static func recoveredHosts(before: [String: HostState],
                               after: [String: HostState]) -> Set<String> {
        var out: Set<String> = []
        for (id, now) in after where now.isLive {
            guard let prev = before[id], !prev.isLive else { continue }
            out.insert(id)
        }
        return out
    }
}
