#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct LFGSessionAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var state: String
        var title: String
        var dir: String
        var host: String
        var since: Double
        var updatedAt: Double
        var subtitle: String?
        var added: Int?
        var removed: Int?
        var files: Int?

        init(
            state: String = "working",
            title: String = "",
            dir: String = "",
            host: String = "",
            since: Double = 0,
            updatedAt: Double = 0,
            subtitle: String? = nil,
            added: Int? = nil,
            removed: Int? = nil,
            files: Int? = nil
        ) {
            self.state = state
            self.title = title
            self.dir = dir
            self.host = host
            self.since = since
            self.updatedAt = updatedAt
            self.subtitle = subtitle
            self.added = added
            self.removed = removed
            self.files = files
        }

        private enum CodingKeys: String, CodingKey {
            case state, title, dir, host, since, updatedAt, subtitle, added, removed, files
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            state = (try c.decodeIfPresent(String.self, forKey: .state)) ?? "working"
            title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            dir = (try c.decodeIfPresent(String.self, forKey: .dir)) ?? ""
            host = (try c.decodeIfPresent(String.self, forKey: .host)) ?? ""
            since = (try c.decodeIfPresent(Double.self, forKey: .since)) ?? 0
            updatedAt = (try c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
            added = try c.decodeIfPresent(Int.self, forKey: .added)
            removed = try c.decodeIfPresent(Int.self, forKey: .removed)
            files = try c.decodeIfPresent(Int.self, forKey: .files)
        }
    }

    var sessionId: String

    init(sessionId: String = "") {
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = (try c.decodeIfPresent(String.self, forKey: .sessionId)) ?? ""
    }
}
#endif
