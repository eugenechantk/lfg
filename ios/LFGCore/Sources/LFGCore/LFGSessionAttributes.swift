import Foundation

public struct LFGSessionAttributes: Codable, Hashable, Sendable {
    public enum ActivityState: String, Codable, Hashable, Sendable {
        case working
        case blocked
        case finished
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var state: String
        public var title: String
        public var dir: String
        public var host: String
        public var since: Double
        public var updatedAt: Double
        public var subtitle: String?
        public var added: Int?
        public var removed: Int?
        public var files: Int?

        public init(
            state: String = ActivityState.working.rawValue,
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

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            state = (try c.decodeIfPresent(String.self, forKey: .state)) ?? ActivityState.working.rawValue
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

    public let sessionId: String

    public init(sessionId: String = "") {
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = (try c.decodeIfPresent(String.self, forKey: .sessionId)) ?? ""
    }
}

public enum LFGSessionActivityPresentation {
    public static func normalizedState(_ raw: String) -> LFGSessionAttributes.ActivityState {
        LFGSessionAttributes.ActivityState(rawValue: raw.lowercased()) ?? .working
    }

    public static func compactElapsed(since: Double, at date: Date) -> String {
        guard since > 0 else { return "now" }
        let seconds = max(0, Int(date.timeIntervalSince1970 - since))
        guard seconds >= 60 else { return "now" }

        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes)m" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    public static func diffSummary(added: Int?, removed: Int?, files: Int?) -> String? {
        guard let added, let removed, let files else { return nil }
        return "+\(added) −\(removed) · \(files) Files"
    }
}
