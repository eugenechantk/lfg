import Foundation

/// Result of merging several hosts' session lists into one: the unified list the
/// UI renders, plus a routing table from each session's `id` to the host that
/// owns it (so every per-session op is sent to the right machine).
public struct MergedSessions: Sendable, Equatable {
    public var sessions: [Session]
    /// session.id → Host.id (the owning host's url).
    public var hostBySession: [String: String]

    public init(sessions: [Session], hostBySession: [String: String]) {
        self.sessions = sessions
        self.hostBySession = hostBySession
    }
}

/// Pure fan-out reconciliation for the multi-host client. No networking, no
/// UIKit — `swift test` verifies the merge/dedupe rules deterministically.
public enum MultiHost {
    /// Merge each host's live sessions into one list, recording which host owns
    /// each session. A session id seen from more than one host keeps the FIRST
    /// host's copy (a session is live on exactly one machine at a time; the tie
    /// only happens transiently during a transfer, and first-wins is stable).
    public static func mergeSessions(_ perHost: [(host: Host, sessions: [Session])]) -> MergedSessions {
        var out: [Session] = []
        var owner: [String: String] = [:]
        for (host, sessions) in perHost {
            for s in sessions {
                if owner[s.id] != nil { continue } // first host wins
                owner[s.id] = host.id
                out.append(s)
            }
        }
        return MergedSessions(sessions: out, hostBySession: owner)
    }

    /// Reconcile the resumable (closed) lists from every host. Because
    /// `~/.claude/projects` is SYNCED, both machines enumerate the SAME
    /// transcripts, so:
    ///   1. dedupe by sessionId (one entry per synced transcript), and
    ///   2. drop any id that is LIVE on *any* host — kills the phantom where
    ///      host B lists host A's running session as "resumable" because B only
    ///      sees its own live panes.
    /// A resumable session is host-agnostic: it can be resumed on whichever host
    /// the user picks (this is also the "transfer a closed session" path).
    /// Order is preserved by first appearance (hosts are passed newest-first).
    public static func reconcileResumable(perHost: [[ResumableSession]], liveIds: Set<String>) -> [ResumableSession] {
        var seen = Set<String>()
        var out: [ResumableSession] = []
        for list in perHost {
            for r in list {
                if liveIds.contains(r.sessionId) { continue }
                if seen.contains(r.sessionId) { continue }
                seen.insert(r.sessionId)
                out.append(r)
            }
        }
        return out
    }

    /// Which host a per-session op must be sent to during a partial outage.
    ///
    /// - `owner` reachable → **owner**. The common case.
    /// - `owner` down, session **live** → **owner** anyway. A live session's agent
    ///   pane exists only on its own machine; rerouting the op to a healthy host
    ///   would address a *different* agent (or spawn one). The op must fail
    ///   honestly rather than land somewhere surprising.
    /// - otherwise (no known owner, or owner down and the session is **closed**) →
    ///   **`agnostic`**, the reachable default. A closed session is host-agnostic:
    ///   its transcript is synced, so any live machine can revive it. This is what
    ///   lets a closed session restart while the marked-default host is down.
    ///
    /// `agnostic` should be `HostStore.defaultHost(hosts, reachable:)`.
    public static func routeHost(owner: Host?, isClosed: Bool,
                                 reachable: (Host) -> Bool, agnostic: Host?) -> Host? {
        if let owner {
            if reachable(owner) { return owner }
            if !isClosed { return owner }
        }
        return agnostic
    }

    /// Whether a session's work is currently unreachable — i.e. it is LIVE on a
    /// host that is down. Closed sessions are never "offline": any reachable host
    /// can revive their synced transcript. Drives the dimmed list row and the
    /// disabled composer.
    public static func isOffline(owner: Host?, isClosed: Bool, reachable: (Host) -> Bool) -> Bool {
        guard let owner else { return false }
        return !reachable(owner) && !isClosed
    }

    /// Host ids that went from a **known-unreachable** state to reachable between
    /// two health snapshots. Drives the "resend what failed while you were down"
    /// path.
    ///
    /// A host absent from `before` is deliberately NOT a recovery: at cold start
    /// `reachabilityByHost` is empty, so every host would look like it had just
    /// come back and the resend sweep would fire on every launch. Only a host we
    /// actually observed failing can recover.
    public static func recoveredHosts(before: [String: Reachability],
                                      after: [String: Reachability]) -> Set<String> {
        var out: Set<String> = []
        for (id, now) in after where now == .ok {
            guard let prev = before[id], prev != .ok else { continue }
            out.insert(id)
        }
        return out
    }
}
