import ActivityKit
import Foundation
import os

/// Compatibility shim for existing app wiring. The aggregate fleet Live Activity
/// has been retired in favor of one `LFGSessionAttributes` activity per session.
@MainActor
final class FleetActivityController {
    static let shared = FleetActivityController()

    private let log = Logger(subsystem: "dev.omg.lfg", category: "fleet-live-activity")

    private init() {}

    func configure(settings: AppSettings, store: SessionStore) {
        endRetiredFleetActivities()
    }

    func syncNow() {
        endRetiredFleetActivities()
    }

    private func endRetiredFleetActivities() {
        guard #available(iOS 17.2, *) else { return }
        Task { @MainActor [log] in
            for activity in Activity<LFGFleetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                log.info("ended retired fleet live activity \(activity.id)")
            }
        }
    }
}
