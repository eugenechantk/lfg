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
        startMockSessionActivitiesIfRequested()
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
        activityTokenTasks[activity.id] = Task { @MainActor [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.sendUpdateToken(apnsTokenHex(token), sessionId: activity.attributes.sessionId)
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

    private func sendUpdateToken(_ token: String, sessionId: String) async {
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.registerLiveActivityUpdateToken(token, env: liveActivityEnv, sessionId: sessionId)
        } catch {
            log.error("live activity update-token register on \(host.label) failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    func startMockSessionActivitiesIfRequested() {
        // "1" seeds all three variants. Passing a single state name
        // ("working" / "blocked" / "finished") seeds just that one — iOS renders
        // only one Live Activity per app on the Lock Screen at a time, so a
        // single-variant seed is the only way to visually verify the other cards.
        // "stressN" (e.g. "stress8") seeds N synthetic activities to measure how
        // many ActivityKit will actually accept — the server's cap is derived
        // from that ceiling, not from a guessed constant.
        let mockMode = ProcessInfo.processInfo.environment["LFG_LA_MOCK"]
        let wanted = ["working", "blocked", "finished"].first { $0 == mockMode }
        let stressCount = (mockMode?.hasPrefix("stress") ?? false)
            ? Int(mockMode!.dropFirst("stress".count)) ?? 8
            : nil
        guard mockMode == "1" || wanted != nil || stressCount != nil else { return }
        guard #available(iOS 17.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task { @MainActor in
            for activity in Activity<LFGSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            for activity in Activity<LFGFleetAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            let now = Date().timeIntervalSince1970
            let states: [(LFGSessionAttributes, LFGSessionAttributes.ContentState)] = [
                (
                    LFGSessionAttributes(sessionId: "mock-working"),
                    LFGSessionAttributes.ContentState(
                        state: "working",
                        title: "Read /Users/eugenechan/dev/personal/lfg/ios/LFG/Views/SessionListView.swift",
                        dir: "lfg",
                        host: "Eugenes-MacBook-Pro",
                        since: now - 60,
                        updatedAt: now,
                        subtitle: "Running xcodegen"
                    )
                ),
                (
                    LFGSessionAttributes(sessionId: "mock-blocked"),
                    LFGSessionAttributes.ContentState(
                        state: "blocked",
                        title: "Does codex work for lfg?",
                        dir: "inbox",
                        host: "Eugenes-MacBook-Pro",
                        since: now - 60,
                        updatedAt: now
                    )
                ),
                (
                    LFGSessionAttributes(sessionId: "mock-finished"),
                    LFGSessionAttributes.ContentState(
                        state: "finished",
                        title: "can you take screenshots of all the states in the iOS client",
                        dir: "lfg",
                        host: "Air",
                        since: now - 60,
                        updatedAt: now,
                        added: 142,
                        removed: 38,
                        files: 6
                    )
                ),
            ]
            // Per-request try/catch, NOT one around the loop: a single throw used
            // to abort the remaining requests, so only the first mock card ever
            // appeared and the blocked/finished variants were invisible. The
            // inter-request pause keeps ActivityKit from rejecting a rapid burst.
            var selected = wanted.map { w in states.filter { $0.1.state == w } } ?? states
            if let n = stressCount {
                selected = (1...n).map { i in
                    (
                        LFGSessionAttributes(sessionId: "mock-stress-\(i)"),
                        LFGSessionAttributes.ContentState(
                            state: "working",
                            title: "Stress session \(i)",
                            dir: "lfg",
                            host: "Eugenes-MacBook-Pro",
                            since: now - Double(i * 60),
                            updatedAt: now
                        )
                    )
                }
            }
            for (attributes, state) in selected {
                do {
                    _ = try Activity.request(
                        attributes: attributes,
                        content: .init(state: state, staleDate: nil),
                        pushType: nil
                    )
                    print("[LFG_LA_MOCK] started \(attributes.sessionId)")
                } catch {
                    print("[LFG_LA_MOCK] FAILED \(attributes.sessionId): \(error)")
                    log.error("mock live activity \(attributes.sessionId) failed: \(error.localizedDescription)")
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
    #endif
}
