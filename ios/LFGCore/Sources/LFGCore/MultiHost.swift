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
}
