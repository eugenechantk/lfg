import Foundation

/// Pure decisions behind "Move to host" (`SessionStore.transfer`).
///
/// A transfer is `close` on the source host, then `resume` on the target. The
/// close used to be a precondition, which made the move impossible in exactly
/// the situation it exists for: the source host is unreachable. These rules make
/// the close **skippable** rather than mandatory:
///
/// - Source **known down** (its state machine says offline / no network): do not
///   even try the close; resume on the target with `force` so the target skips
///   its "live on another host" veto (the source's lease is still fresh in the
///   synced tree — nothing there can release it). Remember the close for when
///   the source is back.
/// - Source **looked fine but the close failed at the transport layer**: same
///   treatment — the host just went away and the state machine has not caught
///   up yet. An HTTP-level failure is a real refusal and still aborts.
///
/// The target's resume mints a NEW session id, so the orphaned copy on the source
/// and the live copy on the target never share an id; closing the orphan later is
/// cleanup (its transcript survives a pane close), not data loss.
public enum SessionTransfer {
    public struct Plan: Equatable, Sendable {
        /// Attempt `close` on the source (and wait for it to disappear) first.
        public var closeSource: Bool
        /// Ask the target to resume past a fresh foreign lease.
        public var force: Bool
        /// Remember to close the source copy once its host is reachable again.
        public var deferSourceClose: Bool

        public static let normal = Plan(closeSource: true, force: false, deferSourceClose: false)
        public static let sourceUnreachable = Plan(closeSource: false, force: true, deferSourceClose: true)
    }

    /// The plan to start with, from what the client already knows about the
    /// source host.
    public static func plan(sourceKnownDown: Bool) -> Plan {
        sourceKnownDown ? .sourceUnreachable : .normal
    }

    /// Whether a failed close on the source means "host went away" (proceed as
    /// unreachable) rather than "host refused" (abort).
    public static func closeFailureIsUnreachable(_ error: Error) -> Bool {
        guard let e = error as? LFGError else { return false }
        switch e {
        case .notReachable, .transport, .streamStalled: return true
        case .badURL, .http, .decoding: return false
        }
    }

    // MARK: Pre-flight — ask the TARGET before touching the source

    /// What the target said about its copy of the transcript. The move itself
    /// is "resume from the synced file on the target", so if the target has no
    /// file (sync lag, Syncthing not running), no cwd, or an old copy, closing
    /// the source first buys nothing and can cost the live session.
    public enum Preflight: Equatable, Sendable {
        /// Server predates the status route: proceed exactly as before.
        case unknown
        case ready
        /// The target has no transcript for this id (yet).
        case missing
        /// The target has the transcript but not the working directory it was recorded in.
        case cwdMissing(String)
        /// The target's copy ends `seconds` before the source's last activity.
        /// Not a refusal — the user decides, knowing the newer turns stay behind.
        case behind(seconds: TimeInterval)
        /// The target could not be asked at all.
        case targetUnreachable(String)

        /// Refuses the move outright (no user choice makes it sensible).
        public var blocks: Bool {
            switch self {
            case .missing, .cwdMissing, .targetUnreachable: return true
            case .unknown, .ready, .behind: return false
            }
        }
        public var needsConfirmation: Bool {
            if case .behind = self { return true }
            return false
        }
    }

    /// A copy this far behind the source's last activity is worth a warning.
    /// Under it, the difference is ordinary sync jitter, not lost turns.
    public static let staleThreshold: TimeInterval = 60

    public static func preflight(status: TranscriptStatus, sourceLastActivityAt: Double?) -> Preflight {
        guard status.found else { return .missing }
        if let cwd = status.cwd, status.cwdExists == false { return .cwdMissing(cwd) }
        if let src = sourceLastActivityAt, let tgt = status.lastActivityAt {
            let behind = (src - tgt) / 1000
            if behind > staleThreshold { return .behind(seconds: behind) }
        }
        return .ready
    }

    /// "14 min", "2 h", "under a minute" — for the stale-copy confirmation.
    public static func behindLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "under a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 { return "\(minutes) min" }
        let hours = seconds / 3600
        if hours < 48 { return String(format: hours == hours.rounded() ? "%.0f h" : "%.1f h", hours) }
        return "\(Int((hours / 24).rounded())) days"
    }
}

/// Source-side closes that were skipped because the host was unreachable,
/// keyed by host id. Persisted (Codable) so a move made minutes before the app
/// was killed still cleans up when that host reappears.
public struct DeferredSourceCloses: Codable, Equatable, Sendable {
    public private(set) var byHost: [String: [String]]

    public init(byHost: [String: [String]] = [:]) { self.byHost = byHost }

    public var isEmpty: Bool { byHost.values.allSatisfy(\.isEmpty) }

    /// Remember `sessionId` for a close on `hostId`. Idempotent.
    public mutating func add(host hostId: String, session sessionId: String) {
        var list = byHost[hostId] ?? []
        guard !list.contains(sessionId) else { return }
        list.append(sessionId)
        byHost[hostId] = list
    }

    /// Hand back (and forget) everything owed to `hostId`. One-shot by design:
    /// a close that fails after the host is back is not worth retrying forever
    /// against a pane the user may since have reused.
    public mutating func take(host hostId: String) -> [String] {
        byHost.removeValue(forKey: hostId) ?? []
    }

    /// A session the user ends up closing or transferring themselves is no
    /// longer owed a close anywhere.
    public mutating func forget(session sessionId: String) {
        for (host, list) in byHost {
            let kept = list.filter { $0 != sessionId }
            if kept.isEmpty { byHost.removeValue(forKey: host) } else { byHost[host] = kept }
        }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> DeferredSourceCloses {
        guard let data, let v = try? JSONDecoder().decode(DeferredSourceCloses.self, from: data) else { return .init() }
        return v
    }
}
