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
        #if DEBUG
        startMockFleetActivityIfRequested()
        #endif
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
            for await token in Activity<LFGFleetAttributes>.pushToStartTokenUpdates {
                await self?.sendStartToken(apnsTokenHex(token))
            }
        }

        activityUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for activity in Activity<LFGFleetAttributes>.activities {
                self.track(activity)
            }
            for await activity in Activity<LFGFleetAttributes>.activityUpdates {
                self.track(activity)
            }
        }
    }

    @available(iOS 17.2, *)
    private func track(_ activity: Activity<LFGFleetAttributes>) {
        guard activityTokenTasks[activity.id] == nil else { return }
        activityTokenTasks[activity.id] = Task { @MainActor [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.sendUpdateToken(apnsTokenHex(token))
            }
        }
    }

    // Register with ONLY the default host, not every host. Registering with all
    // hosts made each host's server push-to-start its own fleet activity → two cards.
    private func sendStartToken(_ token: String) async {
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.registerLiveActivityStartToken(token, env: liveActivityEnv)
        } catch {
            log.error("live activity start-token register on \(host.label) failed: \(error.localizedDescription)")
        }
    }

    private func sendUpdateToken(_ token: String) async {
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.registerLiveActivityUpdateToken(token, env: liveActivityEnv)
        } catch {
            log.error("live activity update-token register on \(host.label) failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    func startMockFleetActivityIfRequested() {
        let mockMode = ProcessInfo.processInfo.environment["LFG_LA_MOCK"]
        guard mockMode == "1" || mockMode == "working" else { return }
        guard #available(iOS 17.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task { @MainActor in
            for activity in Activity<LFGFleetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            let now = Date().timeIntervalSince1970
            let allWorking = ProcessInfo.processInfo.environment["LFG_LA_MOCK"] == "working"
            let state = allWorking
                ? LFGFleetAttributes.ContentState(
                    working: 3,
                    needsInput: 0,
                    rows: [
                        .init(sid: "mock-sendq", title: "fix sendq bracketed paste", host: "air", state: "working", since: now - 724),
                        .init(sid: "mock-tokens", title: "migrate push tokens store", host: "pro", state: "working", since: now - 212),
                        .init(sid: "mock-reelly", title: "reelly ad pipeline refactor", host: "pro", state: "working", since: now - 95),
                    ],
                    hosts: [
                        .init(name: "pro", online: true),
                        .init(name: "air", online: false),
                    ],
                    updatedAt: now
                )
                : LFGFleetAttributes.ContentState(
                    working: 2,
                    needsInput: 2,
                    rows: [
                        .init(
                            sid: "mock-redesign",
                            title: "redesign live activity widget",
                            host: "pro",
                            state: "blocked",
                            since: now - 184
                        ),
                        .init(
                            sid: "mock-sendq",
                            title: "fix sendq bracketed paste",
                            host: "air",
                            state: "blocked",
                            since: now - 126
                        ),
                        .init(
                            sid: "mock-tokens",
                            title: "migrate push tokens store",
                            host: "pro",
                            state: "working",
                            since: now - 724
                        ),
                    ],
                    hosts: [
                        .init(name: "pro", online: true),
                        .init(name: "air", online: true),
                    ],
                    updatedAt: now
                )
            do {
                _ = try Activity.request(
                    attributes: LFGFleetAttributes(fleetId: "fleet"),
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                log.error("mock fleet live activity start failed: \(error.localizedDescription)")
            }
        }
    }
    #endif
}
