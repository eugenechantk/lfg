import ActivityKit
import Foundation
import LFGCore
import Observation
import os

/// Drives the fleet Live Activity from the app's authoritative SessionStore while
/// the app is alive. Server APNs updates remain the suspended-app fallback.
@MainActor
final class FleetActivityController {
    static let shared = FleetActivityController()

    private weak var settings: AppSettings?
    private weak var store: SessionStore?
    private var observationArmed = false
    private var lastSnapshot: LFGCore.LFGFleetAttributes.ContentState?
    private var lastSyncedSnapshot: LFGCore.LFGFleetAttributes.ContentState?
    private let log = Logger(subsystem: "dev.omg.lfg", category: "fleet-live-activity")

    private init() {}

    func configure(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
        guard !mockFleetActivityRequested else { return }
        armObservation()
        syncNow()
    }

    func syncNow() {
        guard !mockFleetActivityRequested else { return }
        Task { @MainActor [weak self] in
            await self?.sync()
        }
    }

    private var mockFleetActivityRequested: Bool {
        #if DEBUG
        let mockMode = ProcessInfo.processInfo.environment["LFG_LA_MOCK"]
        return mockMode == "1" || mockMode == "working"
        #else
        return false
        #endif
    }

    private func armObservation() {
        guard !observationArmed, let store, let settings else { return }
        observationArmed = true
        withObservationTracking {
            _ = store.sessions
            _ = store.busy
            _ = store.prompts
            _ = store.reachabilityByHost
            _ = store.hostBySession
            _ = settings.hosts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observationArmed = false
                await self.sync()
                self.armObservation()
            }
        }
    }

    private func makeSnapshot(now: Double) -> LFGCore.LFGFleetAttributes.ContentState? {
        guard let store, let settings else { return nil }
        return FleetActivitySnapshot.contentState(
            sessions: store.sessions,
            busy: store.busy,
            prompts: store.prompts,
            hosts: settings.hosts,
            hostBySession: store.hostBySession,
            reachabilityByHost: store.reachabilityByHost,
            priorRows: lastSnapshot?.rows ?? [],
            now: now
        )
    }

    private func sync() async {
        guard #available(iOS 17.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let snapshot = makeSnapshot(now: Date().timeIntervalSince1970) else { return }
        lastSnapshot = snapshot

        let activities = Activity<LFGFleetAttributes>.activities
        let activeTotal = snapshot.working + snapshot.needsInput
        let appState = appContentState(from: snapshot)
        let content = ActivityContent(state: appState, staleDate: nil)

        do {
            // No active work → there must be NO card. End every fleet activity
            // (a server push-to-start or an old orphan may have left extras).
            if activeTotal == 0 {
                for activity in activities {
                    await activity.end(content, dismissalPolicy: .immediate)
                }
                lastSyncedSnapshot = nil
                return
            }

            // Active work → exactly ONE card. Nothing exists yet → start it.
            guard let survivor = activities.first else {
                _ = try Activity.request(
                    attributes: LFGFleetAttributes(fleetId: "fleet"),
                    content: content,
                    pushType: nil
                )
                lastSyncedSnapshot = snapshot
                return
            }

            // Collapse duplicates: keep the first, end any extras (the app + each
            // host's server can each create one, racing into 2+ cards).
            let hadDuplicates = activities.count > 1
            for extra in activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }

            if hadDuplicates || !Self.sameRenderableContent(lastSyncedSnapshot, snapshot) {
                await survivor.update(content)
                lastSyncedSnapshot = snapshot
            }
        } catch {
            log.error("fleet live activity sync failed: \(error.localizedDescription)")
        }
    }

    private static func sameRenderableContent(
        _ lhs: LFGCore.LFGFleetAttributes.ContentState?,
        _ rhs: LFGCore.LFGFleetAttributes.ContentState
    ) -> Bool {
        guard let lhs else { return false }
        guard lhs.working == rhs.working,
              lhs.needsInput == rhs.needsInput,
              lhs.rows.count == rhs.rows.count,
              lhs.hosts == rhs.hosts else { return false }
        return zip(lhs.rows, rhs.rows).allSatisfy { left, right in
            left.sid == right.sid
                && left.title == right.title
                && left.host == right.host
                && left.state == right.state
        }
    }

    private func appContentState(
        from snapshot: LFGCore.LFGFleetAttributes.ContentState
    ) -> LFGFleetAttributes.ContentState {
        LFGFleetAttributes.ContentState(
            working: snapshot.working,
            needsInput: snapshot.needsInput,
            rows: snapshot.rows.map {
                LFGFleetAttributes.Row(
                    sid: $0.sid,
                    title: $0.title,
                    host: $0.host,
                    state: $0.state,
                    since: $0.since
                )
            },
            hosts: snapshot.hosts.map {
                LFGFleetAttributes.ContentState.HostStatus(name: $0.name, online: $0.online)
            },
            updatedAt: snapshot.updatedAt
        )
    }
}
