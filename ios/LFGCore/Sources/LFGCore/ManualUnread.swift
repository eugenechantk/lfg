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
}
