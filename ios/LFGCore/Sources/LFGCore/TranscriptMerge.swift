import Foundation

public enum TranscriptMerge {
    /// Union transcript fragments by the same key used by live-event ingestion.
    /// Earlier appearances provide arrival-order tiebreaks; later duplicates
    /// replace the message payload so authoritative copies can win.
    public static func unionByStableID(_ fragments: [SessionMessage]...) -> [SessionMessage] {
        var entries: [String: (message: SessionMessage, arrival: Int)] = [:]
        var arrival = 0

        for fragment in fragments {
            for message in fragment {
                let key = message.stableID
                if let existing = entries[key] {
                    entries[key] = (message, existing.arrival)
                } else {
                    entries[key] = (message, arrival)
                }
                arrival += 1
            }
        }

        return entries.values.sorted { lhs, rhs in
            if let lts = lhs.message.ts, let rts = rhs.message.ts, lts != rts {
                return lts < rts
            }
            return lhs.arrival < rhs.arrival
        }.map(\.message)
    }
}

/// Merging a history page into the transcript the view is already rendering.
///
/// History pages arrive newest-first, so page N+1 is entirely *older* than
/// everything merged so far — it prepends. The previous implementation ignored
/// that: for every page it rebuilt a `[String: SessionMessage]` of the whole
/// transcript, took `.values` (losing all ordering), and re-sorted the entire
/// conversation. That is O(n log n) plus two full allocations per page, on the
/// MainActor, while the user is scrolling — and it got more expensive with every
/// page, precisely as the transcript got long enough for it to matter.
///
/// This does the same job in O(m) for the common prepend, and O(n + m) for the
/// general case, by exploiting two facts the old code threw away:
///
///   1. the transcript is already sorted, and
///   2. each page is already sorted.
///
/// Two sorted sequences merge in linear time; no re-sort is ever required.
extension TranscriptMerge {


    public struct Result: Equatable {
        /// The merged transcript, ordered oldest → newest.
        public let messages: [SessionMessage]
        /// Stable ids of everything in `messages`, carried so callers do not
        /// rebuild the set from scratch each page.
        public let ids: Set<String>
        /// True when the page merged as a pure prepend — diagnostic only, but
        /// worth asserting in tests so the fast path cannot silently rot into
        /// the general one.
        public let usedPrependFastPath: Bool

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.ids == rhs.ids
                && lhs.usedPrependFastPath == rhs.usedPrependFastPath
                && lhs.messages.map(\.stableID) == rhs.messages.map(\.stableID)
        }
    }

    /// Merge one already-ordered page into an already-ordered transcript.
    ///
    /// - Parameters:
    ///   - existing: current transcript, ordered oldest → newest.
    ///   - existingIDs: stable ids of `existing`. Passed in rather than derived
    ///     so the caller can keep it incrementally; deriving it here would
    ///     reintroduce the per-page O(n) rebuild this exists to remove.
    ///   - page: the arriving page, ordered oldest → newest.
    public static func merge(
        existing: [SessionMessage],
        existingIDs: Set<String>,
        page: [SessionMessage]
    ) -> Result {
        // Dedupe first. Re-delivered rows are normal: the live stream and the
        // history walk overlap, and a retried cursor re-sends its page.
        var fresh: [SessionMessage] = []
        fresh.reserveCapacity(page.count)
        var freshIDs = Set<String>()
        for m in page {
            let key = m.stableID
            guard !existingIDs.contains(key), freshIDs.insert(key).inserted else { continue }
            fresh.append(m)
        }

        guard !fresh.isEmpty else {
            return Result(messages: existing, ids: existingIDs, usedPrependFastPath: true)
        }
        guard !existing.isEmpty else {
            return Result(
                messages: fresh,
                ids: existingIDs.union(freshIDs),
                usedPrependFastPath: true)
        }

        let ids = existingIDs.union(freshIDs)

        // The overwhelmingly common shape: an older page landing entirely before
        // everything already on screen. Nothing needs comparing element by
        // element — concatenate.
        if order(fresh[fresh.count - 1]) <= order(existing[0]) {
            return Result(messages: fresh + existing, ids: ids, usedPrependFastPath: true)
        }

        // General case: interleaved timestamps (a live turn landed mid-walk, or
        // the host renumbered). Still linear — both inputs are sorted.
        var merged: [SessionMessage] = []
        merged.reserveCapacity(existing.count + fresh.count)
        var i = 0, j = 0
        while i < existing.count && j < fresh.count {
            // Ties resolve to the page, matching the prepend case above: history
            // rows sharing a timestamp with a live row are the older of the two.
            if order(fresh[j]) <= order(existing[i]) {
                merged.append(fresh[j]); j += 1
            } else {
                merged.append(existing[i]); i += 1
            }
        }
        if i < existing.count { merged.append(contentsOf: existing[i...]) }
        if j < fresh.count { merged.append(contentsOf: fresh[j...]) }

        return Result(messages: merged, ids: ids, usedPrependFastPath: false)
    }

    /// Sort key. A missing timestamp sorts oldest, which is what the previous
    /// `($0.ts ?? 0)` comparator did — kept identical so this change cannot
    /// reorder existing transcripts.
    private static func order(_ m: SessionMessage) -> Double { m.ts ?? 0 }
}
