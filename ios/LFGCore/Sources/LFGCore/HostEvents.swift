import Foundation

/// One element of a host's cursor-resumable event stream (`GET /api/events`).
///
/// The stream is the Phase-1 replacement for the id-selected `/api/live/stream`:
/// one stream per host covers every session that host executes, each journaled
/// event carries a monotonic `seq` (the SSE `id:` field), and reconnecting with
/// `since=<last applied seq>` replays exactly what was missed. See
/// `.claude/feature/phase1-connectivity-core.md`.
public enum HostStreamElement: Sendable {
    /// A journaled event. Apply it, then advance the cursor to `seq`.
    case event(seq: Int64, LiveEvent)
    /// `: hb <head>` — connection is alive; `head` is the journal's newest seq.
    /// A head far beyond the local cursor with no events arriving means the
    /// stream is wedged (shouldn't happen; belt-and-braces gap detector).
    case heartbeat(head: Int64?)
    /// The cursor was unserviceable (predates retention, or from a previous
    /// journal lifetime). Full-refresh via REST and reset the cursor to `head`.
    case resync(head: Int64)
}

public enum HostStreamDecoder {
    /// Decode a parsed SSE frame from `/api/events`. Returns nil for frames we
    /// don't understand (forward compatibility: unknown event types are skipped
    /// but their seq still advances the cursor via the next known event).
    public static func decode(_ frame: SSEFrame, sessionIdHint: String? = nil) -> HostStreamElement? {
        if frame.isComment {
            // Comment body is "hb <head>" (head added in Phase 1; tolerate bare "hb").
            let parts = frame.data.split(separator: " ")
            if parts.first == "hb", parts.count > 1, let head = Int64(parts[1]) {
                return .heartbeat(head: head)
            }
            return .heartbeat(head: nil)
        }
        if frame.event == "resync" {
            struct R: Decodable { let head: Int64? }
            let head = (frame.data.data(using: .utf8))
                .flatMap { try? JSONDecoder().decode(R.self, from: $0) }?.head ?? 0
            return .resync(head: head)
        }
        guard let idStr = frame.id, let seq = Int64(idStr) else { return nil }
        guard let ev = LiveEventDecoder.decode(frame, sessionIdHint: sessionIdHint) else { return nil }
        return .event(seq: seq, ev)
    }
}

/// One page of journaled events from `GET /api/events/page` — the
/// non-streaming fetch shape used by background wakes (push / BGAppRefresh),
/// where holding an SSE stream isn't possible. Rows decode through the exact
/// same path as the live stream: each is rebuilt into an `SSEFrame` and handed
/// to `HostStreamDecoder`, so page-synced and stream-synced state can't drift.
public struct EventsPage: Sendable {
    public let events: [(seq: Int64, event: LiveEvent)]
    public let head: Int64
    /// False = the cursor was unserviceable (predates retention / journal
    /// recreated). Full-refresh via REST and reset the cursor to `head`.
    public let canServe: Bool

    public init(events: [(seq: Int64, event: LiveEvent)], head: Int64, canServe: Bool) {
        self.events = events; self.head = head; self.canServe = canServe
    }

    struct Wire: Decodable {
        struct Row: Decodable {
            let seq: Int64
            let sessionId: String?
            let type: String
            let payload: String
        }
        let events: [Row]
        let head: Int64?
        let canServe: Bool?
    }

    /// Decode the wire JSON, folding each row through the stream decoder.
    /// Unknown event types are skipped (forward compatibility), same as the
    /// live stream path.
    public static func decode(_ data: Data) throws -> EventsPage {
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        var out: [(seq: Int64, event: LiveEvent)] = []
        out.reserveCapacity(wire.events.count)
        for row in wire.events {
            let frame = SSEFrame(event: row.type, data: row.payload, isComment: false, id: String(row.seq))
            if case .event(let seq, let ev)? = HostStreamDecoder.decode(frame, sessionIdHint: row.sessionId) {
                out.append((seq: seq, event: ev))
            }
        }
        return EventsPage(events: out, head: wire.head ?? 0, canServe: wire.canServe ?? true)
    }
}

/// Pure connection policy for a `HostLink` — every number the link's behavior
/// hangs off, testable without a network or a clock.
public enum HostLinkPolicy {
    /// How long the events stream may go silent (no bytes at all — the server
    /// heartbeats every 10s, so this is ~two missed heartbeats) before the link
    /// declares it dead and reconnects. Phase-1 target: detection ≤ 20s.
    ///
    /// This is the LAN number. On a relayed path use `staleTimeout(for:)`.
    public static let staleTimeout: TimeInterval = 20

