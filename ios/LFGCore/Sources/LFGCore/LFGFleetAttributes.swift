import Foundation

/// Platform-free mirror of the app/widget `LFGFleetAttributes` so the snapshot
/// mapping can be unit-tested without ActivityKit. Keep the two in sync.
public struct LFGFleetAttributes: Codable, Hashable, Sendable {
    public struct Row: Codable, Hashable, Sendable {
        public var sid: String
        public var title: String
        /// `"working"` or `"needsInput"`.
        public var state: String
        public var since: Double

        public init(sid: String = "", title: String = "", state: String = "working", since: Double = 0) {
            self.sid = sid
            self.title = title
            self.state = state
            self.since = since
        }

        private enum CodingKeys: String, CodingKey {
            case sid, title, state, since
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sid = (try c.decodeIfPresent(String.self, forKey: .sid)) ?? ""
            title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            state = (try c.decodeIfPresent(String.self, forKey: .state)) ?? "working"
            since = (try c.decodeIfPresent(Double.self, forKey: .since)) ?? 0
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var working: Int
        public var needsInput: Int
        public var rows: [Row]
        public var more: Int
        public var updatedAt: Double

        public init(
            working: Int = 0,
            needsInput: Int = 0,
            rows: [Row] = [],
            more: Int = 0,
            updatedAt: Double = 0
        ) {
            self.working = working
            self.needsInput = needsInput
            self.rows = rows
            self.more = more
            self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case working, needsInput, rows, more, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            working = (try c.decodeIfPresent(Int.self, forKey: .working)) ?? 0
            needsInput = (try c.decodeIfPresent(Int.self, forKey: .needsInput)) ?? 0
            rows = (try c.decodeIfPresent([Row].self, forKey: .rows)) ?? []
            more = (try c.decodeIfPresent(Int.self, forKey: .more)) ?? 0
            updatedAt = (try c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
        }
    }

    public var fleetId: String

    public init(fleetId: String = "fleet") {
        self.fleetId = fleetId
    }
}
