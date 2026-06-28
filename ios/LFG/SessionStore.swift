import SwiftUI
import LFGCore

/// The single source of truth for live session state. Reduces `GET /api/sessions`
/// snapshots plus the `/api/live/stream` SSE deltas (msg/prompt/busy/queue) into
/// observable per-session state the views render.
@MainActor @Observable final class SessionStore {
    let settings: AppSettings

    private(set) var sessions: [Session] = []
    private(set) var reachability: Reachability?
    var lastError: String?

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
    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var streamedIDs: [String] = []
    private var focusedID: String?

    init(settings: AppSettings) { self.settings = settings }

    var client: LFGClient? { settings.client }

    /// Ask the UI to open a session (driven by a tapped push notification).
    func requestSelection(_ sid: String) { requestedSelection = sid }
    func clearRequestedSelection() { requestedSelection = nil }

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
        streamTask?.cancel(); streamTask = nil
        streamedIDs = []
    }

    /// Called when the user changes the host — wipe everything and reconnect.
    func reconnect() {
        stop()
        sessions = []; transcripts = [:]; prompts = [:]; busy = [:]; queues = [:]; seen = [:]; pendingSends = [:]
        reachability = nil; usage = nil; repos = []; users = []
        start()
    }

    // MARK: Polling

    func refresh() async {
        guard let client else { reachability = .badResponse("No host configured"); return }
        do {
            let fresh = try await client.sessions()
            // Keep any not-yet-reconciled optimistic (placeholder-id) sessions so
            // a poll landing mid-create can't make the open session vanish.
            sessions = fresh + optimisticSessions.filter { o in
                !fresh.contains { $0.sessionId == o.sessionId }
            }
            reachability = .ok
            lastError = nil
            ensureStream()
            await reconcilePendingViaQueue()
        } catch let LFGError.notReachable(u) {
            reachability = .hostUnreachable(u)
        } catch let LFGError.http(status, _) {
            reachability = .badResponse("HTTP \(status)")
        } catch {
            reachability = .badResponse(error.localizedDescription)
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
        guard focusedID != id else { return }
        focusedID = id
        ensureStream()
    }

    private func ensureStream() {
        // Prioritise the focused (open) session, then the most-recently-active
        // ones, so the session being viewed and any running sessions always get
        // live events even past the server's 24-id cap.
        var ordered = sessions
            .sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }
            .compactMap(\.sessionId)
            .filter { !$0.hasPrefix("local-") }   // placeholders aren't on the server yet
        if let f = focusedID, !f.hasPrefix("local-") {
            ordered.removeAll { $0 == f }
            ordered.insert(f, at: 0)
        }
        let capped = Array(ordered.prefix(24))
        let key = capped.sorted()
        guard key != streamedIDs else { return }   // no change → keep current stream
        streamedIDs = key
        streamTask?.cancel()
        guard let client, !capped.isEmpty else { streamTask = nil; return }
        streamTask = Task { [weak self] in
            do {
                for try await event in client.liveStream(ids: capped) {
                    if Task.isCancelled { return }
                    self?.apply(event)
                }
            } catch {
                // Thrown error (network blip). Fall through to the reconnect reset.
            }
            // The stream ended — either it threw, or (crucially) the server
            // closed the connection cleanly (server restart, idle timeout, a
            // proxy/Tailscale close that yields EOF, not an error). In the clean
            // case the for-await loop just *completes*, so without this the
            // `catch` never runs and `streamedIDs` stays populated — ensureStream
            // then believes the stream is still live and never reconnects, so
            // live updates silently stop until the session set changes or the app
            // restarts (the user sees new messages only after leaving and
            // re-opening a session, which refetches over HTTP). Reset streamedIDs
            // so the 3s poll re-establishes the stream — unless this task was
            // superseded by a newer ensureStream (cancelled), which already set
            // the correct streamedIDs for the replacement stream.
            if !Task.isCancelled { self?.streamedIDs = [] }
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
        case needsInput, blocked, working, idle
        var title: String {
            switch self {
            case .needsInput: return "Needs you"
            case .blocked: return "Paused"
            case .working: return "Working"
            case .idle: return "Idle"
            }
        }
    }

    func group(for s: Session) -> Group {
        if let sid = s.sessionId, prompts[sid] != nil { return .needsInput }
        if s.isBlocked { return .blocked }
        if let sid = s.sessionId, busy[sid] == true { return .working }
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

    func session(_ id: String) -> Session? { sessions.first { $0.sessionId == id } }

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
        guard let client else { return }
        guard let msgs = try? await client.messages(id, limit: 5000, full: true) else { return }
        var byKey: [String: SessionMessage] = [:]
        for m in (transcripts[id] ?? []) { byKey[m.stableID] = m }
        for m in msgs { byKey[m.stableID] = m }
        transcripts[id] = byKey.values.sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
        seen[id] = Set(byKey.keys)
        reconcilePending(id)
    }

    // MARK: Optimistic sends

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
        guard let client else { return }
        let sids = Array(pendingSends.keys)
        for sid in sids {
            guard pendingSends[sid]?.isEmpty == false else { continue }
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
            await attemptCreate(sid, req, attachments: [])
            return
        }
        mutatePending(sid, pending.id) { $0.failed = false }
        if let qid = pending.serverQueueID {
            await retry(sid, qid)
        } else if let client {
            do { try await client.sendMessage(sid, text: pending.matchText); await refresh(); reconcilePending(sid) }
            catch { mutatePending(sid, pending.id) { $0.failed = true } }
        }
    }

    @discardableResult
    func run(_ label: String, _ op: @escaping (LFGClient) async throws -> Void) async -> Bool {
        guard let client else { return false }
        do { try await op(client); await refresh(); return true }
        catch { lastError = "\(label) failed: \(error.localizedDescription)"; return false }
    }

    func send(_ id: String, _ text: String) async { await run("Send") { try await $0.sendMessage(id, text: text) } }

    /// Upload any image attachments, then send the text with their paths appended
    /// (Claude Code reads local image paths as image input). The message shows as
    /// an optimistic user bubble immediately — before uploads or the network
    /// round-trip — and is reconciled away once the agent records the real turn.
    func sendWithAttachments(_ id: String, text: String, attachments: [ComposerAttachment]) async {
        guard let client else { return }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !attachments.isEmpty else { return }

        // 1) Show the bubble right now, before any await. When the session is
        //    idle (not busy, no open prompt) the agent picks the message up
        //    immediately, so there's nothing to wait for — render it as a
        //    finished user bubble (showSent) instead of a "Sending…" bar that
        //    would just flicker. A busy session genuinely queues the message
        //    behind the running turn, so there we keep the pending bar.
        let idle = prompts[id] == nil && busy[id] != true
        let pid = UUID().uuidString
        let nowMs = Date().timeIntervalSince1970 * 1000
        pendingSends[id, default: []].append(
            PendingSend(id: pid,
                        displayText: typed.isEmpty ? "📎 Attachment" : typed,
                        matchText: typed,
                        ts: nowMs,
                        showSent: idle))

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
            try await client.sendMessage(id, text: full)
            await refresh()
            reconcilePending(id)
        } catch {
            lastError = "Send failed: \(error.localizedDescription)"
            mutatePending(id, pid) { $0.failed = true }
        }
    }
    func answer(_ id: String, _ index: Int) async { await run("Answer") { try await $0.answer(id, index: index) } }
    func dismissPrompt(_ id: String) async { await run("Dismiss") { try await $0.dismiss(id) } }
    func interrupt(_ id: String) async { await run("Stop") { try await $0.interrupt(id) } }
    func setModel(_ id: String, _ model: String) async { await run("Switch model") { try await $0.setModel(id, model: model) } }
    func rename(_ id: String, _ title: String) async { await run("Rename") { try await $0.rename(id, title: title) } }
    func assign(_ id: String, _ user: String?) async { await run("Assign") { try await $0.assign(id, user: user) } }
    func close(_ id: String) async { await run("End session") { try await $0.close(id) } }
    func retry(_ id: String, _ messageID: String) async { await run("Retry") { try await $0.retryQueued(id, messageID: messageID) } }

    func create(_ req: NewSessionRequest) async -> String? {
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
    func startOptimistic(_ req: NewSessionRequest, attachments: [ComposerAttachment] = []) -> String {
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
        busy[placeholder] = true            // the agent is spinning up on this prompt
        addPending(placeholder, text: typed)   // finished (showSent) kickoff bubble
        Task { await attemptCreate(placeholder, req, attachments: attachments) }
        return placeholder
    }

    /// Run the real create for a placeholder, then remap all of its state to the
    /// server-assigned id and point navigation at it. On failure, surface the
    /// kickoff bubble's Retry (which re-enters here).
    private func attemptCreate(_ placeholder: String, _ req: NewSessionRequest, attachments: [ComposerAttachment]) async {
        guard let client else { return }
        do {
            let resp = try await client.newSession(req)
            guard let realId = resp.sessionId else {
                throw LFGError.http(status: 0, body: "Create returned no session id")
            }
            pendingCreates[placeholder] = nil
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
        }
        if focusedID == old { focus(new) }
    }

    func resume(_ req: ResumeRequest) async -> String? {
        guard let client else { return nil }
        do {
            let resp = try await client.resume(req)
            await refresh()
            return resp.sessionId
        } catch { lastError = "Resume failed: \(error.localizedDescription)"; return nil }
    }
}