    /// The stall watchdog, widened for a slow path.
    ///
    /// 20s is two missed heartbeats on a ~5ms LAN. Over a DERP relay, where one
    /// lost packet head-of-line blocks the tunnel, a 20s gap is a stream that is
    /// slow rather than dead — and dropping it costs a full relay re-dial, which
    /// makes the next gap more likely, not less.
    ///
    /// Capped at 2× deliberately. Detection has to stay bounded: 40s ≈ four
    /// missed heartbeats, and beyond that the user is staring at dead air for
    /// longer than a redial would have cost.
    public static func staleTimeout(for quality: PathQuality) -> TimeInterval {
        staleTimeout * quality.scale(max: 2)
    }

    /// How long to wait for the stream's RESPONSE HEADERS before giving up.
    ///
    /// Scoped to the connect phase on purpose. A black-holed host accepts the TCP
    /// connection and then never sends headers, which the byte-stall watchdog
    /// cannot catch because it only starts once headers arrive — so this phase
    /// needs its own bound. It used to be expressed as `URLRequest.timeoutInterval
    /// = 18`, which looked like a connect bound but is actually an IDLE timeout
    /// spanning the WHOLE request. That silently overrode `staleTimeout`: on a
    /// relayed path the client logged `stale=40s`, believed it, and URLSession
    /// still killed the stream at ~18s of quiet. The proof is negative — across
    /// every connection log captured on 2026-08-16 the string "STALL — no bytes"
    /// appears zero times, while `-1001 timedOut` at 18–21s of idle appears
    /// constantly. The custom watchdog had never once fired.
    public static let headersTimeout: TimeInterval = 18

    /// The idle timeout to hand URLSession for a stream. Never below the stale
    /// watchdog, or URLSession pre-empts the policy this client actually intends.
    public static func streamRequestTimeout(for quality: PathQuality) -> TimeInterval {
        max(headersTimeout, staleTimeout(for: quality))
    }

    /// Keepalive request timeout, widened for a slow path.
    ///
    /// The ping is the **only** source of RTT samples, so a fixed 5s timeout is a
    /// feedback trap: on the exact path where the estimate matters, every ping
    /// times out, no samples are recorded, and the estimator stays pinned at the
    /// LAN default forever. Capped at `keepaliveInterval` so a slow ping can
    /// never overlap the next one.
    public static func keepaliveTimeout(for quality: PathQuality) -> TimeInterval {
        min(5 * quality.scale(max: 2), keepaliveInterval)
    }

    /// Keepalive ping cadence per live host. Primary purpose is keeping the
    /// phone-side carrier-NAT mapping warm (idle bindings expire in ~30s and
    /// their expiry is what triggers Tailscale re-punch flaps); also yields an
    /// RTT sample and bidirectional fast death detection.
    public static let keepaliveInterval: TimeInterval = 10

    /// When the next keepalive tick is due, given the tick that just ran.
    ///
    /// Deadline-based, NOT sleep-after-work. Sleeping `keepaliveInterval` *after*
    /// the ping returns makes the real cadence `interval + ping duration`, and the
    /// ping's own timeout widens with a bad path — so on the exact path where the
    /// NAT binding needs warming, 10s quietly became ~19s against a binding that
    /// expires at ~30s. Measured in the 2026-08-16 cellular log: pings at
    /// 13:48:13.7 and 13:48:33.2, a 19.5s gap, with nothing in between.
    ///
    /// If a tick overran its own deadline the schedule is rebased on now rather
    /// than firing a burst of catch-up pings, which would be worse than late.
    public static func keepaliveNextDeadline(after due: Date, now: Date) -> Date {
        let next = due.addingTimeInterval(keepaliveInterval)
        return next > now ? next : now.addingTimeInterval(keepaliveInterval)
    }

    /// How long with NO successful contact of any kind — a stream byte or a
    /// keepalive pong — before a host is treated as **cold**.
    ///
    /// A cold host is not merely unhealthy; it is one nothing has reached for
    /// minutes, and the overwhelmingly likely reason is that it is switched off.
    /// The Air spent the whole of the 2026-08-16 outdoor log that way — six hours,
    /// `dial since=26089` never advancing, not one set of response headers — while
    /// costing a full 18 s stream timeout per attempt plus a keepalive every 10 s,
    /// on the same marginal cellular link the *reachable* host was struggling over.
    ///
    /// Two minutes is deliberately far longer than any blip this client is
    /// designed to ride out (the stale watchdog tops out at 40 s, the reconnect
    /// ladder at 30 s), so a host that is merely having a bad time never trips it.
    public static let coldAfter: TimeInterval = 120

