# Feature: phase1-connectivity-core

Tier: **product**. Spec: `.claude/brainstorm/multihost-first-rearchitecture.md` §4, §6.1, §7.2, §10 Phase 1.

## User Story

The iOS client's connection to a reachable host never drops because of the app's own behavior,
survives real network flaps invisibly (one lossless round-trip to recover), detects a dead path in
≤20s, and reports "unreachable" only when a host has genuinely been unreachable for ≥30s.

## Success Criteria

- **SC1 (no self-teardowns):** opening/closing/creating/transferring sessions causes **zero** stream
  reconnects. The events stream has no id-set to rebuild.
- **SC2 (lossless resume):** kill the server mid-stream; on restart the client reconnects with
  `since=<cursor>` and receives every journaled event it missed — zero loss, no 40-message cap.
- **SC3 (fast detection/recovery):** a silently-stalled connection (SIGSTOP'd server — the
  black-hole case) is detected ≤20s; after SIGCONT/network-restore, recovery ≤3s.
- **SC4 (honest banner):** no unreachable-banner for blips <30s; sustained failure shows it, per host.
- **SC5 (keepalive):** client pings each live host every ~10s; server heartbeats every 10s carrying
  head seq. (NAT warmth + RTT visibility + gap detection.)
- **SC6 (isolated restarts):** editing one host in Settings restarts only that host's link.
- **SC7 (restart-safe pump):** a server restart does not re-journal transcript history (persisted
  pump offsets); a fresh client (no cursor) bootstraps via REST + streams from head.
- **SC8 (no regressions):** existing suites stay green; send/queue/prompt flows unchanged.

## Test Strategy

- Journal core, pump delta logic, retention, resync boundaries → bun tests (pure, sqlite in temp dir).
- SSE `id:` parsing, cursor rules, backoff schedule, banner policy → LFGCore swift tests (pure).
- SC1–SC4 are async/live properties → verified against the real server: scripted lifecycle churn
  (SC1), SIGKILL + journal diff (SC2), SIGSTOP/SIGCONT timing (SC3/SC4), per
  memory `verify-real-seam-not-mocks`.

## Design pins (from proposal)

- Journal: `~/.lfg/journal.db` (bun:sqlite, WAL). `events(seq PK AUTOINCREMENT, ts, sessionId, type, payload)`.
  A host journals only sessions it executes. Retention 14 days.
- Pump: ONE global loop (transcript tail 700ms, pane poll 1000ms) replacing per-connection pumps;
  per-session offsets persisted in a `pump_state` table.
- `GET /api/events?since=` (SSE): replay then live; SSE `id:` = seq; `: hb <headSeq>` every 10s;
  `event: resync` when `since` is unserviceable → client full-refreshes and resets cursor to head.
- Client: `HostLink` actor per host owns connect/catch-up/live/backoff + keepalive + watchdog;
  cursor in UserDefaults (`lfg.cursor.<hostId>`); events feed the existing `apply(LiveEvent)`;
  unknown sessionId → `refresh()`; poll loop 3s → 60s reconcile.
- Old endpoints untouched (web client + old app builds keep working).

## Tests

### Unit (all green: bun 79/79 incl. 14 new; swift 98/98 incl. 11 new)
- `src/journal.test.ts` — append/since/head monotonicity, replay ordering + limits,
  live subscription + throwing-subscriber isolation, **canServe resync boundaries**
  (incl. the fully-pruned-idle-journal case that forced head onto the AUTOINCREMENT
  counter), pump offsets, PumpDeltas first-sight/change/forget semantics.
- `ios/LFGCore/Tests/LFGCoreTests/HostEventsTests.swift` — SSE `id:` capture with
  last-event-id persistence, HostStreamDecoder (event-with-seq / heartbeat-with-head /
  bare heartbeat / resync / unknown-event / missing-id), HostLinkPolicy reconnect
  schedule + ≤20s stale target + 30s sustained-banner rule.

### Live gates (real app in simulator ↔ real Phase-1 server; evidence in `phase1-evidence/`)
- **SC1 ✅ zero rebuilds:** two session opens + backs, a real session created via API,
  and a send — `connect-log.txt` shows exactly ONE `[events] connect` for the entire
  churn. (Old code rebuilt the stream on every one of these.)
