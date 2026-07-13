import Foundation

public enum OptimisticSendReconciliation {
    public static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func containsMatchingUserTurn(
        matchText: String,
        in messages: [SessionMessage],
        prefixLength: Int = 80
    ) -> Bool {
        let needle = normalized(matchText)
        guard needle.count >= 3 else { return false }
        let key = String(needle.prefix(prefixLength))
        return messages
            .filter { $0.role == "user" && $0.kind == "text" }
            .map { normalized($0.text) }
            .contains { $0.contains(key) }
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
