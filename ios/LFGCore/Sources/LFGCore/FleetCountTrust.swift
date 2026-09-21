import Foundation

/// When the app may trust its own active-session count for the fleet Live
/// Activity — the input `FleetEndGate` and the card-creation branch both read.
///
/// Rule: every host that is NOT known down has answered a live sessions fetch
/// this launch, and at least one such host exists.
///
/// - A known-down host is *excluded*, not a veto. Its sessions' busy flags are
///   already blanked by the store, and the fleet Worker drops a silent host after
///   90 s, so the count over the remaining hosts is the same truth the Worker
///   publishes. The old rule ("no host known down") froze the card for as long as
///   one host slept: on 2026-09-21 a card created from a stale launch view could
///   not be corrected for two hours because the Pro was asleep.
/// - A reachable host that has not answered yet is a veto: its sessions are
///   either absent or a GRDB cold snapshot, and neither is a count.
/// - Every host known down (or no hosts at all) is not trustworthy — there is
///   nothing live behind the number.
///
/// "Answered" means a successful LIVE fetch; GRDB hydration must not count.
public enum FleetCountTrust {
    public struct HostStatus: Equatable, Sendable {
        public let id: String
        public let knownDown: Bool
        public init(id: String, knownDown: Bool) {
            self.id = id
            self.knownDown = knownDown
        }
    }

    public static func isTrustworthy(hosts: [HostStatus], liveFetchedHostIds: Set<String>) -> Bool {
        let up = hosts.filter { !$0.knownDown }
        guard !up.isEmpty else { return false }
        return up.allSatisfy { liveFetchedHostIds.contains($0.id) }
    }
}
