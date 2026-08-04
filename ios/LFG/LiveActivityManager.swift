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
    /// Seeds the one fleet activity with synthetic content so the lock-screen card
    /// can be screenshotted without driving five real sessions. Lock-screen Live
    /// Activity text is not in the accessibility tree, so a screenshot is the only
    /// way to verify this surface — in particular whether the header survives the
    /// system's fixed ~160pt frame.
    ///
    /// `LFG_LA_MOCK` values:
    ///   `1`          — frame 27's shape: 5 active, 3 rows + "2 More"
    ///   `working`    — working only, no needs-input counter
    ///   `needsInput` — needs-input only
    ///   `single`     — one row, no overflow
    func startMockFleetActivityIfRequested() {
        guard let mode = ProcessInfo.processInfo.environment["LFG_LA_MOCK"] else { return }
        guard #available(iOS 17.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date().timeIntervalSince1970
        func row(_ sid: String, _ title: String, _ state: String, _ minutesAgo: Double) -> LFGFleetAttributes.Row {
            LFGFleetAttributes.Row(sid: sid, title: title, state: state, since: now - minutesAgo * 60)
        }

        let content: LFGFleetAttributes.ContentState
        switch mode {
        case "working":
            content = .init(
                working: 2,
                needsInput: 0,
                rows: [
                    row("w1", "Read /Users/eugenechan/dev/personal/lfg/ios/LFG/Views/SessionListView.swift", "working", 2),
                    row("w2", "Running xcodegen", "working", 6),
                ],
                more: 0,
                updatedAt: now
            )
        case "needsInput":
            content = .init(
                working: 0,
                needsInput: 2,
                rows: [
                    row("b1", "Does codex work for lfg?", "needsInput", 1),
                    row("b2", "In the iOS client, can you add an option…", "needsInput", 4),
                ],
                more: 0,
                updatedAt: now
            )
        case "single":
            content = .init(
                working: 1,
                needsInput: 0,
                rows: [row("w1", "Running xcodegen", "working", 3)],
                more: 0,
                updatedAt: now
            )
        default:
            content = .init(
                working: 4,
                needsInput: 1,
                rows: [
                    row("b1", "Does codex work for lfg?", "needsInput", 1),
                    row("w1", "Read /Users/eugenechan/dev/personal/lfg/ios/LFG/Views/SessionListView.swift", "working", 2),
                    row("w2", "In the iOS client, can you add an option…", "working", 4),
                ],
                more: 2,
                updatedAt: now
            )
        }

        Task { @MainActor in
            for activity in Activity<LFGFleetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                _ = try Activity.request(
                    attributes: LFGFleetAttributes(fleetId: "fleet"),
                    content: .init(state: content, staleDate: nil),
                    pushType: nil
                )
                print("[LFG_LA_MOCK] started fleet activity mode=\(mode)")
            } catch {
                print("[LFG_LA_MOCK] FAILED: \(error)")
                log.error("mock fleet live activity failed: \(error.localizedDescription)")
            }
        }
    }

    #endif
}
