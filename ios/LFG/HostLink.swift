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
/// Health semantics: `unhealthySince` is the moment the link last stopped
/// receiving (connect failure or stream death) and is cleared by the first
/// element received after reconnect. The unreachable UI shows only when
/// `HostLinkPolicy.showUnreachable` says the failure is SUSTAINED (≥30s) — a
/// blip renders as nothing while the link quietly recovers.
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
    private(set) var lastRTT: TimeInterval?

    var onEvent: ((LiveEvent) -> Void)?
    /// The server declared our cursor unserviceable — full-refresh via REST.
    var onResyncNeeded: (() -> Void)?
    var onStateChange: (() -> Void)?

    private var runTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private let cursorKey: String
    private(set) var cursor: Int64

    init(host: Host, client: LFGClient) {
        self.host = host
        self.client = client
        // Keyed by the configured url (Host.id): stable across app runs, and a
        // URL edit in Settings correctly starts a fresh cursor for what may be
        // a different machine.
        self.cursorKey = "lfg.cursor.\(host.id)"
        self.cursor = Int64(UserDefaults.standard.string(forKey: cursorKey) ?? "") ?? 0
    }

    var isHealthy: Bool {
        switch state {
        case .catchingUp, .live: return true
        case .connecting: return unhealthySince == nil // first dial after a healthy run
        case .idle, .backoff: return false
        }
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in await self?.run() }
        pingTask = Task { [weak self] in await self?.keepalive() }
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
