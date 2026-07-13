#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct LFGFleetAttributes: ActivityAttributes, Sendable {
    struct Row: Codable, Hashable, Sendable {
        var sid: String
        var title: String
        var host: String
        var state: String
        var since: Double

        init(sid: String = "", title: String = "", host: String = "", state: String = "idle", since: Double = 0) {
            self.sid = sid
            self.title = title
            self.host = host
            self.state = state
            self.since = since
        }

        private enum CodingKeys: String, CodingKey {
            case sid, title, host, state, since
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sid = (try c.decodeIfPresent(String.self, forKey: .sid)) ?? ""
            title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            host = (try c.decodeIfPresent(String.self, forKey: .host)) ?? ""
            state = (try c.decodeIfPresent(String.self, forKey: .state)) ?? "idle"
            since = (try c.decodeIfPresent(Double.self, forKey: .since)) ?? 0
        }
    }

    struct ContentState: Codable, Hashable, Sendable {
        struct HostStatus: Codable, Hashable, Sendable {
            var name: String
            var online: Bool

            init(name: String = "", online: Bool = true) {
                self.name = name
                self.online = online
            }

            private enum CodingKeys: String, CodingKey {
                case name, online
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = (try c.decodeIfPresent(String.self, forKey: .name)) ?? ""
                online = (try c.decodeIfPresent(Bool.self, forKey: .online)) ?? true
            }
        }

        var working: Int
        var needsInput: Int
        var rows: [Row]
        var hosts: [HostStatus]
        var updatedAt: Double

        init(
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

        private enum CodingKeys: String, CodingKey {
            case working, needsInput, rows, hosts, updatedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            working = (try c.decodeIfPresent(Int.self, forKey: .working)) ?? 0
            needsInput = (try c.decodeIfPresent(Int.self, forKey: .needsInput)) ?? 0
            rows = (try c.decodeIfPresent([Row].self, forKey: .rows)) ?? []
            hosts = (try c.decodeIfPresent([HostStatus].self, forKey: .hosts)) ?? []
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
