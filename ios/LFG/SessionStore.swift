import SwiftUI
import UIKit
import LFGCore

/// The single source of truth for live session state. Reduces `GET /api/sessions`
/// snapshots plus the `/api/live/stream` SSE deltas (msg/prompt/busy/queue) into
/// observable per-session state the views render.
@MainActor @Observable final class SessionStore {
    let settings: AppSettings

    private(set) var sessions: [Session] = []
    /// Aggregate reachability: `.ok` if ANY configured host is reachable, else a
    /// representative failure. The list/banner read this; per-host detail lives in
    /// `reachabilityByHost`.
    private(set) var reachability: Reachability?
    /// Per-host reachability, keyed by `Host.id` (url). Drives the Settings
    /// per-host dots and the reachable-set for default-host placement.
    private(set) var reachabilityByHost: [String: Reachability] = [:]
    /// Routing table: session `id` → owning `Host.id` (url). Every per-session op
    /// resolves the host's client through this. Rebuilt each refresh.
    private(set) var hostBySession: [String: String] = [:]
    var lastError: String?

    /// Consecutive failed polls since the last success, PER host. Used to debounce
    /// the visible `reachability` so a single transient blip (the single-event-loop
    /// Bun server documented to stall HTTP 20s+ under PTY load, a tailnet reroute,
    /// an app-just-foregrounded gap) doesn't flip a healthy host to "Offline" —
    /// which then contradicts a fresh Settings ping. See
    /// `.claude/diagnosis-settings-reachable-list-offline.md`.
    private var failuresByHost: [String: Int] = [:]
    /// Failed polls to tolerate before surfacing "not reachable" from a
    /// currently-healthy state (~9s at the 3s poll interval).
    private let failureThreshold = 3

    // Per-session live state, keyed by sessionId.
    private(set) var transcripts: [String: [SessionMessage]] = [:]
    private(set) var prompts: [String: AgentPrompt] = [:]
    private(set) var busy: [String: Bool] = [:]
    private(set) var queues: [String: [QueueItem]] = [:]

    /// Locally-originated sends shown optimistically as user bubbles the instant
    /// the user hits send — before any network round-trip. Each is removed once
    /// the agent records the matching user turn in the transcript (reconciled by
    /// text), so the optimistic bubble hands off seamlessly to the real message.
    /// Keyed by sessionId, in send order.
    private(set) var pendingSends: [String: [PendingSend]] = [:]

    struct PendingSend: Identifiable, Equatable {
        let id: String            // client-generated UUID
        var displayText: String   // what the user typed (shown in the bubble)
        var matchText: String     // full sent text incl. attachment paths (for reconcile)
        var ts: Double            // device send time, epoch ms (ordering)
        var failed: Bool = false
        var serverQueueID: String? = nil   // set once correlated to a server queue item
        /// Render as a finished user bubble in the transcript rather than the
        /// muted "Sending…" bar. Used for a session's kickoff message, which is
        /// already committed (it created the session) so a pending state is noise.
        var showSent: Bool = false
        /// Whether the backend has accepted this send yet. `true` for the normal
        /// path (the agent picks an idle/live session up instantly, so the bubble
        /// reads as sent immediately). `false` for a wake-up send to a session
        /// whose pane was reaped: the server has to resume the conversation first
        /// (a real 1–6s round-trip), so the bubble renders muted/gray until the
        /// send returns, then animates to the confirmed accent color.
        var confirmed: Bool = true
    }

    /// Client-created sessions shown before the server has assigned a real id.
    /// Each carries a placeholder id ("local-…") and is merged into `sessions`
    /// so the 3s poll can't drop it before the real session arrives; it's
    /// removed once the create round-trip reconciles the placeholder to the
    /// server's id (see `remap`).
    private(set) var optimisticSessions: [Session] = []
    /// The create request behind each placeholder id, kept so a failed create
    /// can be retried straight from the optimistic kickoff bubble.
    private var pendingCreates: [String: NewSessionRequest] = [:]
    /// The host each placeholder create targets, so a retry re-creates on the
    /// same machine the user picked.
    private var pendingCreateHost: [String: Host] = [:]

    /// A session a tapped push notification asked us to open. RootView observes
    /// this and drives its navigation selection, then clears it.
    private(set) var requestedSelection: String?

    // Create-flow lookups.
    private(set) var repos: [Repo] = []
    private(set) var root: String = ""
    private(set) var inbox: String = ""
    private(set) var users: [String] = []
    private(set) var usage: Usage?

    private var seen: [String: Set<String>] = [:]

    /// Per-session "last time this viewer opened it" (epoch ms), persisted in
    /// UserDefaults so unread marks survive relaunch. A completed (idle) session
    /// whose `lastActivityAt` is newer than its entry here is shown as "Unread".
    /// Populated on open (`focus`) and kept current for the session on screen as
    /// it streams. See `ReadState.isUnread` for the predicate.
    private var lastOpenedAt: [String: Double]
    private static let lastOpenedKey = "lfg.lastOpenedAt"

    // Live SSE streams, one per host (each host has its own /api/live/stream and
    // its own 24-id cap). Keyed by Host.id (url).
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var streamedIDsByHost: [String: [String]] = [:]
    private var pollTask: Task<Void, Never>?
    private var focusedID: String?

    /// Closed (resumable) sessions synthesized from `/api/sessions/resumable`,
    /// merged into `sessions` each poll so ended sessions stay visible. Refreshed
    /// on a slower cadence than the 3s live poll (see `resumeTick`) since the
    /// resumable list changes rarely and each fetch reads transcript heads.
    private var closedCache: [Session] = []
    private var resumeTick = 0
    /// Ids of closed sessions we've resumed this run. Claude resumes into a NEW
    /// sessionId while the old transcript lingers on disk (so it keeps showing as
    /// resumable) — suppress the stale closed card once we've revived it.
    private var resumedIds: Set<String> = []

