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
