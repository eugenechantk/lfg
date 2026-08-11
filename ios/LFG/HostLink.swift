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
/// Health semantics: this object holds **no** health opinion and keeps **no**
/// failure clock. It reports what happened (`HostSignal`) and `SessionStore`
/// folds that into the one `HostState` per host. The link used to own an
/// `unhealthySince` date, which the store then had to mirror into
/// `unhealthySinceByHost` to survive teardown/rebuild — two clocks that had to
/// agree before "recovered" could be asserted. The clock now lives in the state.
///
/// `attemptFailed` below is not a health opinion: it is a fact about the dial
/// currently in flight, used only to decide whether a foreground kick should
/// interrupt it.
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
    /// Whether the dial currently in flight has already failed at least once.
    /// Scoped to the attempt, not to the host's health — `resumeNow` uses it to
    /// avoid cancelling a fresh in-flight dial.
    private(set) var attemptFailed = false
    /// When the last stream element (event or heartbeat) arrived. The freshness
    /// signal `resumeNow` uses — `state` alone can't tell a live stream from one
    /// frozen by a process suspension.
    private(set) var lastElementAt: Date?
    private(set) var lastRTT: TimeInterval?
    /// Rolling RTT estimate for this host, and the timeout scaling derived from
    /// it. Owned here because the keepalive that samples it is owned here; read
    /// by `SessionStore` so the reconcile poll can size its own timeout per host.
    private(set) var pathQuality = PathQuality()
    /// Last grade written to the connection log, so a transition is logged once
    /// rather than once per 10s sample.
    private var loggedGrade: PathQuality.Grade = .unknown

    var onEvent: ((LiveEvent) -> Void)?
    /// Something happened that bears on this host's health. The store folds it
    /// through `HostStateMachine`; the link itself draws no conclusion.
    var onSignal: ((HostSignal) -> Void)?
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

    func start() {
        guard runTask == nil else { return }
        startRunTask()
    }

    func retryNow() {
        switch state {
        case .catchingUp, .live:
            // Bytes are flowing. Do not churn a healthy stream just because the
            // system path changed.
            //
            // NOTE: this is only safe when the caller knows the socket is still
            // valid. After a network PATH change it is not — see `resumeNow`,
            // which is what the path-restored handler calls now.
            log("retryNow: ignored, stream is \(state)")
            return
        case .idle:
            log("retryNow: starting from idle")
            start()
        case .connecting, .backoff:
            log("retryNow: redialing from \(state)")
            redial()
        }
    }

    /// Be connected NOW — the app just came forward, or the device's network
    /// path just changed underneath us.
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
    ///
    /// The same freshness argument applies to a **network path change**, which is
    /// why the path-restored handler calls this and not `retryNow()`: after the
    /// device's interface moves (5G↔LTE handover, VPN re-attach, Wi-Fi→cellular)
    /// the local endpoint has changed, so a socket that still reads `.live` is
    /// already dead and just hasn't noticed. `retryNow()` deliberately leaves
    /// those alone, which cost ~20s of dead air per path change — invisible on
    /// LAN, where paths don't change, and constant on cellular.
    ///
    /// - Parameter cause: recorded in the connection log so the timeline shows
    ///   *why* a redial happened, not just that one did.
    func resumeNow(now: Date = Date(), cause: String = "foreground") {
        switch state {
        case .idle:
            log("resumeNow(\(cause)): starting from idle")
            start()
        case .backoff(let attempt):
            log("resumeNow(\(cause)): skipping backoff (attempt \(attempt))")
            redial()
        case .connecting:
            // A dial that has already failed at least once; a fresh one is left
            // to complete.
            if attemptFailed {
                log("resumeNow(\(cause)): redialing a dial that already failed")
                redial()
            } else {
                log("resumeNow(\(cause)): leaving a fresh dial in flight")
            }
        case .catchingUp, .live:
            let quietFor = now.timeIntervalSince(lastElementAt ?? now)
            if quietFor > HostLinkPolicy.quietRedialAfter {
                log(String(format: "resumeNow(%@): stream READS %@ but has been quiet %.1fs — redialing",
                           cause, String(describing: state), quietFor))
                redial()
            } else {
                log(String(format: "resumeNow(%@): stream is fresh (quiet %.1fs) — left alone",
                           cause, quietFor))
            }
        }
    }

    private func log(_ message: String) {
        ConnectionLog.shared.log(.link, message, host: host.logLabel)
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
        onSignal?(.stopped)
    }

    private func setState(_ s: State) {
        guard state != s else { return }
        log("\(state) -> \(s)")
        state = s
        onStateChange?()
    }

    private func markFailed(_ reason: String) {
        attemptFailed = true
        onSignal?(.failed(reason: reason))
        onStateChange?()
    }

    private func markReceiving() {
        let was = attemptFailed
        attemptFailed = false
        onSignal?(.receiving)
        if was { onStateChange?() }
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
                log(String(format: "backoff %.0fs before attempt %d", delay, attempt))
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
            if !attemptFailed { onSignal?(.connecting) }
            var receivedAny = false
            do {
                for try await element in client.events(since: cursor, quality: pathQuality) {
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
                if !receivedAny { markFailed("Connection closed") }
            } catch {
                if Task.isCancelled { return }
                // Stream died (network blip, stale watchdog, connect failure).
                markFailed("Connection lost")
                attempt = receivedAny ? 1 : attempt + 1
            }
        }
    }

    /// 10s keepalive while the stream is up: keeps the phone-side carrier-NAT
    /// mapping warm (idle expiry is what causes Tailscale re-punch flaps) and
    /// samples RTT. Failures are ignored — the stream watchdog is the authority
    /// on liveness, and a lost ping alone shouldn't churn state.
    ///
    /// The ping's own timeout is derived from the estimate it feeds, which sounds
    /// circular but is the fix for a real trap: at a fixed 5s, every ping on a
    /// relayed path times out, so no sample is ever recorded and the estimate
    /// stays pinned at the LAN default precisely where it is most wrong. The
    /// floor at 1.0× means the loop can only widen from there, never tighten.
    private func keepalive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(HostLinkPolicy.keepaliveInterval))
            if Task.isCancelled { return }
            switch state {
            case .catchingUp, .live:
                let timeout = HostLinkPolicy.keepaliveTimeout(for: pathQuality)
                if let r = try? await client.keepalivePing(timeout: timeout) {
                    lastRTT = r.rtt
                    pathQuality.record(rtt: r.rtt)
                    noteGradeChange()
                }
            default:
                break
            }
        }
    }

    /// Log the path grade when it changes — once per transition, not per sample.
    /// This is what makes "the connection is iffy on 5G" a value you can read
    /// back from the log instead of something you have to be holding the phone
    /// to notice.
    private func noteGradeChange() {
        let grade = pathQuality.grade
        guard grade != loggedGrade else { return }
        let was = loggedGrade
        loggedGrade = grade
        ConnectionLog.shared.log(
            .keepalive,
            String(format: "path %@ -> %@ (%@); poll=%.0fs stale=%.0fs",
                   was.rawValue, grade.rawValue, pathQuality.summary,
                   HostProbePolicy.default.pollTimeout(for: pathQuality),
                   HostLinkPolicy.staleTimeout(for: pathQuality)),
            host: host.logLabel)
    }
}
