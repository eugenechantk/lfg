import Foundation

/// Per-viewer "have I seen the latest output of this session?" logic.
///
/// "Unread" is a client-side, per-device notion (the server has no concept of
/// who is looking), so the predicate is a pure function of two timestamps: when
/// the session last produced activity, and when this viewer last opened it. The
/// store persists the open times in `UserDefaults` and feeds them in here.
public enum ReadState {
    /// A completed session is *unread* when it produced activity more recently
    /// than the viewer last opened it. A session that was never opened but has
    /// any activity counts as unread (there is output the viewer hasn't seen); a
    /// session with no activity yet (`lastActivityAt == nil`) is never unread.
    ///
    /// Both timestamps are epoch milliseconds, matching `Session.lastActivityAt`.
    /// This says nothing about whether the session is idle/working/blocked — the
    /// caller gates on those first and only asks about read-state for otherwise
    /// idle (completed) sessions.
    public static func isUnread(lastActivityAt: Double?, lastOpenedAt: Double?) -> Bool {
        guard let last = lastActivityAt, last > 0 else { return false }
        return last > (lastOpenedAt ?? 0)
    }
}
