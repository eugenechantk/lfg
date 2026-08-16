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
        sentAt: Double? = nil,
        in messages: [SessionMessage],
        prefixLength: Int = 80,
        searchLimit: Int = 30,
        clockSkewAllowanceMs: Double = 5 * 60 * 1_000
    ) -> Bool {
        let needle = normalized(matchText)
        guard !needle.isEmpty else { return false }
        let requiresExactMatch = needle.count < 3
        // Without temporal causality, a one- or two-character substring is too
        // ambiguous to retire a pending row safely. Timestamped pending sends can
        // still reconcile short replies such as "ok", but only by exact text.
        guard sentAt != nil || !requiresExactMatch else { return false }
        let key = String(needle.prefix(prefixLength))

        var inspectedUserTurns = 0
        let earliestPossibleLanding = sentAt.map { $0 - clockSkewAllowanceMs }
        for message in messages.reversed() {
            guard message.role == "user", message.kind == "text" else { continue }

            if let earliestPossibleLanding, let timestamp = message.ts,
               timestamp < earliestPossibleLanding {
                // Messages are chronological. Once the reverse scan crosses
                // before this send (allowing for host/device clock skew), an
                // older same-text turn cannot be its delivery.
                break
            }

            if sentAt == nil {
                guard inspectedUserTurns < searchLimit else { break }
                inspectedUserTurns += 1
            }

            let candidate = normalized(message.text)
            if requiresExactMatch ? candidate == key : candidate.contains(key) { return true }
        }
        return false
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
