import Foundation

/// Pure bookkeeping for sessions the user explicitly put back into the Unread
/// group. This is separate from `ReadState`: clearing `lastSeenMessageID` would
/// be undone while the detail view remains focused.
public enum ManualUnread {
    /// Opening a session means the user is reading it again, so its manual unread
    /// flag is consumed. Other manual flags survive unchanged.
    public static func afterOpening(_ sessionID: String, flags: Set<String>) -> Set<String> {
        guard !sessionID.isEmpty, flags.contains(sessionID) else { return flags }
        var updated = flags
        updated.remove(sessionID)
        return updated
    }

    /// Local placeholders are not durable server sessions yet.
    public static func canMarkUnread(_ sessionID: String) -> Bool {
        !sessionID.isEmpty && !sessionID.hasPrefix("local-")
    }

    /// What a leading swipe on a session-list row should offer. Mirrors Mail:
    /// the row's current reading state picks the verb, so a row you flagged by
    /// mistake has a list-level undo.
    public enum ListAction: Equatable {
        case markRead
        case markUnread
    }

    /// `isUnread` is the row's rendered group (manual flag OR unseen messages);
    /// `isClosed` because `closed` outranks `unread` in the group ladder, so a
    /// flag on a closed row could never surface — offering it would be a dead
    /// action.
    public static func listAction(sessionID: String, isUnread: Bool, isClosed: Bool) -> ListAction? {
        guard canMarkUnread(sessionID), !isClosed else { return nil }
        return isUnread ? .markRead : .markUnread
    }
}
