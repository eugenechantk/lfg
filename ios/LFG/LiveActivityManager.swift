import ActivityKit
import Foundation
import LFGCore
import os

/// Owns ActivityKit token registration. Live Activity token updates are separate
/// from normal APNs device-token registration and are delivered through
/// ActivityKit async sequences.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private weak var settings: AppSettings?
    private var pushToStartTask: Task<Void, Never>?
    private var activityUpdatesTask: Task<Void, Never>?
    private var activityTokenTasks: [String: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "dev.omg.lfg", category: "live-activity")

    private init() {}

    func configure(settings: AppSettings) {
        self.settings = settings
        start()
    }

    /// Same convention as `PushManager.apnsEnv`: Debug → APNs sandbox,
    /// Release → production. The server treats anything ≠ "production" as
    /// sandbox, so the exact string matters for release builds.
    private var liveActivityEnv: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private func start() {
        guard #available(iOS 17.2, *) else { return }
        guard pushToStartTask == nil, activityUpdatesTask == nil else { return }

        pushToStartTask = Task { @MainActor [weak self] in
            for await token in Activity<LFGSessionAttributes>.pushToStartTokenUpdates {
                await self?.sendStartToken(apnsTokenHex(token))
            }
        }

        activityUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for activity in Activity<LFGSessionAttributes>.activities {
                self.track(activity)
            }
            for await activity in Activity<LFGSessionAttributes>.activityUpdates {
                self.track(activity)
            }
        }
    }

    @available(iOS 17.2, *)
    private func track(_ activity: Activity<LFGSessionAttributes>) {
        guard activityTokenTasks[activity.id] == nil else { return }
        let sessionId = activity.attributes.sid
        activityTokenTasks[activity.id] = Task { @MainActor [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.sendUpdateToken(apnsTokenHex(token), sessionId: sessionId)
            }
        }
    }

    private func sendStartToken(_ token: String) async {
        guard let settings, !settings.hosts.isEmpty else { return }
        for host in settings.hosts {
            guard let client = settings.client(for: host) else { continue }
            do {
                try await client.registerLiveActivityStartToken(token, env: liveActivityEnv)
            } catch {
                log.error("live activity start-token register on \(host.label) failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendUpdateToken(_ token: String, sessionId: String) async {
        guard let settings, !settings.hosts.isEmpty else { return }
        for host in settings.hosts {
            guard let client = settings.client(for: host) else { continue }
            do {
                try await client.registerLiveActivityUpdateToken(token, env: liveActivityEnv, sessionId: sessionId)
            } catch {
                log.error("live activity update-token register on \(host.label) failed: \(error.localizedDescription)")
            }
        }
    }
}