    /// Last successful live-session snapshot PER host (keyed by Host.id). A host
    /// that blips (transiently unreachable) keeps contributing its last-known
    /// sessions to the merged list rather than having them vanish for a poll —
    /// the resilience the single-host path got from the server's `lastGood`.
    private var lastSessionsByHost: [String: [Session]] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        lastOpenedAt = (UserDefaults.standard.dictionary(forKey: Self.lastOpenedKey) as? [String: Double]) ?? [:]
    }

    /// Host-agnostic client: the default host. Used for create-flow metadata
    /// (dirs/users/usage) and resumable lookups (transcripts are synced, so any
    /// host answers). Per-session ops must use `client(forSession:)` instead.
    var client: LFGClient? { settings.defaultClient }

    /// The host that currently owns a session (nil if unknown → falls back to
    /// default). Used for op routing, the list host chip, and transfer targeting.
    func host(forSession id: String) -> Host? {
        guard let hid = hostBySession[id] else { return nil }
        return settings.hosts.first { $0.id == hid }
    }

    /// The client for the host that owns `id`, falling back to the default host
    /// (covers optimistic/placeholder sessions not yet in the routing table).
    func client(forSession id: String) -> LFGClient? {
        if let h = host(forSession: id), let c = settings.client(for: h) { return c }
        return settings.defaultClient
    }

    /// Whether a host is currently reachable (for default-host placement).
    private func isReachable(_ host: Host) -> Bool { reachabilityByHost[host.id] == .ok }

    /// Ask the UI to open a session (driven by a tapped push notification).
    func requestSelection(_ sid: String) { requestedSelection = sid }
    func clearRequestedSelection() { requestedSelection = nil }

    /// Route a tapped push notification to its session. A tap frequently
    /// cold-launches the app (or wakes it from suspension) with no live session
    /// list yet — the old path just set the selection and the detail view flashed
    /// "No session selected" because nothing was loaded. So we ALSO actively
    /// reconnect and resolve the session here: refresh the live list, and if the
    /// session has since closed (pane reaped), pull it from the resumable list so
    /// its transcript still opens (sending revives it via the server auto-resume).
    func openFromNotification(_ sid: String, snapshot: Session? = nil) {
        // Defer onto the next main-actor turn. A notification tap calls this from
        // *inside* UIKit's launch / CATransaction-commit while it's snapshotting
        // for state restoration; setting `requestedSelection` synchronously there
        // drives a NavigationSplitView selection change mid-transaction, and UIKit
        // throws an NSException during the snapshot (the app "opens then quits").
        // Hopping a runloop turn lets the navigation update happen in a clean
        // context — exactly like an in-app tap.
        Task { [weak self] in
            guard let self else { return }
            // Seed the detail from the push's embedded snapshot so the session
            // screen renders instantly on tap, before the reconnect + refresh.
            // `resolveDeepLink`'s refresh swaps in the authoritative live copy.
            if let snapshot, snapshot.sessionId == sid, self.session(sid) == nil {
                self.deepLinkSession = snapshot
            }
            self.requestedSelection = sid
            await self.resolveDeepLink(sid)
        }
    }

    private func resolveDeepLink(_ sid: String) async {
        await refresh()                       // reconnect + load the live list
        if session(sid) != nil { return }     // live — detail can bind immediately
        guard let client else { return }
        // Closed session: synthesize a display copy from the resumable list so the
        // detail view + transcript open; `session(_:)` returns it as a fallback.
        if let list = try? await client.resumable(limit: 80),
           let r = list.first(where: { $0.sessionId == sid }) {
            deepLinkSession = Session(
                sessionId: r.sessionId,
                title: r.title ?? "Session",
                agent: r.agent ?? "claude",
                project: r.project,
                cwd: r.cwd,
                lastActivityAt: r.mtime)
        }
    }

    var isConnected: Bool { reachability == .ok }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        for t in streamTasks.values { t.cancel() }
        streamTasks = [:]
        streamedIDsByHost = [:]
    }

    /// Called when the host list changes — wipe everything and reconnect.
    func reconnect() {
        stop()
        sessions = []; transcripts = [:]; prompts = [:]; busy = [:]; queues = [:]; seen = [:]; pendingSends = [:]
        closedCache = []; resumedIds = []; resumeTick = 0
        hostBySession = [:]; lastSessionsByHost = [:]; reachabilityByHost = [:]; failuresByHost = [:]
        reachability = nil; usage = nil; repos = []; users = []
        start()
    }

    // MARK: Polling

    /// One host's live-session fetch result (Sendable so it crosses the task
    /// group boundary).
    private struct HostFetch: Sendable {
        let host: Host
        let sessions: [Session]?
        let reach: Reachability
    }

    /// Fan out `GET /api/sessions` to every configured host in parallel, returning
    /// results in configured order (the task group completes out of order).
    private func fetchSessionsAllHosts() async -> [HostFetch] {
        let pairs: [(Host, LFGClient?)] = settings.hosts.map { ($0, settings.client(for: $0)) }
        let results = await withTaskGroup(of: HostFetch.self) { group -> [HostFetch] in
            for (h, c) in pairs {
                group.addTask {
                    guard let c else { return HostFetch(host: h, sessions: nil, reach: .badResponse("Invalid URL")) }
                    do { return HostFetch(host: h, sessions: try await c.sessions(), reach: .ok) }
                    catch let LFGError.notReachable(u) { return HostFetch(host: h, sessions: nil, reach: .hostUnreachable(u)) }
                    catch let LFGError.http(status, _) { return HostFetch(host: h, sessions: nil, reach: .badResponse("HTTP \(status)")) }
                    catch { return HostFetch(host: h, sessions: nil, reach: .badResponse("Bad response")) }
                }
            }
            var out: [HostFetch] = []
            for await r in group { out.append(r) }
            return out
        }
        let order = Dictionary(uniqueKeysWithValues: settings.hosts.enumerated().map { ($1.id, $0) })
        return results.sorted { (order[$0.host.id] ?? 0) < (order[$1.host.id] ?? 0) }
    }

    /// Fan out `GET /api/sessions/resumable` to the given (reachable) hosts, in
    /// order. Because `~/.claude/projects` is synced these lists overlap heavily —
    /// `MultiHost.reconcileResumable` dedupes + drops live ids.
    private func fetchResumableAllHosts(_ hosts: [Host]) async -> [[ResumableSession]] {
        let pairs: [(Int, LFGClient?)] = hosts.enumerated().map { ($0, settings.client(for: $1)) }
        let results = await withTaskGroup(of: (Int, [ResumableSession]).self) { group -> [(Int, [ResumableSession])] in
            for (i, c) in pairs {
                group.addTask {
                    guard let c else { return (i, []) }
                    return (i, (try? await c.resumable(limit: 60)) ?? [])
                }
            }
            var out: [(Int, [ResumableSession])] = []
            for await r in group { out.append(r) }
            return out
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }

    func refresh() async {
        guard !settings.hosts.isEmpty else {
            reachability = .badResponse("No host configured"); return
        }
        let fetched = await fetchSessionsAllHosts()

        // Per-host reachability with the transient-blip debounce, and cache each
        // host's last good snapshot so a blip doesn't drop its sessions.
        for f in fetched {
            if f.reach == .ok {
                reachabilityByHost[f.host.id] = .ok
                failuresByHost[f.host.id] = 0
                lastSessionsByHost[f.host.id] = f.sessions ?? []
            } else {
                let n = (failuresByHost[f.host.id] ?? 0) + 1
                failuresByHost[f.host.id] = n
                if reachabilityByHost[f.host.id] != .ok || n >= failureThreshold {
                    reachabilityByHost[f.host.id] = f.reach
                }
            }
        }
        // Prune state for hosts removed from settings.
        let hostIds = Set(settings.hosts.map(\.id))
        reachabilityByHost = reachabilityByHost.filter { hostIds.contains($0.key) }
        lastSessionsByHost = lastSessionsByHost.filter { hostIds.contains($0.key) }

        let anyOK = fetched.contains { $0.reach == .ok }
        reachability = anyOK ? .ok : (fetched.first { $0.reach != .ok }?.reach ?? .badResponse("No host configured"))
        lastError = nil

        // Merge each host's last-known live sessions (configured order → stable
        // list + deterministic first-wins), building the session→host routing map.
        let perHostLive = settings.hosts.map { (host: $0, sessions: lastSessionsByHost[$0.id] ?? []) }
        let merged = MultiHost.mergeSessions(perHostLive)
        let fresh = merged.sessions
        hostBySession = merged.hostBySession
        let liveIds = Set(fresh.compactMap(\.sessionId))

        // Refresh the closed/resumable set on a slower cadence (first poll, then
        // every ~12s), reconciled across hosts (dedupe synced transcripts + drop
        // anything live on any host). The cached copy is merged in every poll.
        resumeTick += 1
        if resumeTick % 4 == 1 {
            let okHosts = settings.hosts.filter { reachabilityByHost[$0.id] == .ok }
            let perHostResumable = await fetchResumableAllHosts(okHosts)
            let reconciled = MultiHost.reconcileResumable(perHost: perHostResumable, liveIds: liveIds)
            closedCache = reconciled.map(Self.closedSession(from:))
        }

        // Keep any not-yet-reconciled optimistic (placeholder-id) sessions so
        // a poll landing mid-create can't make the open session vanish.
        let optimistic = optimisticSessions.filter { o in
            guard let id = o.sessionId else { return true }
            return !liveIds.contains(id)
        }
        let optimisticIds = Set(optimistic.compactMap(\.sessionId))
        // Merge closed sessions that aren't live, optimistic, or already resumed
        // away this run, so ended sessions stay in the list.
        let closed = closedCache.filter { c in
            guard let cid = c.sessionId else { return false }
            return !liveIds.contains(cid) && !optimisticIds.contains(cid) && !resumedIds.contains(cid)
        }
        sessions = fresh + optimistic + closed
        // Seed busy from the REST baseline for sessions the live SSE stream
        // doesn't cover (outside the 24-id window). Streamed sessions keep their
        // accurate pane-scraped SSE busy as an override.
        let streamed = Set(streamedIDsByHost.values.flatMap { $0 })
        for s in fresh {
            guard let sid = s.sessionId, let b = s.busy, !streamed.contains(sid) else { continue }
            busy[sid] = b
        }
        // Snapshot the focused session while it's live so its detail view survives
        // the session later dropping out of the live list.
        if let f = focusedID, let live = fresh.first(where: { $0.sessionId == f }) {
            focusedSnapshot = live
        } else if focusedID == nil {
            focusedSnapshot = nil
        }
        // Drop the deep-link fallback once its session is live in the list.
        if let dl = deepLinkSession, fresh.contains(where: { $0.sessionId == dl.sessionId }) {
            deepLinkSession = nil
        }
        ensureStream()
        await reconcilePendingViaQueue()
    }

    /// Resolve `/api/info` for any host missing its friendly name, folding the
    /// identity back into settings (used for the host chip + dedupe).
    func resolveHostIdentities() async {
        for host in settings.hosts where (host.name ?? "").isEmpty {
            guard let client = settings.client(for: host) else { continue }
            if let info = try? await client.info() {
                settings.updateHostInfo(host.id, info: info)
            }
        }
    }

    func loadCreateMetadata() async {
        guard let client else { return }
        async let d = try? client.dirs()
        async let u = try? client.users()
        async let g = try? client.usage()
        if let dirs = await d {
            repos = dirs.repos; root = dirs.root; inbox = dirs.inbox
        }
        users = (await u) ?? []
        usage = await g
    }

    func createDirectory(_ name: String) async -> Repo? {
        guard let client else { return nil }
        do {
            let dir = try await client.createDir(name: name)
            await loadCreateMetadata()
            return dir
        } catch {
            lastError = "Create directory failed: \(error.localizedDescription)"
            return nil
        }
    }

    func setInbox(_ path: String) async {
        guard let client else { return }
        if let updated = try? await client.setInbox(path: path) { inbox = updated }
    }

    // MARK: Live stream

    /// Pin the currently-open session so it always receives live events.
    func focus(_ id: String?) {
        if let id { markOpened(id) }
        guard focusedID != id else { return }
        focusedID = id
        ensureStream()
    }

    /// Stamp a session as seen "now" (epoch ms) and persist. Called when the
    /// session is opened and as it streams while on screen, so it clears from the
    /// "Unread" group. No-op for local placeholder ids (not real sessions yet).
    private func markOpened(_ id: String) {
        guard !id.hasPrefix("local-") else { return }
        lastOpenedAt[id] = Date().timeIntervalSince1970 * 1000
        UserDefaults.standard.set(lastOpenedAt, forKey: Self.lastOpenedKey)
    }

    /// Maintain one live SSE stream PER host (each host serves its own
    /// `/api/live/stream` with its own 24-id cap). Within a host, prioritise the
    /// focused session, then most-recently-active, so the viewed + running
    /// sessions always get live events.
    private func ensureStream() {
        let hosts = settings.hosts
        let hostIds = Set(hosts.map(\.id))
        // Tear down streams for hosts removed from settings.
        for hid in Array(streamTasks.keys) where !hostIds.contains(hid) {
            streamTasks[hid]?.cancel(); streamTasks[hid] = nil; streamedIDsByHost[hid] = nil
        }
        for host in hosts {
            var ordered = sessions
                .filter { !$0.closed && hostBySession[$0.id] == host.id }
                .sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }
                .compactMap(\.sessionId)
                .filter { !$0.hasPrefix("local-") }   // placeholders aren't on the server yet
            if let f = focusedID, !f.hasPrefix("local-"), hostBySession[f] == host.id {
                ordered.removeAll { $0 == f }
                ordered.insert(f, at: 0)
            }
            let capped = Array(ordered.prefix(24))
            let key = capped.sorted()
            if key == (streamedIDsByHost[host.id] ?? []) { continue }   // unchanged
            streamedIDsByHost[host.id] = key
            streamTasks[host.id]?.cancel()
            guard let client = settings.client(for: host), !capped.isEmpty else {
                streamTasks[host.id] = nil; continue
            }
            let hid = host.id
            streamTasks[hid] = Task { [weak self] in
                do {
                    for try await event in client.liveStream(ids: capped) {
                        if Task.isCancelled { return }
                        self?.apply(event)
                    }
                } catch {
                    // Thrown error (network blip). Fall through to the reset below.
                }
                // A clean close (server restart / idle EOF / proxy close) completes
                // the for-await loop WITHOUT throwing; without resetting this host's
                // streamedIDs, ensureStream would believe the stream is still live
                // and never reconnect (live updates silently stop). Reset so the 3s
                // poll re-establishes it — unless superseded (cancelled) by a newer
                // ensureStream, which already set the correct ids for its stream.
                if !Task.isCancelled { self?.streamedIDsByHost[hid] = [] }
            }
        }
    }

    private func apply(_ event: LiveEvent) {
        switch event {
        case .message(let sid, let m):
            var set = seen[sid] ?? []
            let key = m.stableID
            if set.contains(key) { return }
            set.insert(key); seen[sid] = set
            transcripts[sid, default: []].append(m)
            // Keep the session on screen marked read as its output streams in, so
            // a turn that completes while you're watching doesn't resurface it as
            // unread when you leave the detail view.
            if sid == focusedID { markOpened(sid) }
            // A real user turn just landed — drop any optimistic bubble it fulfils.
            if m.role == "user" { reconcilePending(sid) }
        case .prompt(let sid, let prompt):
            if let prompt { prompts[sid] = prompt } else { prompts[sid] = nil }
        case .busy(let sid, let value):
            busy[sid] = value
        case .queue(let sid, let q):
            queues[sid] = q
            correlatePending(sid, q)
        case .heartbeat:
            break
        }
    }

    // MARK: Derived view state

    enum Group: Int, CaseIterable {
        case needsInput, blocked, working, unread, idle, closed
        var title: String {
            switch self {
            case .needsInput: return "Needs you"
            case .blocked: return "Paused"
            case .working: return "Working"
            case .unread: return "Unread"
            case .idle: return "Idle"
            case .closed: return "Closed"
            }
        }
    }

    func group(for s: Session) -> Group {
        if s.closed { return .closed }
        if let sid = s.sessionId, prompts[sid] != nil { return .needsInput }
        if s.isBlocked { return .blocked }
        if let sid = s.sessionId, busy[sid] == true { return .working }
        // Completed (idle) but with output newer than the last time this device
        // opened it → "Unread". The session on screen is excluded (you're reading
        // it right now, even before its stream stamps it read).
        if let sid = s.sessionId, sid != focusedID,
           ReadState.isUnread(lastActivityAt: s.lastActivityAt, lastOpenedAt: lastOpenedAt[sid]) {
            return .unread
        }
        return .idle
    }

    var filteredSessions: [Session] {
        sessions.filter { settings.userFilter.matches($0) }
    }

    /// Number of sessions currently working (busy) — shown in the top bar.
    var runningCount: Int {
        sessions.filter { group(for: $0) == .working }.count
    }

    func grouped() -> [(Group, [Session])] {
        let visible = filteredSessions
        return Group.allCases.compactMap { g in
            let items = visible.filter { group(for: $0) == g }
                .sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }
            return items.isEmpty ? nil : (g, items)
        }
    }

    /// Last live copy of the focused session, retained so its detail view +
    /// composer survive the session dropping out of the live list (its pane was
    /// reaped while idle — box reboot, host restart). Without this the detail
    /// snaps to "No session selected" the instant the session closes and the
    /// user can't send. A send to this carried-forward session auto-resumes the
    /// conversation server-side and the next refresh replaces it with the live
    /// copy. Not added to `sessions`, so it never shows as a stale list card.
    private var focusedSnapshot: Session?

    /// See `openFromNotification`: a closed session a notification deep-linked to,
    /// resolved from the resumable list so its detail view can still open.
    private var deepLinkSession: Session?

    func session(_ id: String) -> Session? {
        if let s = sessions.first(where: { $0.sessionId == id }) { return s }
        if id == focusedID, let snap = focusedSnapshot, snap.sessionId == id { return snap }
        if let dl = deepLinkSession, dl.sessionId == id { return dl }
        return nil
    }

    // MARK: Steering actions (optimistic where useful, then refresh)

    private var historyTasks: [String: Task<Void, Never>] = [:]

    /// Kick off a full-history load in a *store-owned* task so it runs to
    /// completion even if the detail view churns or the user navigates away
    /// mid-load (a view-bound `.task` would cancel the in-flight request,
    /// leaving only the live-stream backfill — i.e. "only a few messages").
    func loadHistory(_ id: String) {
        // Placeholder sessions have no server-side transcript yet — skip the
        // fetch (it would 404) until the create reconciles to a real id.
        guard !id.isEmpty, !id.hasPrefix("local-"), historyTasks[id] == nil else { return }
        historyTasks[id] = Task { [weak self] in
            await self?.ensureHistory(id)
            self?.historyTasks[id] = nil
        }
    }

    /// Load the session's full transcript and merge it with anything the live
    /// stream already delivered (deduped by stable id, sorted by timestamp).
    /// Loads the whole history — not just a recent window — so the user's own
    /// prompts show even in long, tool-heavy sessions where they'd otherwise be
    /// older than the live-stream backfill window.
    func ensureHistory(_ id: String) async {
        guard let client = client(forSession: id) else { return }
        guard let msgs = try? await client.messages(id, limit: 5000, full: true) else { return }
        var byKey: [String: SessionMessage] = [:]
        for m in (transcripts[id] ?? []) { byKey[m.stableID] = m }
        for m in msgs { byKey[m.stableID] = m }
        transcripts[id] = byKey.values.sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
        seen[id] = Set(byKey.keys)
        reconcilePending(id)
    }

    // MARK: Optimistic sends

    /// Build a display `Session` for a closed/resumable transcript. `closed` marks
    /// it so `group(for:)` files it under "Closed" and the send path treats a
    /// message to it as a wake-up (server auto-resumes on send).
    private static func closedSession(from r: ResumableSession) -> Session {
        Session(
            sessionId: r.sessionId,
            title: (r.title?.isEmpty == false ? r.title! : "Session"),
            agent: r.agent ?? "claude",
            project: r.project,
            cwd: r.cwd,
            lastUserText: r.lastUserText,
            lastActivityAt: r.mtime,
            closed: true)
    }

    /// Normalize text for fuzzy matching an optimistic send against the user turn
    /// the agent eventually records (whitespace/case differences, wrapping).
    private static func normMatch(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Remove optimistic bubbles whose text now appears as a real user turn in the
    /// transcript — the live message took over, so the placeholder is done.
    private func reconcilePending(_ sid: String) {
        guard let pend = pendingSends[sid], !pend.isEmpty else { return }
        let userTurns = (transcripts[sid] ?? [])
            .filter { $0.role == "user" && $0.kind == "text" }
            .map { Self.normMatch($0.text) }
        let remaining = pend.filter { p in
            let needle = Self.normMatch(p.matchText)
            guard needle.count >= 3 else { return true }
            let key = String(needle.prefix(80))
            return !userTurns.contains { $0.contains(key) }
        }
        if remaining.count != pend.count { pendingSends[sid] = remaining }
    }

    /// Drive optimistic bubbles off the server's authoritative outbound-queue
    /// status — more reliable than re-matching transcript text on the client
    /// (which can miss when the recorded turn is reformatted/wrapped). The server
    /// marks an item `delivered` once it has surfaced as a real user turn in the
    /// transcript, so on `delivered` we drop the placeholder and let that real
    /// bubble take over; `failed` surfaces a Retry; anything else is still in
    /// flight, so keep showing the muted bar.
    private func correlatePending(_ sid: String, _ q: [QueueItem]) {
        guard let pend = pendingSends[sid], !pend.isEmpty else { return }
        let remaining: [PendingSend] = pend.compactMap { p in
            let needle = Self.normMatch(p.matchText)
            guard needle.count >= 3 else { return p }
            let key = String(needle.prefix(60))
            guard let item = q.first(where: { Self.normMatch($0.text).contains(key) }) else {
                // We linked this to a queue item earlier and it's now gone. The
                // server only prunes items after a terminal state (delivered /
                // failed), so a vanished item means it's done — drop the bar.
                return p.serverQueueID != nil ? nil : p
            }
            if item.status == "delivered" { return nil }   // surfaced as a real user turn
            var p2 = p
            p2.serverQueueID = item.id
            p2.failed = item.isFailed
            return p2
        }
        if remaining != pend { pendingSends[sid] = remaining }
    }

    /// Poll-based safety net (runs on the 3s refresh): for any session with
    /// outstanding optimistic sends, fetch its queue directly and reconcile.
    /// Catches deliveries even when the live `queue` event was missed (stream
    /// stalled/reconnecting), so a pending bar can't get stuck after the agent
    /// has actually picked the message up. Also refreshes the transcript for a
    /// session whose pending just cleared, so the real user bubble is present.
    private func reconcilePendingViaQueue() async {
        let sids = Array(pendingSends.keys)
        for sid in sids {
            guard pendingSends[sid]?.isEmpty == false else { continue }
            guard let client = client(forSession: sid) else { continue }
            guard let q = try? await client.queue(sid) else { continue }
            queues[sid] = q
            let had = pendingSends[sid]?.count ?? 0
            correlatePending(sid, q)
            if (pendingSends[sid]?.count ?? 0) < had { loadHistory(sid) }
        }
    }

    private func mutatePending(_ sid: String, _ pid: String, _ body: (inout PendingSend) -> Void) {
        guard var pend = pendingSends[sid], let i = pend.firstIndex(where: { $0.id == pid }) else { return }
        body(&pend[i]); pendingSends[sid] = pend
    }

    private func removePending(_ sid: String, _ pid: String) {
        pendingSends[sid]?.removeAll { $0.id == pid }
    }

    /// Show a just-started (or resumed) session's kickoff prompt optimistically —
    /// the same pending → user-bubble handoff as an in-session send — so the first
    /// message appears as the user's message right away instead of only once the
    /// agent records it. The session is created with this text as its prompt, so
    /// the real user turn lands shortly and reconciles the placeholder away.
    func addPending(_ sid: String, text: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let nowMs = Date().timeIntervalSince1970 * 1000
        pendingSends[sid, default: []].append(
            PendingSend(id: UUID().uuidString, displayText: typed, matchText: typed, ts: nowMs, showSent: true))
        reconcilePending(sid)
    }

    /// Resend a failed optimistic message. If we know its server queue id, retry
    /// that queued entry; otherwise (the original HTTP send never landed) resend.
    func retryPending(_ sid: String, _ pending: PendingSend) async {
        // A placeholder whose session never got created: re-attempt the create,
        // not a send (there's no session on the server to send to yet).
        if let req = pendingCreates[sid] {
            mutatePending(sid, pending.id) { $0.failed = false }
            busy[sid] = true
            await attemptCreate(sid, req, on: pendingCreateHost[sid], attachments: [])
            return
        }
        mutatePending(sid, pending.id) { $0.failed = false }
        if let qid = pending.serverQueueID {
            await retry(sid, qid)
        } else if let client = client(forSession: sid) {
            do {
                let resp = try await client.sendMessage(sid, text: pending.matchText)
                applyResume(from: sid, resp)
                let eff = (resp.resumed == true ? resp.sessionId : nil) ?? sid
                mutatePending(eff, pending.id) { $0.confirmed = true }
                await refresh(); reconcilePending(eff)
            } catch { mutatePending(sid, pending.id) { $0.failed = true } }
        }
    }

    /// Run a per-session steering op against the host that OWNS the session, then
    /// refresh. Routing through `client(forSession:)` is what makes every action
    /// (send/close/interrupt/…) hit the right machine in a multi-host setup.
    @discardableResult
    func run(_ label: String, for id: String, _ op: @escaping (LFGClient) async throws -> Void) async -> Bool {
        guard let client = client(forSession: id) else { return false }
        do { try await op(client); await refresh(); return true }
        catch { lastError = "\(label) failed: \(error.localizedDescription)"; return false }
    }

    /// If a send auto-resumed a session whose pane had been reaped (the server
    /// revived it and may have handed back a new id), re-point all per-session
    /// keyed state at the new id. No-op in the common case — the resumed id is
    /// almost always identical, and a normal live send sets `resumed` nil.
    private func applyResume(from old: String, _ resp: SendResponse) {
        guard resp.resumed == true, let new = resp.sessionId, !new.isEmpty, new != old else { return }
        // Carry the just-resumed session forward under its new live id so the open
        // detail doesn't blank out during the 1–6s the revived pane takes to
        // appear in the live list. Cleared on the next refresh once it's live.
        if var carried = session(old) {
            carried.sessionId = new
            carried.closed = false
            deepLinkSession = carried
        }
        remap(from: old, to: new)
        requestSelection(new)   // move the open detail from the closed id to the live one
    }

    func send(_ id: String, _ text: String) async {
        guard let client = client(forSession: id) else { return }
        do {
            let resp = try await client.sendMessage(id, text: text)
            applyResume(from: id, resp)
            await refresh()
        } catch { lastError = "Send failed: \(error.localizedDescription)" }
    }

    // Sends in flight, keyed so the store retains them. A send must outlive the
    // view that started it: leaving the session view, popping the nav stack, or
    // backgrounding the app must NOT drop the message mid-delivery.
    private var inflightSends: [UUID: Task<Void, Never>] = [:]

    /// Fire a send that is owned by the store (app-lifetime), not the calling
    /// view. The work is retained in `inflightSends` so leaving the session view
    /// or popping the nav stack can't cancel it. Crucially, the background-task
    /// assertion is taken SYNCHRONOUSLY here — before this returns and before the
    /// app can be suspended — so pressing Home the instant after tapping send
    /// still grants the in-flight POST a grace period to finish. (Taking it
    /// inside the async Task would race the suspension and lose the message.)
    func dispatchSend(_ id: String, text: String, attachments: [ComposerAttachment]) {
        let app = UIApplication.shared
        var bg: UIBackgroundTaskIdentifier = .invalid
        bg = app.beginBackgroundTask(withName: "lfg.send") {
            if bg != .invalid { app.endBackgroundTask(bg); bg = .invalid }
        }
        let key = UUID()
        inflightSends[key] = Task { [weak self] in
            await self?.sendWithAttachments(id, text: text, attachments: attachments)
            self?.inflightSends[key] = nil
            if bg != .invalid { app.endBackgroundTask(bg); bg = .invalid }
        }
    }

    /// Upload any image attachments, then send the text with their paths appended
    /// (Claude Code reads local image paths as image input). The message shows as
    /// an optimistic user bubble immediately — before uploads or the network
    /// round-trip — and is reconciled away once the agent records the real turn.
    func sendWithAttachments(_ id: String, text: String, attachments: [ComposerAttachment]) async {
        guard let client = client(forSession: id) else { return }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !attachments.isEmpty else { return }

        // 1) Show the bubble right now, before any await. When the session is
        //    idle (not busy, no open prompt) the agent picks the message up
        //    immediately, so there's nothing to wait for — render it as a
        //    finished user bubble (showSent) instead of a "Sending…" bar that
        //    would just flicker. A busy session genuinely queues the message
        //    behind the running turn, so there we keep the pending bar.
        let idle = prompts[id] == nil && busy[id] != true
        // A wake-up send: the target isn't in the live list — it's a closed
        // session whose detail we're carrying forward, either because its pane
        // was reaped while focused (`focusedSnapshot`) or it was opened straight
        // from a tapped push notification (`deepLinkSession`). Either way this
        // message has to resume the conversation server-side first (a real
        // round-trip), so show it as a bubble (showSent) but unconfirmed/muted
        // until the send returns, rather than instantly-blue as if received.
        // A closed session shown in the list is also a wake-up: the send resumes
        // it server-side (a real round-trip) before it's live.
        let isClosed = session(id)?.closed == true
        let isWakeUp = isClosed
            || (!sessions.contains { $0.sessionId == id }
                && (focusedSnapshot?.sessionId == id || deepLinkSession?.sessionId == id))
        let pid = UUID().uuidString
        let nowMs = Date().timeIntervalSince1970 * 1000
        pendingSends[id, default: []].append(
            PendingSend(id: pid,
                        displayText: typed.isEmpty ? "📎 Attachment" : typed,
                        matchText: typed,
                        ts: nowMs,
                        showSent: idle || isWakeUp,
                        confirmed: !isWakeUp))

        // 2) Upload attachments, then assemble the full text the agent will record.
        var paths: [String] = []
        for att in attachments {
            if let p = try? await client.upload(id, data: att.data, contentType: "image/png") { paths.append(p) }
        }
        let full = ([typed] + paths).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !full.isEmpty else { removePending(id, pid); return }
        mutatePending(id, pid) { $0.matchText = full }

        // 3) Send. On failure mark the bubble failed (Retry); on success let the
        //    queue/transcript reconcile it.
        do {
            let resp = try await client.sendMessage(id, text: full)
            applyResume(from: id, resp)
            let eff = (resp.resumed == true ? resp.sessionId : nil) ?? id
            // The backend accepted it (and, for a wake-up, finished resuming) —
            // flip the muted bubble to its confirmed accent color before the
            // refresh, then let reconcile hand it off to the real user turn.
            mutatePending(eff, pid) {
                $0.confirmed = true
                // Link to the server queue id right away so the message can be
                // removed / edited / sent-now while it's still pending.
                if let qid = resp.msg?.id { $0.serverQueueID = qid }
            }
            await refresh()
            reconcilePending(eff)
        } catch {
            lastError = "Send failed: \(error.localizedDescription)"
            mutatePending(id, pid) { $0.failed = true }
        }
    }

    // MARK: Queued-message actions (hold-in-lfg)

    /// Remove a still-pending queued message so it never runs. Drops the server
    /// queue entry (held in lfg's queue, so this is clean) and the local bubble.
    func removeQueued(_ sid: String, _ pending: PendingSend) async {
        if let qid = pending.serverQueueID {
            await run("Remove", for: sid) { try await $0.removeQueued(sid, qid) }
        }
        removePending(sid, pending.id)
    }

    /// Pull a queued message back to edit: remove it server-side + locally and
    /// return its text so the caller can repopulate the composer.
    @discardableResult
    func editQueued(_ sid: String, _ pending: PendingSend) async -> String {
        if let qid = pending.serverQueueID {
            await run("Edit", for: sid) { try await $0.removeQueued(sid, qid) }
        }
        removePending(sid, pending.id)
        return pending.displayText
    }

    /// Interrupt the current turn and deliver this queued message immediately.
    func sendQueuedNow(_ sid: String, _ pending: PendingSend) async {
        guard let qid = pending.serverQueueID else { return }
        await run("Send now", for: sid) { try await $0.sendQueuedNow(sid, qid) }
    }
    func answer(_ id: String, _ index: Int) async { await run("Answer", for: id) { try await $0.answer(id, index: index) } }
    func dismissPrompt(_ id: String) async { await run("Dismiss", for: id) { try await $0.dismiss(id) } }
    func interrupt(_ id: String) async { await run("Stop", for: id) { try await $0.interrupt(id) } }
    func setModel(_ id: String, _ model: String) async { await run("Switch model", for: id) { try await $0.setModel(id, model: model) } }
    func rename(_ id: String, _ title: String) async { await run("Rename", for: id) { try await $0.rename(id, title: title) } }
    func assign(_ id: String, _ user: String?) async { await run("Assign", for: id) { try await $0.assign(id, user: user) } }
    func close(_ id: String) async { await run("End session", for: id) { try await $0.close(id) } }
    func retry(_ id: String, _ messageID: String) async { await run("Retry", for: id) { try await $0.retryQueued(id, messageID: messageID) } }

    /// Create a session on a specific host (defaults to the default host). The
    /// chosen host is where the agent's pane spawns.
    func create(_ req: NewSessionRequest, on host: Host? = nil) async -> String? {
        let client = host.flatMap { settings.client(for: $0) } ?? settings.defaultClient
        guard let client else { return nil }
        do {
            let resp = try await client.newSession(req)
            await refresh()
            return resp.sessionId
        } catch { lastError = "Create failed: \(error.localizedDescription)"; return nil }
    }

    /// Create a session optimistically: synthesize a placeholder session plus its
    /// kickoff bubble and return a temporary id so the UI can navigate to it the
    /// instant the user hits send, then fire `POST /new` in the background and
    /// reconcile the placeholder id to the server's once it lands. This is the
    /// session-level twin of an optimistic in-session send — the kickoff message
    /// shows as a finished user bubble right away instead of waiting on the
    /// create round-trip.
    @discardableResult
    func startOptimistic(_ req: NewSessionRequest, on host: Host? = nil, attachments: [ComposerAttachment] = []) -> String {
        let placeholder = "local-" + UUID().uuidString
        let nowMs = Date().timeIntervalSince1970 * 1000
        let typed = req.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = typed.split(whereSeparator: \.isNewline).first.map(String.init) ?? "New session"
        let optimistic = Session(
            sessionId: placeholder,
            title: String(firstLine.prefix(60)),
            agent: req.agent ?? "aisdk",
            model: req.model,
            cwd: req.cwd,
            status: "ok",
            assignedUser: req.user,
            lastUserText: typed,
            startedAt: nowMs,
            lastActivityAt: nowMs)
        optimisticSessions.append(optimistic)
        sessions.append(optimistic)
        pendingCreates[placeholder] = req
        pendingCreateHost[placeholder] = host
        // Route any early op on the placeholder to the chosen host (until refresh
        // maps the real id).
        if let host { hostBySession[placeholder] = host.id }
        busy[placeholder] = true            // the agent is spinning up on this prompt
        addPending(placeholder, text: typed)   // finished (showSent) kickoff bubble
        Task { await attemptCreate(placeholder, req, on: host, attachments: attachments) }
        return placeholder
    }

    /// Run the real create for a placeholder, then remap all of its state to the
    /// server-assigned id and point navigation at it. On failure, surface the
    /// kickoff bubble's Retry (which re-enters here).
    private func attemptCreate(_ placeholder: String, _ req: NewSessionRequest, on host: Host?, attachments: [ComposerAttachment]) async {
        let client = host.flatMap { settings.client(for: $0) } ?? settings.defaultClient
        guard let client else { return }
        do {
            let resp = try await client.newSession(req)
            guard let realId = resp.sessionId else {
                throw LFGError.http(status: 0, body: "Create returned no session id")
            }
            pendingCreates[placeholder] = nil
            pendingCreateHost[placeholder] = nil
            remap(from: placeholder, to: realId)
            requestSelection(realId)        // swap the open detail from placeholder → real
            await refresh()
            if !attachments.isEmpty {
                await sendWithAttachments(realId, text: "", attachments: attachments)
            }
        } catch {
            lastError = "Create failed: \(error.localizedDescription)"
            busy[placeholder] = false
            if var pend = pendingSends[placeholder] {
                for i in pend.indices { pend[i].failed = true }
                pendingSends[placeholder] = pend
            }
        }
    }

    /// Move every per-session keyed value from a placeholder id to the
    /// server-assigned id once an optimistic create lands, then drop the
    /// placeholder session so only the real one remains.
    private func remap(from old: String, to new: String) {
        // A resumed closed session's old transcript lingers on disk; remember it
        // so the merge in `refresh` doesn't re-add it as a stale "Closed" card.
        resumedIds.insert(old)
        if let v = transcripts.removeValue(forKey: old) { transcripts[new] = v }
        if let v = prompts.removeValue(forKey: old) { prompts[new] = v }
        if let v = busy.removeValue(forKey: old) { busy[new] = v }
        if let v = queues.removeValue(forKey: old) { queues[new] = v }
        if let v = pendingSends.removeValue(forKey: old) {
            pendingSends[new, default: []].insert(contentsOf: v, at: 0)
        }
        if let v = seen.removeValue(forKey: old) { seen[new] = v }
        optimisticSessions.removeAll { $0.sessionId == old }
        // Rename the session in place (rather than removing it) so it stays
        // visible under the new id with no "no session selected" flash before
        // the authoritative copy arrives on the next refresh.
        if let i = sessions.firstIndex(where: { $0.sessionId == old }) {
            sessions[i].sessionId = new
            sessions[i].closed = false   // it's reviving — no longer a closed card
        }
        if focusedID == old { focus(new) }
    }

    /// Resume a closed session. Defaults to the default host; pass `on:` to revive
    /// the (synced) transcript on a specific machine — the basis of transfer.
    func resume(_ req: ResumeRequest, on host: Host? = nil) async -> String? {
        let client = host.flatMap { settings.client(for: $0) } ?? settings.defaultClient
        guard let client else { return nil }
        do {
            let resp = try await client.resume(req)
            await refresh()
            return resp.sessionId
        } catch { lastError = "Resume failed: \(error.localizedDescription)"; return nil }
    }

    /// Fork a session into a new branch and return the new session's id (nil on
    /// failure). The source is untouched; the caller focuses the returned id so
    /// the detail view deep-links straight into the fork. Routed to the source
    /// session's host.
    func fork(_ req: ForkRequest) async -> String? {
        guard let client = client(forSession: req.sessionId) else { return nil }
        do {
            let resp = try await client.fork(req)
            await refresh()
            return resp.sessionId
        } catch { lastError = "Fork failed: \(error.localizedDescription)"; return nil }
    }

    /// Transfer a live session to another host: stop its pane on the SOURCE host,
    /// then resume the (synced) transcript on the TARGET host, and point routing +
    /// navigation at the new live id. Returns the new sessionId, or nil on failure
    /// (the source close having already happened — the session is then resumable
    /// on the target and can be retried). See `.claude/brainstorm/multi-host-plan.md`.
    @discardableResult
    func transfer(_ id: String, to target: Host) async -> String? {
        guard let source = host(forSession: id) else {
            lastError = "Transfer: unknown source host for session"; return nil
        }
        guard source.id != target.id else { return id }   // already there
        guard let sourceClient = settings.client(for: source),
              let targetClient = settings.client(for: target) else {
            lastError = "Transfer: invalid host"; return nil
        }
        // 1) Stop the live pane on the source. The transcript survives (synced).
        do { try await sourceClient.close(id) }
        catch {
            lastError = "Transfer: closing on \(source.label) failed: \(error.localizedDescription)"
            return nil
        }
        // 1b) Give the source a moment to reap the pane before resuming.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(400))
            let stillLive = (try? await sourceClient.sessions())?.contains { $0.sessionId == id } ?? false
            if !stillLive { break }
        }
        // 2) Resume on the target. The server's resume dedupes against live
        //    sessions ("already running → don't double-spawn"); right after the
        //    close, the target can still observe the just-closed process while it
        //    finishes dying, so resume comes back `alreadyLive` WITHOUT spawning —
        //    and the session would end up dead, not transferred. Retry until the
        //    source is fully gone and resume actually revives a pane. Claude
        //    resumes off the copied history; re-point routing + selection at it.
        do {
            var resp = try await targetClient.resume(ResumeRequest(sessionId: id))
            var attempts = 0
            while resp.alreadyLive == true && attempts < 10 {
                try? await Task.sleep(for: .milliseconds(700))
                resp = try await targetClient.resume(ResumeRequest(sessionId: id))
                attempts += 1
            }
            if resp.alreadyLive == true {
                lastError = "Transfer: \(target.label) couldn't take over — source still busy. Try again."
                return nil
            }
            let newId = resp.sessionId ?? id
            if newId != id { remap(from: id, to: newId) }
            hostBySession[newId] = target.id
            await refresh()
            requestSelection(newId)
            return newId
        } catch {
            lastError = "Transfer: resuming on \(target.label) failed: \(error.localizedDescription)"
            return nil
        }
    }
}
