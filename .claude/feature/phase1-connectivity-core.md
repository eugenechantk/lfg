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

_Populated during implementation._

## Implementation Details

_Populated during implementation._

## Residual Risks

_Populated at the end._

## Bugs

_None yet._
