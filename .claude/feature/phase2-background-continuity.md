# Feature: phase2-background-continuity

Tier: **product**. Spec: `.claude/brainstorm/multihost-first-rearchitecture.md` §5, §10 Track A Phase 2.
Builds on Phase 1's journal cursors (`.claude/feature/phase1-connectivity-core.md`).

## User Story

The backgrounded/locked phone stays current: pushes carry the host's journal head so the app
delta-syncs on wake and is current at unlock with no spinner; sends complete even if the app is
immediately backgrounded or killed; running sessions are visible on the lock screen via Live
Activities.

## Sub-tasks & routing (Claude = frame/verify, Codex = execute)

| # | What | Owner | Status |
|---|---|---|---|
| A | Server: `/api/events/page` + push payloads carry `{hostId, seq}` + content-available | **Codex** (brief: `.codex/delegate/brief-phase2a-server.md`) | ✅ done, Claude-verified |
| B | Client: remote-notification wake + BGAppRefreshTask → per-host delta sync via page endpoint | Claude | ✅ done, sim-verified (device caveat below) |
| C | Client: sends via background URLSession + persisted pending list | spec ready: `.codex/delegate/brief-phase2c-background-sends.md` — execution deferred until ios/LFG/* is quiet (twin session active); gates C1–C3 must run on sim/device | spec ✅ / exec pending |
| D1 | Server: liveactivity APNs (token endpoints + store, pure payload builders, watcher hooks behind `LFG_LIVE_ACTIVITIES=1`) | **Codex** (brief: `.codex/delegate/brief-phase2d1-liveactivity-server.md`) | delegated, in flight |
| D2 | Client: widget extension target (project.yml), `LFGSessionAttributes` shared type, push-to-start + update-token registration, frequent-updates entitlement | Claude — after D1 verified + twin idle (project.yml/xcodegen collides with active builds) | pending |

## A+B results (2026-07-10)

- **Codex delegation (A):** implemented per brief on the first pass — page endpoint, payload
  keys, injected watcher deps, 5 files, 82/82 bun tests. Its sandbox couldn't bind ports, so
  Claude ran the live curls: page rows with string payloads ✓, `canServe:false` shape ✓, log
  lines ✓. Honest report incl. the sandbox limitation.
- **Live chain (B):** push → hint parse → `backgroundSync` → cursor page fetch, proven on the
  sim at the real seam: foreground-current case `page since=438 … served=0` (idempotent no-op),
  and the behind-cursor case after a 25s server outage: **`page since=475 head=565 served=90`** —
  the push-driven sync recovered all 90 missed events before the link reconnected.
- **Bugs caught live, fixed:** (1) `backgroundSync` skipped hosts with "healthy" links — but a
  suspended process's link always READS healthy (frozen watchdogs); skip removed, idempotency
  makes it safe. (2) Remote-notification registration was gated behind alert permission — silent
  pushes need REGISTRATION, not permission; now registered unconditionally at launch.
  (3) A running link in backoff never picked up cursor advances from a background sync —
  `reloadCursor()` now runs per connect attempt. (4) The remote-wake delegate needed the
  `@MainActor` async variant under Swift 6 (non-Sendable userInfo).
- **Simulator limitation (documented, not a code bug):** `simctl push` never drives
  `didReceiveRemoteNotification` on this sim (any variant, any payload — while UN-center
  delivery and token registration demonstrably work). The `willPresent` foreground-sync path was
  added as product-legitimate redundancy AND is what the sim verifies. **Device checkpoint for
  the soak:** confirm a real APNs push while backgrounded produces a `[events] page` line in the
  prod server log from the phone.
- SC-B3 (BGAppRefresh): registration + scheduling verified (registers without exception,
  submits on background); actual firing is at iOS's discretion — device-soak observable.

## Design decisions (pinned)

- **D1 — page endpoint, not SSE, for background syncs.** `GET /api/events/page?since=<seq>&limit=<n>`
  → JSON `{ events: [{seq, ts, sessionId, type, payload}], head, canServe }` where `payload` is the
  RAW JSON STRING as journaled. Client rebuilds an `SSEFrame(event: type, data: payload, id: seq)`
  and reuses the exact Phase-1 decode path — zero new decode logic on either side.
- **D2 — piggyback, don't add a silent-push stream.** The existing watcher pushes (finished /
  needs-input) gain `content-available: 1` + custom keys `{hostId, seq}` (journal head at send
  time). One push both notifies the human AND wakes the app to sync. No separate pure-silent
  pushes in Phase 2 (respects iOS's silent-push budget); `BGAppRefreshTask` covers the gaps.
- **D3 — journal head reaches the watcher by injection** (TickDeps gains `head()`), matching its
  existing deps pattern; wired in `cmdServe` where the journal already lives.
- **D4 — client wake path:** `didReceiveRemoteNotification` parses `{hostId, seq}` (pure parser in
  LFGCore/Push.swift + test); if `seq >` stored cursor for that host → fetch page(s), apply through
  the existing `apply(LiveEvent)` reducer, advance cursor, call completionHandler(.newData).
  BGAppRefresh (`me.eugenechan.lfg.refresh`) does the same for ALL hosts, no push needed.
- **D5 — background sends:** own brief after A+B verified (riskiest integration; touches
  dispatchSend/pendingSends).

## Success Criteria

- **SC-A1:** `/api/events/page` returns exactly the journaled events after `since`, `head`, and
  `canServe:false` for unserviceable cursors; additive (old endpoints untouched); bun tests green.
- **SC-A2:** watcher pushes carry `content-available: 1` + `hostId` + `seq` (verified in apns body
  unit test + a live push observed).
- **SC-B1:** simulated push (`simctl push` with `{hostId, seq}`) against a backgrounded sim app →
  app wakes, fetches the delta, cursor advances (observable via server connect/page logs).
- **SC-B2:** foreground after background-wake shows current transcript with NO catch-up spinner
  and no stream rebuild beyond the normal resume.
- **SC-B3:** BGAppRefresh task registered and schedulable (verified via LLDB/`e -l swift` trigger
  or BGTaskScheduler debug launch); performs the same delta sync.
- **SC-8:** all suites green; Phase-1 gates unaffected (no stream behavior change while foreground).

## Tests / Implementation / Bugs

_Populated as sub-tasks land._
