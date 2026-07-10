#if canImport(ActivityKit)
import ActivityKit

struct LFGSessionAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var state: String
        var sid: String
        var since: Double
    }

    var sid: String
    var hostName: String
}
#endif
