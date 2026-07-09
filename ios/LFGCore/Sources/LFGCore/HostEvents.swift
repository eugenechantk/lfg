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
    public static func decode(_ frame: SSEFrame) -> HostStreamElement? {
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
        guard let ev = LiveEventDecoder.decode(frame) else { return nil }
        return .event(seq: seq, ev)
    }
}

/// Pure connection policy for a `HostLink` — every number the link's behavior
/// hangs off, testable without a network or a clock.
public enum HostLinkPolicy {
    /// How long the events stream may go silent (no bytes at all — the server
    /// heartbeats every 10s, so this is ~two missed heartbeats) before the link
    /// declares it dead and reconnects. Phase-1 target: detection ≤ 20s.
    public static let staleTimeout: TimeInterval = 20

    /// Keepalive ping cadence per live host. Primary purpose is keeping the
    /// phone-side carrier-NAT mapping warm (idle bindings expire in ~30s and
    /// their expiry is what triggers Tailscale re-punch flaps); also yields an
    /// RTT sample and bidirectional fast death detection.
    public static let keepaliveInterval: TimeInterval = 10

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
}
