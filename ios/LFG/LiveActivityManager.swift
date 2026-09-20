import ActivityKit
import Foundation
import LFGCore
import UIKit
import os

/// Owns the push-to-start token and the broadcast channel the fleet card listens
/// on.
///
/// There used to be a second token here — one per live card, obtained from
/// `activity.pushTokenUpdates` and uploaded so the server could address that card.
/// It is gone. Getting it required iOS to wake the app in the background after a
/// push-to-start, which on an idle phone routinely never happened (9 of 14 starts
/// on 2026-09-19 got no token back), and because a dead Live Activity token still
/// answers 200 the server could not tell it was shouting into a void — the card
/// froze on the Lock Screen and nothing ever corrected it.
///
/// A broadcast channel is addressed by id rather than by card, so there is nothing
/// left to register and nothing left to miss. Push-to-start tokens remain, because
/// broadcast cannot START an activity.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private weak var settings: AppSettings?
    private var pushToStartTask: Task<Void, Never>?
    private var activityUpdatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "dev.omg.lfg", category: "live-activity")

    /// Cached so a card can still be created when the host is briefly unreachable.
    /// A card cannot be started against an invalid channel id — Apple: "If the
    /// channel ID isn't a valid channel, the Live Activity fails to start" — so a
    /// stale-but-real id is worth far more than no id at all.
    private static let channelDefaultsKey = "lfg.liveActivity.channelId"

    private(set) var channelId: String? = UserDefaults.standard.string(forKey: channelDefaultsKey)

    /// The fleet aggregator (a Cloudflare Worker): the ONE publisher of the card,
    /// merging every host's sessions. The phone registers its push-to-start token,
    /// fetches the channel and reports card starts/ends there directly, so none of
    /// it depends on a particular Mac being awake. Any reachable host hands out the
    /// address and key once; cached so later launches need no host at all.
    private static let aggregatorDefaultsKey = "lfg.liveActivity.aggregator"
    private(set) var aggregator = FleetAggregatorConfig.decode(
        UserDefaults.standard.data(forKey: aggregatorDefaultsKey))
    private var lastStartToken: String?

    private var aggregatorClient: FleetAggregatorClient? {
        aggregator.map { FleetAggregatorClient(config: $0) }
    }

    private var deviceId: String? { UIDevice.current.identifierForVendor?.uuidString }

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
            await self.refreshAggregator()
            await self.refreshChannelId()
            await self.endDuplicateFleetActivities()
            for await _ in Activity<LFGFleetAttributes>.activityUpdates {
                // A push-to-start card lands here first — in the background too,
                // since a start push wakes the app. Collapse to one card the moment
                // a second one exists, before either side updates the wrong one.
                //
                // Nothing is registered for the card any more: it already listens
                // on the channel, chosen when it was started.
                await self.endDuplicateFleetActivities()
            }
        }
    }

    /// Ask ANY reachable host where the aggregator is — not only the default one,
    /// which is exactly the host that may be down. A host with no aggregator (or an
    /// older server) answers nothing useful and the next host is tried; a cached
    /// config survives every failure.
    func refreshAggregator() async {
        guard let settings else { return }
        for host in settings.hosts {
            guard let client = settings.client(for: host),
                  let fetched = try? await client.liveActivityAggregator() else { continue }
            if fetched != aggregator {
                aggregator = fetched
                UserDefaults.standard.set(fetched.encoded(), forKey: Self.aggregatorDefaultsKey)
                log.notice("fleet live activity aggregator: \(fetched.url.host ?? "?", privacy: .public)")
                // A token that arrived before we knew where to send it.
                if let token = lastStartToken { await sendStartToken(token) }
            }
            return
        }
    }

    /// Fetch (and cache) the broadcast channel id — from the aggregator when there
    /// is one (every host must hand out the same id), else from the default host.
    ///
    /// Failure is quiet and non-fatal: any previously cached id stays in force, and
    /// if there has never been one the app simply does not create cards itself —
    /// the server push-to-starts them instead.
    func refreshChannelId() async {
        if let agg = aggregatorClient, let fetched = try? await agg.channel(env: liveActivityEnv) {
            if fetched != channelId {
                channelId = fetched
                UserDefaults.standard.set(fetched, forKey: Self.channelDefaultsKey)
                log.notice("fleet live activity channel (aggregator): \(fetched.prefix(8), privacy: .public)…")
            }
            return
        }
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            guard let fetched = try await client.liveActivityChannel(env: liveActivityEnv) else { return }
            guard fetched != channelId else { return }
            channelId = fetched
            UserDefaults.standard.set(fetched, forKey: Self.channelDefaultsKey)
            log.notice("fleet live activity channel: \(fetched.prefix(8), privacy: .public)…")
        } catch {
            log.error("fetching live activity channel from \(host.label) failed: \(error.localizedDescription)")
        }
    }

    /// Tell the server a card exists so it adopts ours instead of starting a second.
    func reportActivityStarted() async {
        if let agg = aggregatorClient, (try? await agg.reportStarted()) != nil { return }
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.reportLiveActivityStarted()
        } catch {
            log.error("reporting fleet live activity start on \(host.label) failed: \(error.localizedDescription)")
        }
    }

    /// Tell the publisher the card is gone (see `FleetActivityController`).
    func reportActivityEnded() async {
        if let agg = aggregatorClient, (try? await agg.reportEnded()) != nil { return }
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.reportLiveActivityEnded()
        } catch {
            // Best-effort: a missed report self-heals — the publisher re-evaluates
            // on the next slice and the app dedupes any second card.
            log.error("reporting fleet live activity end on \(host.label) failed: \(error.localizedDescription)")
        }
    }

    /// One fleet card per phone. The server and the app both create cards and
    /// neither can see the other's, so this is the only place the invariant can
    /// hold. Survivor selection is `FleetActivityDedupe` (LFGCore, tested).
    @available(iOS 17.2, *)
    private func endDuplicateFleetActivities() async {
        let cards = Activity<LFGFleetAttributes>.activities
            .filter { $0.activityState == .active }
            .map { FleetActivityDedupe.Card(id: $0.id, updatedAt: $0.content.state.updatedAt) }
        guard cards.count > 1 else { return }
        let partition = FleetActivityDedupe.partition(cards)
        let losers = Set(partition.end)
        await Self.endFleetActivities(ids: losers)
        log.notice("fleet live activity dedupe: kept \(partition.keep ?? "-", privacy: .public), ended \(losers.count)")
    }

    // Looked up and consumed in its own scope — binding an `Activity` in the
    // caller and awaiting on it there trips Swift 6's region isolation ("sending
    // 'activity' risks causing data races"), as `FleetActivityController` notes.
    @available(iOS 17.2, *)
    private static func endFleetActivities(ids: Set<String>) async {
        for activity in Activity<LFGFleetAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // Register with ONLY the default host, not every host. Registering with all
    // hosts made each host's server push-to-start its own fleet activity → two cards.
    private func sendStartToken(_ token: String) async {
        lastStartToken = token
        if aggregator == nil { await refreshAggregator() }
        if let agg = aggregatorClient {
            do {
                try await agg.registerStartToken(token, env: liveActivityEnv, deviceId: deviceId)
                return
            } catch {
                log.error("start-token register on the aggregator failed: \(error.localizedDescription)")
                // Fall through: a host forwards it to the aggregator.
            }
        }
        guard let settings, let host = settings.defaultHost, let client = settings.client(for: host) else { return }
        do {
            try await client.registerLiveActivityStartToken(token, env: liveActivityEnv)
        } catch {
            log.error("live activity start-token register on \(host.label) failed: \(error.localizedDescription)")
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
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        // NSLog, not `log`: FlowDeck's log capture shows the bundle-id subsystem
        // only, and this logger lives under dev.omg.lfg.
        NSLog("[LFG_LA_MOCK] mode=%@ activitiesEnabled=%d", mode, enabled ? 1 : 0)
        guard enabled else { return }

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
                NSLog("[LFG_LA_MOCK] started fleet activity mode=%@", mode)
            } catch {
                NSLog("[LFG_LA_MOCK] FAILED: %@", String(describing: error))
                log.error("mock fleet live activity failed: \(error.localizedDescription)")
            }
        }
    }

    #endif
}
