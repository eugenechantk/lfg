import Foundation
import LFGCore

/// One host's connection, as a real state machine — Phase 1 of the multi-host
/// rearchitecture (`.claude/feature/phase1-connectivity-core.md`).
///
/// Owns everything about staying connected to a single `lfg serve`:
/// the cursor-resumable `/api/events` stream (whole host, no id set — nothing
/// is ever rebuilt when sessions open/close/transfer), the persisted journal
/// cursor, the 10s keepalive ping, and its own immediate-then-backoff
/// reconnect loop. The store consumes events and state changes via callbacks;
/// it never tears a link down for anything but host-list changes and
/// backgrounding.
///
/// Health semantics: `unhealthySince` is the moment this link object last
/// stopped receiving (connect failure or stream death) and is cleared by the
/// first element received after reconnect. `SessionStore` owns the durable
/// sustained-failure clock across foreground teardowns/rebuilds.
@MainActor
final class HostLink {
    enum State: Equatable {
        case idle              // not started / stopped
        case connecting        // first dial of this attempt
        case catchingUp        // connected, replaying since=<cursor>
        case live              // heartbeat seen — fully current
        case backoff(Int)      // waiting reconnectDelay(attempt)
    }

    let host: Host
    private let client: LFGClient
    private(set) var state: State = .idle
    /// When the link last left the healthy states; nil while healthy.
    private(set) var unhealthySince: Date?
    /// When the last stream element (event or heartbeat) arrived. The freshness
    /// signal `resumeNow` uses — `state` alone can't tell a live stream from one
    /// frozen by a process suspension.
    private(set) var lastElementAt: Date?
    private(set) var lastRTT: TimeInterval?

    var onEvent: ((LiveEvent) -> Void)?
    /// The server declared our cursor unserviceable — full-refresh via REST.
    var onResyncNeeded: (() -> Void)?
    var onStateChange: (() -> Void)?

    private var runTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private let cursorKey: String
    private(set) var cursor: Int64
    private let localStore: LFGStore?

    init(host: Host, client: LFGClient, localStore: LFGStore? = nil) {
        self.host = host
        self.client = client
        self.localStore = localStore
        // Shared key with the background delta sync (HostLinkPolicy.cursorKey):
        // both paths advance the SAME cursor, so a push-wake sync while the app
        // was backgrounded shortens the next foreground catch-up.
        self.cursorKey = HostLinkPolicy.cursorKey(forHostURL: host.id)
        self.cursor = Int64(UserDefaults.standard.string(forKey: cursorKey) ?? "") ?? 0
    }

    /// Re-read the persisted cursor (a background sync may have advanced it
    /// while this link was stopped). Called on start().
    private func reloadCursor() {
        if let s = UserDefaults.standard.string(forKey: cursorKey), let v = Int64(s), v > cursor {
            cursor = v
        }
    }

    var isHealthy: Bool {
        switch state {
        case .catchingUp, .live: return unhealthySince == nil
        case .connecting, .idle, .backoff: return false
        }
    }

    func start() {
        guard runTask == nil else { return }
        startRunTask()
    }

    func retryNow() {
        switch state {
        case .catchingUp, .live:
            // Bytes are flowing. Do not churn a healthy stream just because the
            // system path changed.
            return
        case .idle:
            start()
        case .connecting, .backoff:
            redial()
        }
    }

    /// Foreground kick — "the user just opened the app, be connected NOW".
    ///
    /// Stronger than `retryNow()` in two places, both of which cost the user
    /// seconds of a stale "Offline" badge otherwise:
    ///   - a link in `.backoff` skips the rest of its wait (up to 30s);
    ///   - a link that *looks* healthy but has been quiet past one heartbeat
    ///     interval is redialed rather than left to the 20s stale watchdog. A
    ///     suspended process's link always reads healthy on resume (its
    ///     watchdogs were frozen too), so freshness has to come from
    ///     `lastElementAt`, not from `state`.
    /// A dial that is genuinely in flight is left alone — cancelling it to start
    /// an identical one only adds latency.
    func resumeNow(now: Date = Date()) {
        switch state {
        case .idle:
            start()
        case .backoff:
            redial()
        case .connecting:
            // A dial that has already failed at least once; a fresh one
            // (unhealthySince == nil) is left to complete.
            if unhealthySince != nil { redial() }
        case .catchingUp, .live:
            let quietFor = now.timeIntervalSince(lastElementAt ?? now)
            if quietFor > HostLinkPolicy.quietRedialAfter { redial() }
        }
    }

