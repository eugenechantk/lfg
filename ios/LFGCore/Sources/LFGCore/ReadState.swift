import Foundation

/// Per-viewer "have I seen the latest output of this session?" logic.
///
/// "Unread" is a client-side, per-device notion (the server has no concept of
/// who is looking), so the predicate is a pure function of two *message
/// identities*: the id of the session's newest transcript message, and the id of
/// the newest message this viewer has actually seen. The store persists the seen
/// ids in `UserDefaults` and feeds them in here.
///
/// Read-state is deliberately **not** derived from time. `Session.lastActivityAt`
/// is the transcript file's mtime, which advances whenever anything touches the
/// file — a sync daemon rewriting metadata, a metadata-only line appended by the
/// harness — with no new conversation. Keying on mtime made long-idle sessions
/// resurrect as "Unread" every time their file was touched. Message ids only
/// change when the conversation does, and comparing ids (rather than the device
/// clock against the host clock) sidesteps clock skew entirely.
public enum ReadState {
    /// A session is *unread* when its newest message isn't the newest message this
    /// viewer has seen. A session that was never opened but has a message counts as
    /// unread (there is output the viewer hasn't seen); a session with no messages
    /// yet (`lastMessageID == nil`) is never unread.
    ///
    /// This says nothing about whether the session is idle/working/blocked — the
    /// caller gates on those first and only asks about read-state for otherwise
    /// idle (completed) sessions.
    public static func isUnread(lastMessageID: String?, lastSeenMessageID: String?) -> Bool {
        guard let last = lastMessageID, !last.isEmpty else { return false }
        return last != lastSeenMessageID
    }

    /// Timestamp-based predicate, retained for the one-shot migration off the old
    /// `lfg.lastOpenedAt` store (see `SessionStore.migrateReadState`).
    ///
    /// Do not use this for live read-state. It is only correct when fed a *message*
    /// timestamp (`Session.last?.ts`) — feeding it `lastActivityAt` reintroduces the
    /// mtime bug this type exists to avoid.
    ///
    /// Both timestamps are epoch milliseconds.
    public static func isUnread(lastMessageAt: Double?, lastOpenedAt: Double?) -> Bool {
        guard let last = lastMessageAt, last > 0 else { return false }
        return last > (lastOpenedAt ?? 0)
    }
}
