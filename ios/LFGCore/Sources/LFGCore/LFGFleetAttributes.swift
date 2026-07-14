import Foundation

public struct LFGFleetAttributes: Codable, Hashable, Sendable {
    public struct Row: Codable, Hashable, Sendable {
        public var sid: String
        public var title: String
        public var host: String
        public var state: String
        public var since: Double

        public init(sid: String = "", title: String = "", host: String = "", state: String = "idle", since: Double = 0) {
            self.sid = sid
            self.title = title
            self.host = host
            self.state = state
            self.since = since
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public struct HostStatus: Codable, Hashable, Sendable {
            public var name: String
            public var online: Bool

            public init(name: String = "", online: Bool = true) {
                self.name = name
                self.online = online
            }
        }

        public var working: Int
        public var needsInput: Int
        public var rows: [Row]
        public var hosts: [HostStatus]
        public var updatedAt: Double

        public init(
            working: Int = 0,
            needsInput: Int = 0,
            rows: [Row] = [],
            hosts: [HostStatus] = [],
            updatedAt: Double = 0
        ) {
            self.working = working
            self.needsInput = needsInput
            self.rows = rows
            self.hosts = hosts
            self.updatedAt = updatedAt
        }
    }

    public let fleetId: String

    public init(fleetId: String = "fleet") {
        self.fleetId = fleetId
    }
}
