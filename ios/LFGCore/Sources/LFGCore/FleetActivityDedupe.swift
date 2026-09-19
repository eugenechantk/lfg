import Foundation

/// One fleet card per phone, enforced where cards appear.
///
/// A card can be created by the app (`Activity.request`) or by the server (an
/// APNs push-to-start), and the two are not coordinated: the server forgets the
/// card when the app reports it ended and push-starts a fresh one, while the old
/// ones sit on the Lock Screen until ActivityKit expires them. `LiveActivityManager`
/// asks this for the survivor whenever the set of fleet activities changes and ends
/// the rest. See `.claude/diagnosis-live-activity-duplicate-cards-20260918.md`.
///
/// Survivor = the card with the newest `updatedAt`: that is the one both the app and
/// the server most recently addressed, and ActivityKit exposes no creation time.
/// Ties break on the larger `id` so the answer is stable across calls — the order
/// of `Activity.activities` is not.
public enum FleetActivityDedupe {
    public struct Card: Equatable, Sendable {
        public var id: String
        public var updatedAt: Double
        public init(id: String, updatedAt: Double) {
            self.id = id
            self.updatedAt = updatedAt
        }
    }

    public struct Partition: Equatable, Sendable {
        public var keep: String?
        public var end: [String]
    }

    public static func partition(_ cards: [Card]) -> Partition {
        guard let survivor = cards.max(by: { a, b in
            if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
            return a.id < b.id
        }) else {
            return Partition(keep: nil, end: [])
        }
        return Partition(
            keep: survivor.id,
            end: cards.map(\.id).filter { $0 != survivor.id }
        )
    }
}
