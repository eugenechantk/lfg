import Foundation

/// When the app may END the fleet Live Activity.
///
/// Ending is the one irreversible move: the card's update token dies with it, and
/// putting a card back needs a server push-to-start plus a background wake — the
/// exact chain that misfires. The app used to end the card the instant its own
/// active count read zero, which it does at every background launch (the store is
/// empty until the first live fetch), so every server-started card died ~2 s after
/// it appeared. See `.claude/diagnosis-live-activity-stale-when-backgrounded-20260919.md`.
///
/// Rules:
/// - An untrustworthy count (no live fetch yet this launch, or a host known down)
///   is *unknown*, not zero: never end, and reset the zero clock.
/// - A trustworthy zero ends the card after `hold` seconds. The default is
///   **zero**: Eugene wants the card gone the moment nothing is running
///   (2026-09-19), and the server's `FLEET_END_DEBOUNCE_S` is zero to match.
///   The hold stays a parameter for tests and for the day a hold is wanted back.
public enum FleetEndGate {
    public static let hold: Double = 0

    public enum Verdict: Equatable, Sendable {
        /// Leave the card alone (count unknown) — no end, no zeroed update.
        case untouched
        /// Keep the card; it may be updated (to zero counters during the hold).
        case keep
        case end
    }

    public struct State: Equatable, Sendable {
        /// When a trustworthy zero was first observed; nil while anything is active
        /// or the count is unknown.
        public var zeroSince: Double?
        public init(zeroSince: Double? = nil) { self.zeroSince = zeroSince }
    }

    public static func step(
        activeTotal: Int,
        countTrustworthy: Bool,
        state: State,
        now: Double,
        hold: Double = hold
    ) -> (verdict: Verdict, state: State) {
        guard countTrustworthy else { return (.untouched, State()) }
        guard activeTotal == 0 else { return (.keep, State()) }
        let since = state.zeroSince ?? now
        if now - since >= hold { return (.end, State(zeroSince: since)) }
        return (.keep, State(zeroSince: since))
    }
}
