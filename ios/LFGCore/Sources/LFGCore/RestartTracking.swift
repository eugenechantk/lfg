import Foundation

/// Sessions this client has asked a host to revive, and hasn't seen come back
/// live yet.
///
/// Waking a closed session is slow enough to need its own state: the server
/// polls for the revived pane's pidfile for up to 6s before it even answers the
/// resume, and the pane then takes another beat to show up in `/api/sessions`.
/// For that whole window the only thing that knows a revival is happening is the
/// client that asked for it — which is why this can't live in the
/// `SessionDisplayState` ladder the server mirrors. The window the server would
/// report during is *inside* its own blocking request.
///
/// The rule is deliberately narrow: **marked when we ask, cleared when a host
/// returns a live row for the id.** No busy/prompt heuristics — an empty resume
/// (no kickoff message) comes back live and idle, and waiting for it to look
/// busy would leave the card spinning forever.
public struct RestartTracking: Sendable, Equatable {
    /// How long a revival can stay unconfirmed before we stop claiming it. A
    /// resume that never lands should fall back to the truth ("Closed"), not
    /// spin. Generous against the server's ~6s pidfile wait plus a slow host.
    public static let defaultTimeout: TimeInterval = 45

    private var startedAt: [String: Date] = [:]

    public init() {}

    /// Ids currently marked, whether or not they've timed out.
    public var markedIds: Set<String> { Set(startedAt.keys) }

    /// Record that a revival was requested for `id`. Re-marking an already-marked
    /// id restarts its clock: a retried resume deserves a fresh window.
    public mutating func mark(_ id: String, at now: Date) {
        guard !id.isEmpty else { return }
        startedAt[id] = now
    }

    public mutating func clear(_ id: String) {
        startedAt.removeValue(forKey: id)
    }

    /// Carry the mark across an id change. Claude resumes into a NEW sessionId,
    /// so without this the row that is actually restarting loses the mark to the
    /// old transcript id the moment `remap` renames it.
    public mutating func move(from old: String, to new: String) {
        guard old != new, let started = startedAt.removeValue(forKey: old) else { return }
        guard !new.isEmpty else { return }
        startedAt[new] = started
    }

    /// Confirmation: any marked id a host now reports as live has finished
    /// restarting.
    public mutating func confirmLive(_ liveIds: Set<String>) {
        for id in startedAt.keys where liveIds.contains(id) { startedAt.removeValue(forKey: id) }
    }

    /// Drop marks that have outlived the window. Call this where the list is
    /// rebuilt so the fallback to "Closed" is driven by the same poll that would
    /// have confirmed the revival.
    public mutating func prune(now: Date, timeout: TimeInterval = RestartTracking.defaultTimeout) {
        startedAt = startedAt.filter { now.timeIntervalSince($0.value) < timeout }
    }

    public func isRestarting(
        _ id: String,
        now: Date,
        timeout: TimeInterval = RestartTracking.defaultTimeout
    ) -> Bool {
        guard let started = startedAt[id] else { return false }
        return now.timeIntervalSince(started) < timeout
    }
}