    /// Whether a host should be treated as cold. `nil` means nothing has been
    /// recorded yet — a freshly started link is never cold.
    public static func isCold(lastContactAt: Date?, now: Date = Date()) -> Bool {
        guard let last = lastContactAt else { return false }
        return now.timeIntervalSince(last) >= coldAfter
    }

    /// A cold host is pinged one tick in this many — 10 s becomes 60 s.
    public static let coldKeepaliveEvery = 6

    /// Whether the NAT-warming keepalive should fire on this tick.
    ///
    /// It fires whenever the link is started — **including while connecting or in
    /// backoff**. Gating it on an already-healthy stream was a self-sustaining
    /// failure loop on cellular: the stream drops, the link leaves `.live`, the
    /// keepalive goes silent, the carrier NAT binding idles out at ~30s, Tailscale
    /// has to re-punch, traffic black-holes, so the stream cannot reconnect and
    /// the link never returns to `.live` to re-enable the keepalive. The one
    /// moment the binding most needs a packet is the moment this used to stop
    /// sending them.
    ///
    /// A **cold** host is the exception, and it is the correction to that fix
    /// rather than a retreat from it: there is no NAT binding worth warming
    /// toward a machine that is off, so it drops to one ping a minute. It never
    /// stops entirely — that is what lets the host be noticed when it returns.
    public static func keepaliveShouldPing(linkStarted: Bool, isCold: Bool, tick: Int) -> Bool {
        guard linkStarted else { return false }
        guard isCold else { return true }
        return tick % coldKeepaliveEvery == 0
    }

    /// Whether a foreground kick may skip the rest of a link's backoff wait.
    ///
    /// For a reachable host, yes — that is the whole point of the kick, and it is
    /// what turns a 30 s stale badge into an instant reconnect. For a cold one,
    /// no: the app coming forward is not new information about a machine that has
    /// been unreachable for minutes, and honouring it there is what kept the dead
    /// Air pinned at attempt 1. Every `APP foreground` in the 2026-08-16 log —
    /// dozens of them — reset its ladder and bought another immediate 18 s dial.
    /// Cold hosts keep climbing their own backoff to the 30 s cap instead.
    public static func foregroundMaySkipBackoff(isCold: Bool) -> Bool { !isCold }

    /// How quiet an apparently-healthy stream may be before a foreground kick
    /// force-redials it. The server heartbeats every 10s, so anything past this
    /// has already missed one — and after a process suspension a link can *read*
    /// healthy (`.live`, no failure recorded) while its socket is long dead,
    /// because its watchdogs were frozen along with everything else. Waiting for
    /// the 20s stale watchdog to notice is exactly the "not connected for a
    /// while" the user sees on reopening the app.
    public static let quietRedialAfter: TimeInterval = 12

    /// Reconnect back-off: immediate first retry (the common case is a clean
    /// server restart or a momentary path blip — waiting helps nobody), then
    /// gentle growth capped at 30s so a genuinely-down host costs little.
    public static func reconnectDelay(attempt: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [0, 1, 2, 5, 10, 30]
        return schedule[min(max(attempt, 0), schedule.count - 1)]
    }

    /// The unreachable banner shows only for SUSTAINED failure: a host that has
    /// been unhealthy for at least this long. Blips shorter than this render as
    /// nothing (the link is quietly reconnecting/catching up).
    public static let bannerAfter: TimeInterval = 30

    /// Whether the per-host "unreachable" UI should show, given when the link
    /// last left the healthy states (nil = currently healthy).
    public static func showUnreachable(unhealthySince: Date?, now: Date = Date()) -> Bool {
        guard let since = unhealthySince else { return false }
        return now.timeIntervalSince(since) >= bannerAfter
    }

    /// UserDefaults key of a host's persisted journal cursor. Keyed by the
    /// CONFIGURED url (`Host.id`) — stable across app runs; editing the URL in
    /// Settings correctly starts a fresh cursor. Shared by `HostLink` (live
    /// stream) and the background delta sync so both advance the same cursor.
    public static func cursorKey(forHostURL hostURL: String) -> String {
        "lfg.cursor.\(hostURL)"
    }
}