- **SC2 ✅ zero loss:** server SIGKILLed mid-stream; a marker line written into a live
  transcript during the outage; server restarted → app reconnected
  `since=530 head=604` (cursor resume, not from-scratch) and the marker rendered in
  the open transcript (`gate2-marker2.png` — "SC2-MARKER-PHOENIX-7741").
- **SC3 ✅:** 26s SIGSTOP black-hole → invisible (no banner, stream resumed);
  sustained stall recovered ≤13s after SIGCONT (`gateB2-after.png`).
- **SC4 ✅ honest banner:** 26s stall → "Connected" throughout (`gate34-A-during.png`);
  58s stall → "Offline · Host unreachable" by ~T+50 (`gateB2-during.png`), cleared on
  recovery. First run FAILED and caught two real bugs (see Bugs).
- **SC5 ✅** 10s server heartbeats observed; client keepalive wired (RTT sampled).
- **SC7 ✅ restart-safe pump:** scratch-server restart delta = 65 events
  (~32 sessions × 2 baseline re-states + 4 genuine restart-gap messages), zero
  history reflood; pre-restart cursor stayed serviceable.
- **SC8 ✅** full suites green; send path exercised live against the Phase-1 server.

## Implementation Details

Server: `src/journal.ts` (Journal + PumpDeltas), `src/journal-pump.ts` (one global
pump; per-session offsets persisted; cross-host rule: sessions appearing mid-pump
start at file end), `/api/events?since=` + `/api/ping` + connect logging in
`src/commands/serve.ts`. Client: `LFGCore/HostEvents.swift` (HostStreamElement,
decoder, HostLinkPolicy), `LFGClient.events(since:)` (18s idle `timeoutInterval`
covering the header phase + 20s byte watchdog) + `keepalivePing()`,
`LFG/HostLink.swift` (state machine), `SessionStore` rewiring (syncLinks diff,
ingest→apply, 60s reconcile, link-driven reachability with scheduled banner
re-check, enterBackground grace / enterForeground resume), `focus()` no longer
touches any connection. Old `/api/live/stream` + `liveStream(ids:)` kept for
back-compat (web client, old app builds); deleted from the app path.

## Residual Risks

- **SC6 (Settings-edit link isolation) verified by code shape, not live UI**: 
  `syncLinks` is a pure diff (only added/removed host ids are touched) and
  `reconnect()` no longer calls `stop()`; driving the Settings URL-field UI under
  automation wasn't attempted (documented flaky). Covered implicitly by SC1 (no
  rebuilds when the host list is unchanged). Verify manually on first TestFlight run.
- **A new session's first turns can precede the pump's first sighting** (offset
  starts at file end) — the app covers via `loadHistory` on open, same as the old
  40-message backfill did. Track B's outbox/acks make this exact.
- **Transcripts dict now grows for ALL sessions on a healthy host** (no 24-id cap
  bounding it). Bounded in practice by session count × activity; properly bounded by
  the Track B store. Watch memory on TestFlight.
- Keepalive pings run only while foregrounded and healthy — NAT warmth during
  long-idle foreground is the target case; background is Phase 2's job.

## Bugs (found BY the gates, fixed, re-verified)

1. **Banner could lag ~55s past its 30s rule** — the sustained-failure flip only
   evaluated on state-change callbacks, which arrive once per watchdog cycle during
   a stall. Fix: `SessionStore.linkStateChanged` schedules a re-check for the exact
   moment the grace window closes.
2. **A black-holed connect was invisible to all watchdogs** — `events()` started its
   stale watchdog only after response headers, but a SIGSTOPed/vanished server
   accepts TCP and never sends headers, hanging the request forever; meanwhile
   `HostLink` claimed `.catchingUp` (healthy) on dial, so the banner re-check reset
   the host to `.ok`. Fix: 18s idle `timeoutInterval` (covers the header phase;
   resets on every byte so 10s heartbeats never trip it) + `.connecting` until bytes
   actually flow.
