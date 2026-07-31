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