    private func redial() {
        runTask?.cancel()
        runTask = nil
        startRunTask()
    }

    private func startRunTask() {
        reloadCursor()
        runTask = Task { [weak self] in await self?.run() }
        if pingTask == nil {
            pingTask = Task { [weak self] in await self?.keepalive() }
        }
    }

    func stop() {
        runTask?.cancel(); runTask = nil
        pingTask?.cancel(); pingTask = nil
        setState(.idle)
    }

    private func setState(_ s: State) {
        guard state != s else { return }
        state = s
        onStateChange?()
    }

    private func markUnhealthy() {
        if unhealthySince == nil { unhealthySince = Date() }
        onStateChange?()
    }

    private func markReceiving() {
        if unhealthySince != nil {
            unhealthySince = nil
            onStateChange?()
        }
    }

    private func persistCursor() {
        UserDefaults.standard.set(String(cursor), forKey: cursorKey)
        guard let localStore else { return }
        let hostID = host.id
        let seq = cursor
        Task.detached(priority: .utility) {
            do { try await localStore.setCursor(hostId: hostID, seq: seq) }
            catch { }
        }
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled {
            let delay = HostLinkPolicy.reconnectDelay(attempt: attempt)
            if delay > 0 {
                setState(.backoff(attempt))
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            // A background sync may have advanced the persisted cursor while
            // this loop was in backoff (push-wake during an outage) — pick it
            // up per attempt, or the reconnect wastefully re-replays what the
            // sync already applied (caught live in the Phase-2 gate test).
            reloadCursor()
            // .connecting until BYTES actually flow — claiming .catchingUp on
            // dial would read as healthy while hung against a black-holed host
            // (caught live in the Phase-1 gate test: the banner re-check saw a
            // "healthy" link that was really stuck awaiting response headers).
            setState(.connecting)
            var receivedAny = false
            do {
                for try await element in client.events(since: cursor) {
                    if Task.isCancelled { return }
                    receivedAny = true
                    lastElementAt = Date()
                    markReceiving()
                    switch element {
                    case .event(let seq, let ev):
                        cursor = seq
                        persistCursor()
                        if state != .live { setState(.catchingUp) }
                        onEvent?(ev)
                    case .heartbeat:
                        // Heartbeats only flow once the replay backlog is done —
                        // the definitive "caught up" signal.
                        setState(.live)
                    case .resync(let head):
                        cursor = head
                        persistCursor()
                        setState(.catchingUp)
                        onResyncNeeded?()
                    }
                }
                // Clean close (server restart / idle EOF). If this connection was
                // healthy, retry immediately — the common case is the server
                // coming right back, and the cursor makes the reconnect free.
                attempt = receivedAny ? 0 : attempt + 1
                if !receivedAny { markUnhealthy() }
            } catch {
                if Task.isCancelled { return }
                // Stream died (network blip, stale watchdog, connect failure).
                markUnhealthy()
                attempt = receivedAny ? 1 : attempt + 1
            }
        }
    }

    /// 10s keepalive while the stream is up: keeps the phone-side carrier-NAT
    /// mapping warm (idle expiry is what causes Tailscale re-punch flaps) and
    /// samples RTT. Failures are ignored — the stream watchdog is the authority
    /// on liveness, and a lost ping alone shouldn't churn state.
    private func keepalive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(HostLinkPolicy.keepaliveInterval))
            if Task.isCancelled { return }
            switch state {
            case .catchingUp, .live:
                if let r = try? await client.keepalivePing() { lastRTT = r.rtt }
            default:
                break
            }
        }
    }
}
