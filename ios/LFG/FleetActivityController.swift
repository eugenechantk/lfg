import ActivityKit
import Foundation
import LFGCore
import Observation
import os

/// Drives the single fleet Live Activity from the app's authoritative
/// `SessionStore` while the app is alive: it starts on the first active session,
/// updates on every state change, and ends when nothing is active.
///
/// Server APNs pushes (`src/push/watcher.ts`) are the suspended-app fallback and
/// compute the same shape, so there is no fidelity seam between the two paths.
@MainActor
final class FleetActivityController {
    static let shared = FleetActivityController()

    private weak var settings: AppSettings?
    private weak var store: SessionStore?
    private var observationArmed = false
    private var lastSnapshot: LFGCore.LFGFleetAttributes.ContentState?
    private var lastSyncedSnapshot: LFGCore.LFGFleetAttributes.ContentState?
    private var endGate = FleetEndGate.State()
    private let log = Logger(subsystem: "dev.omg.lfg", category: "fleet-live-activity")

    private init() {}

    func configure(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
        endRetiredPerSessionActivities()
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
        return ProcessInfo.processInfo.environment["LFG_LA_MOCK"] != nil
        #else
        return false
        #endif
    }

    /// End any per-session activities left over from the previous build — see
    /// `RetiredSessionActivity.swift`. Without this, an upgrading device keeps up
    /// to five stale cards on its Lock Screen until they expire on their own.
    private func endRetiredPerSessionActivities() {
        guard #available(iOS 17.2, *) else { return }
        Task { @MainActor [log] in
            for activity in Activity<LFGSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                log.info("ended retired per-session live activity \(activity.id)")
            }
        }
    }

    private static let fleetId = "fleet"

    /// Re-arming one-shot observation: `withObservationTracking` fires its
    /// `onChange` exactly once, so the handler must re-arm to keep tracking.
    private func armObservation() {
        guard !observationArmed, let store else { return }
        observationArmed = true
        withObservationTracking {
            _ = store.sessions
            _ = store.busy
            _ = store.prompts
            // The snapshot reads `filteredSessions`, so the mute list is one of
            // its inputs — untracked, muting a directory wouldn't reach the card
            // until some unrelated session state happened to change.
            _ = settings?.hiddenDirs
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
        guard let store else { return nil }
        return FleetActivitySnapshot.contentState(
            // Muted directories are excluded here too: a Live Activity counting
            // sessions the list refuses to show is the same parallel-ladder bug
            // class the repo notes warn about — two surfaces, two answers.
            sessions: store.filteredSessions,
            busy: store.busy,
            prompts: store.prompts,
            priorRows: lastSnapshot?.rows ?? [],
            now: now
        )
    }

    private func sync() async {
        guard #available(iOS 17.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let snapshot = makeSnapshot(now: Date().timeIntervalSince1970) else { return }
        lastSnapshot = snapshot

        let activeTotal = snapshot.working + snapshot.needsInput
        let state = appContentState(from: snapshot)
        let exists = Self.currentActivityExists
        let now = Date().timeIntervalSince1970

        // Ending is irreversible (the token dies; a comeback needs a push-to-start
        // and a background wake), so it is gated: never on a count the store cannot
        // vouch for, and only after a sustained zero. A background launch from a
        // push-to-start has an empty store — that read as zero and killed every
        // server-started card ~2 s after it appeared.
        let gate = FleetEndGate.step(
            activeTotal: activeTotal,
            countTrustworthy: store?.fleetCountIsTrustworthy ?? false,
            state: endGate,
            now: now
        )
        endGate = gate.state

        do {
            if !exists {
                guard activeTotal > 0 else {
                    lastSyncedSnapshot = nil
                    return
                }
                // Subscribe the new card to the broadcast channel, so the server
                // can keep it current once this app suspends — with no token to
                // hand back and no background wake to depend on.
                //
                // No channel means no card: Apple is explicit that "if the channel
                // ID isn't a valid channel, the Live Activity fails to start", and
                // starting with `.token` instead would resurrect the very failure
                // this replaced (a token the server may never receive). The server
                // push-to-starts a card in that case, which does work while
                // suspended.
                guard let channelId = LiveActivityManager.shared.channelId else {
                    log.notice("no broadcast channel yet — leaving the card to the server")
                    lastSyncedSnapshot = nil
                    return
                }
                _ = try Activity.request(
                    attributes: LFGFleetAttributes(fleetId: Self.fleetId),
                    content: Self.content(state),
                    pushType: .channel(channelId)
                )
                lastSyncedSnapshot = snapshot
                await LiveActivityManager.shared.reportActivityStarted()
                return
            }

            switch gate.verdict {
            case .untouched:
                // Count unknown: leave the card exactly as the server left it.
                return
            case .end:
                await Self.endCurrentActivity(state: state)
                lastSyncedSnapshot = nil
                endGate = FleetEndGate.State()
                await reportActivityEnded()
                return
            case .keep:
                break
            }

            // Skip no-op updates: `updatedAt` and the elapsed-time labels change
            // every tick, but the card only re-renders on renderable differences.
            if !Self.sameRenderableContent(lastSyncedSnapshot, snapshot) {
                await Self.updateCurrentActivity(state: state)
                lastSyncedSnapshot = snapshot
            }
        } catch {
            log.error("fleet live activity sync failed: \(error.localizedDescription)")
        }
    }

    /// Tell the server the card is gone.
    ///
    /// Only this app knows: it ends the card when ITS active count reaches zero,
    /// and the server's count is derived independently, so the server can be left
    /// pushing updates into an activity the device has already dismissed — a dead
    /// Live Activity token still answers 200 from APNs, so nothing else would ever
    /// correct it. Once told, the server forgets the card and push-to-starts a new
    /// one, which is the only way a card can reappear while this app is suspended.
    ///
    /// Reported to the DEFAULT host only, matching `LiveActivityManager`'s token
    /// registration: telling every host would have each of them push-to-start its
    /// own card and put two on the Lock Screen.
    /// See `.claude/diagnosis-live-activity-background-updates.md`.
    private func reportActivityEnded() async {
        // Routed through `LiveActivityManager`, which knows whether the publisher
        // is the fleet aggregator or (older deployments) the default host.
        await LiveActivityManager.shared.reportActivityEnded()
    }

    // Each helper looks the activity up in its own scope and consumes it
    // immediately. Binding it once in `sync` and awaiting on it there merges it
    // into the caller's actor-isolated region, which Swift 6 rejects as a
    // potential data race ("sending 'activity' risks causing data races").

    @available(iOS 17.2, *)
    private static var currentActivityExists: Bool {
        Activity<LFGFleetAttributes>.activities.contains { $0.attributes.fleetId == fleetId }
    }

    @available(iOS 17.2, *)
    private static func endCurrentActivity(state: LFGFleetAttributes.ContentState) async {
        for activity in Activity<LFGFleetAttributes>.activities
        where activity.attributes.fleetId == fleetId {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    @available(iOS 17.2, *)
    private static func updateCurrentActivity(state: LFGFleetAttributes.ContentState) async {
        for activity in Activity<LFGFleetAttributes>.activities
        where activity.attributes.fleetId == fleetId {
            await activity.update(content(state))
        }
    }

    /// Mirrors the server's `relevanceScore` (`src/push/liveactivity.ts`). Ranks
    /// this app's own activities only — iOS decides on its own which app's card is
    /// attached to a shared Dynamic Island and which is the detached bubble; no API
    /// influences that. A fleet waiting on a human outranks one merely working.
    @available(iOS 17.2, *)
    private static func content(_ state: LFGFleetAttributes.ContentState) -> ActivityContent<LFGFleetAttributes.ContentState> {
        ActivityContent(state: state, staleDate: nil, relevanceScore: state.needsInput > 0 ? 100 : 90)
    }

    private static func sameRenderableContent(
        _ lhs: LFGCore.LFGFleetAttributes.ContentState?,
        _ rhs: LFGCore.LFGFleetAttributes.ContentState
    ) -> Bool {
        guard let lhs else { return false }
        guard lhs.working == rhs.working,
              lhs.needsInput == rhs.needsInput,
              lhs.more == rhs.more,
              lhs.rows.count == rhs.rows.count else { return false }
        return zip(lhs.rows, rhs.rows).allSatisfy { left, right in
            left.sid == right.sid
                && left.title == right.title
                && left.state == right.state
                && left.since == right.since
        }
    }

    private func appContentState(
        from snapshot: LFGCore.LFGFleetAttributes.ContentState
    ) -> LFGFleetAttributes.ContentState {
        LFGFleetAttributes.ContentState(
            working: snapshot.working,
            needsInput: snapshot.needsInput,
            rows: snapshot.rows.map {
                LFGFleetAttributes.Row(sid: $0.sid, title: $0.title, state: $0.state, since: $0.since)
            },
            more: snapshot.more,
            updatedAt: snapshot.updatedAt
        )
    }
}
