#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The single aggregate Live Activity: every session that is working or needs
/// input, in one card. There is deliberately no per-session activity — see
/// `.claude/fleet-live-activity/plan.md`.
///
/// Idle sessions never appear, which is why there is no "unread" count: unread is
/// derived from idle sessions and so is not active by definition.
struct LFGFleetAttributes: ActivityAttributes, Sendable {
    struct Row: Codable, Hashable, Sendable {
        var sid: String
        var title: String
        /// `"working"` or `"needsInput"`. Not `"blocked"` — that means *paused* in
        /// `SessionStore.Group` and carries a different colour.
        var state: String
        var since: Double

        init(sid: String = "", title: String = "", state: String = "working", since: Double = 0) {
            self.sid = sid
            self.title = title
            self.state = state
            self.since = since
        }

        private enum CodingKeys: String, CodingKey {
            case sid, title, state, since
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sid = (try c.decodeIfPresent(String.self, forKey: .sid)) ?? ""
            title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            state = (try c.decodeIfPresent(String.self, forKey: .state)) ?? "working"
            since = (try c.decodeIfPresent(Double.self, forKey: .since)) ?? 0
        }
    }

    struct ContentState: Codable, Hashable, Sendable {
        var working: Int
        var needsInput: Int
        /// Needs-input first, capped by the renderer's height budget.
        var rows: [Row]
        /// Active sessions beyond `rows`, rendered as "N More".
        var more: Int
        var updatedAt: Double

        init(
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            working = (try c.decodeIfPresent(Int.self, forKey: .working)) ?? 0
            needsInput = (try c.decodeIfPresent(Int.self, forKey: .needsInput)) ?? 0
            rows = (try c.decodeIfPresent([Row].self, forKey: .rows)) ?? []
            more = (try c.decodeIfPresent(Int.self, forKey: .more)) ?? 0
            updatedAt = (try c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
        }
    }

    var fleetId: String

    init(fleetId: String = "fleet") {
        self.fleetId = fleetId
    }

    private enum CodingKeys: String, CodingKey {
        case fleetId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fleetId = (try c.decodeIfPresent(String.self, forKey: .fleetId)) ?? "fleet"
    }
}
#endif
