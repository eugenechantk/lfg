import Foundation

public enum OptimisticSendReconciliation {
    public static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Whether `matchText` has already landed as a real user turn.
    ///
    /// Scans backwards and stops after `searchLimit` user turns: the turn we're
    /// looking for was sent seconds ago, so it is always near the tail, and the
    /// *unmatched* case is the hot one — a message queued behind a running turn
    /// stays unmatched for that whole turn while the transcript streams, and the
    /// view re-asks on every render. Unbounded, that was a full-transcript
    /// normalization (two intermediate arrays, every user turn lowercased and
    /// re-joined) per render per pending message.
    public static func containsMatchingUserTurn(
        matchText: String,
        in messages: [SessionMessage],
        prefixLength: Int = 80,
        searchLimit: Int = 30
    ) -> Bool {
        let needle = normalized(matchText)
        guard needle.count >= 3 else { return false }
        let key = String(needle.prefix(prefixLength))
        return messages
            .reversed()
            .lazy
            .filter { $0.role == "user" && $0.kind == "text" }
            .prefix(searchLimit)
            .contains { normalized($0.text).contains(key) }
    }

    public static func matchingQueueItem(
        matchText: String,
        in queue: [QueueItem],
        prefixLength: Int = 60
    ) -> QueueItem? {
        let needle = normalized(matchText)
        guard needle.count >= 3 else { return nil }
        let key = String(needle.prefix(prefixLength))
        return queue.first { normalized($0.text).contains(key) }
    }
}
