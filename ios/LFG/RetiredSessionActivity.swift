import ActivityKit
import Foundation

/// Tombstone for the retired per-session Live Activity.
///
/// A device upgrading from the per-session build can be carrying up to five live
/// `LFGSessionAttributes` activities. ActivityKit keeps an activity alive until it
/// is ended or expires (hours later) — and an activity whose attributes type the
/// app no longer declares cannot be enumerated, so it cannot be ended either.
/// Keeping the type declared is the only way to reach those activities and end
/// them; `FleetActivityController` does that once at launch.
///
/// Nothing else may use this. There is no widget `ActivityConfiguration` for it,
/// so it can never be started again. Delete it once no installed build is old
/// enough to have started one (they self-expire well within a day).
struct LFGSessionAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        // Deliberately empty: the payload is irrelevant when the only operation
        // is `end`, and lenient decoding means a real payload still decodes.
        init() {}
        init(from decoder: Decoder) throws { self.init() }
        func encode(to encoder: Encoder) throws {}
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
