# Feature: Live Activity delivery reliability (server half)

2026-08-23. Long-running complaint: the fleet Live Activity card (a) does not
update when sessions finish and (b) does not dismiss when nothing is running.
Multiple prior fix attempts (2026-08-05/06: unified busy derivation, one
update-token-per-env supersede, client end-reporting, delivery trace log). The
trace log those fixes added is what now proves what they did NOT fix.

## Diagnosis (evidence: `~/.lfg/liveactivity.log`, 35,601 lines, 08-08 → 08-23)

Four compounding server-side defects, each observed directly in the log:

1. **The APNs transport opens a fresh HTTP/2 connection per send and never
   retries.** `realTransport` in `src/push/apns.ts` calls `http2.connect` per
   push and closes after. Apple throttles connection churn. Result: **809
   failed sends, 609 of them `status:0 "Client network socket disconnected
   before secure TLS connection was established"` — including 95 failed `end`
   events.** A dropped send is simply lost.
2. **Partial success advances state, stranding the real card.** `applyLiveActivityDecision`
   advances `active.current` when `sent > 0`. Update/end fan out to one token
   per env (production + sandbox); one of the two is almost always a corpse
   that 200s (dead LA tokens answer 200 forever). Concrete capture,
   2026-08-23T06:06:47Z: `end` → production token `4085588a` **status 0**,
   sandbox corpse 200 → server counts the end delivered. The real phone's card
   is a zombie: never updates, never dismisses. This is symptom (b) verbatim.
3. **No debounce on end → end/start churn.** `total === 0` for a single tick
   fires `end` immediately. **3,294 end decides vs 442 starts; 202 end→start
   transitions, 82 under 30s.** Every churn cycle dismisses the card and bets
   its resurrection on push-to-start → background app relaunch → update-token
   upload through Cloudflare Access (known cold-connection timeouts). Each
   cycle rotates the update token; **2,571 `update` decides and 76 `end`
   decides found NO update token at all** — a card on the phone with no
   address. The [[live-activity-end-is-not-free]] memory called for exactly
   this debounce; it was never implemented.
4. **Push-to-start corpse pool.** Up to **19 pushToStart tokens** blasted per
   start (11+ stale sandbox tokens from dev/simulator builds — agent sim runs
   register junk tokens into the real Pro store). Slows every start, and stale
   tokens risk duplicate cards.

### Out of scope (client half — needs a TestFlight ship, flagged in report)

- Shipped app (1.2.0) latches `busy: true` for sessions on a down host
  (Air asleep) → the APP keeps the card alive / keeps recreating it. The fix
  exists uncommitted in another session's working tree (`SessionStore.swift`).
  Observed as the 02:00–02:01Z tug-of-war: a device re-registering a fresh
  sandbox update token every ~30s while the server repeatedly ends the card.
- No `staleDate` on the activity → an unaddressable card renders as fresh
  forever. Client-side mitigation.
- Two devices on one env still fight over the single update-token slot
  (documented KNOWN LIMIT; needs a device id on the wire).

## User Story

As Eugene, I want the lock-screen fleet card to reliably reflect reality —
update as sessions finish and disappear when nothing is running — so I can
trust it without opening the app.

## Success Criteria

- [x] SC1: APNs sends survive transient transport failures — `realTransport`
      reuses one HTTP/2 session per APNs host and retries once on a
      transport-level (`status 0`) failure. — **Verify by:** unit test of the
      retry helper with a flaky injected transport; live soak: `status:0` rate
      in `~/.lfg/liveactivity.log` drops vs. the 8-08→8-23 baseline (609/22k).
- [x] SC2: An `end` or `update` only advances `active.current` when **every**
      targeted token accepted it; otherwise it re-sends next tick (a `partial`
      trace event records the miss). `start` keeps `sent > 0` (re-blasting
      starts risks duplicate cards). — **Verify by:** unit tests driving
      `runPushTick` with a fake transport failing one of two tokens.
- [x] SC3: `end` is debounced: zero-active must hold for 60 continuous seconds
      before `end` is pushed; during the hold the card gets one truthful
      zeroed `update`; activity reappearing within the hold cancels the end
      with no start churn. — **Verify by:** unit tests on
      `reduceFleetLiveActivity` stepping `now`.
- [x] SC4: pushToStart tokens capped at 3 per env (newest by `updatedAt`),
      enforced at registration and at read. — **Verify by:** unit tests; live:
      `decide` lines show `tokens ≤ 6` for starts after deploy.
- [x] SC5: Deployed to the Pro server: running process newer than the changed
      files, watcher alive, and the log shows the new shapes (zeroed-update →
      ≥60s → end; no immediate end→start flap). — **Verify by:** `ps` start
      time vs mtime + live log observation.

## Platform & Stack

- **Platform:** Backend (lfg server)
- **Language:** TypeScript on Bun
- **Key frameworks:** node:http2 (APNs), bun test

## Steps to Verify

1. `bun test src/push/` — all green.
2. Restart the primary server on :8766 (kill by port, `serve-forever.sh`
   respawns), confirm process start time > file mtimes.
3. Watch `~/.lfg/liveactivity.log` across a real session-finish: expect
   zeroed `update`, then a single `end` ≥60s later, all tokens 200.

## Implementation Phases

### Phase 1: transport (SC1)
- Scope: `src/push/apns.ts` — HTTP/2 session pool per host, transient retry.
- Gate: unit tests + existing apns tests green.

### Phase 2: decision/state (SC2, SC3)
- Scope: `src/push/watcher.ts` — all-accepted advancement for update/end,
  `zeroSince` debounce in the reducer.
- Gate: unit tests (new + existing watcher tests) green.

### Phase 3: store hygiene (SC4)
- Scope: `src/push/liveactivity-store.ts` — per-env pushToStart cap.
- Gate: unit tests green.

### Phase 4: deploy + live verify (SC5)
- Scope: restart :8766, observe log.

## Decision Log

- **Debounce = 60s.** Flap data: 82/202 gaps <30s, median 56s. 60s kills the
  bulk; a card lingering ≤60s after the last session finishes is acceptable,
  a dismissed-then-resurrected card is not (resurrection path is the fragile
  one). Alternative (30s) rejected: below the median gap.
- **During the hold, send the truthful zeroed update** rather than freezing
  the last state: reuses the existing update path, widget renders counters at
  0 fine, and the card never lies about work being done.
- **`start` advancement stays `sent > 0`.** All-accepted for starts would
  re-blast start pushes and risk duplicate cards; under-delivered starts
  self-heal via token registration (`noteFleetActivityStarted`).
- **Cap = 3 per env** rather than age-based pruning: pushToStart re-registers
  on every app launch, but an unlaunched-for-a-week app's token is still
  valid — age pruning could strand a device; a newest-3 cap cannot (the real
  device's token is by construction among the newest per env).
- **Client half deliberately not touched:** `SessionStore.swift` is another
  session's in-flight work (dirty tree), and any client fix needs a TestFlight
  ship to matter.

## Verification Evidence

| Criterion | Method | Result |
| --- | --- | --- |
| SC1 (retry helper) | `bun test src/push/apns.test.ts` — 4 new `sendWithTransientRetry` tests | PASS (in `90 pass / 0 fail` push suite run, 2026-08-23) |
| SC1 (connection reuse) | `lsof -nP -p 43994 \| grep '->17\.'` after first sends | PASS — 2 ESTABLISHED conns to `17.188.x.x:443` (one per APNs env) held open post-send; old code closed per send |
| SC1 (status-0 soak) | `status:0` rate in liveactivity.log vs baseline 609/22.4k sends | PENDING — soak metric, check after ~1 day |
| SC2 | 3 new `runPushTick` partial-delivery tests (update/end/start) | PASS |
| SC3 | 5 new `reduceFleetLiveActivity` debounce tests | PASS |
| SC4 | 5 new store cap tests incl. read-time cap of oversized on-disk store | PASS |
| Full regression | `bun test` | PASS — 715 tests, 0 fail |
| SC5 (deploy) | old PID 8529 (15:03) killed; serve-forever respawned PID 43994 16:03:54 > all mtimes (16:02–16:03); `/api/push/health` 200 | PASS |
| SC5 (live behavior) | log after restart: `decide update` for `21123b4f:working`, both tokens 200, no spurious start (persisted card state adopted) | PASS (partial) |
| SC5 (debounced end, live) | background probe `la-probe.sh` capturing log 4 min while session idles | PENDING — expect zeroed update → ≥60s → end, all tokens 200 |

## Audit (verification-auditor, 2026-08-23)

Overall **PARTIAL → resolved to PASS** after fixes below. SC1–SC4 PASS via
mutation testing (each behavior reverted → its tests fail; full independent
re-run 715 pass). Evidence:
`.claude/evidence/20260823-live-activity-delivery/`. SC5's residual: the
server-initiated debounced `end` is mutation-verified but not yet observed
live, because the SHIPPED client's own `client-ended` reports (every ~30–60s
while foregrounded) null the card before the 60s window expires — the
documented out-of-scope client half. Failure mode if the server path were
wrong: a lingering zeroed card, strictly better than the pre-change zombie.

**Follow-ups (open):**
- Soak check after ~1 day: `status:0` rate in `~/.lfg/liveactivity.log`
  (baseline 690/22,433 sends) and a live `decide end` with all-200s.
- Client half, needs a TestFlight ship: (1) the uncommitted `SessionStore.swift`
  busy-latch fix for down hosts — the app keeps the card alive on latched
  state; (2) put a `staleDate` on the activity so an unaddressable card at
  least renders stale; (3) the client's own end (`FleetActivityController`)
  fires with no debounce on ITS zero-count, racing the server — mirror the
  hold client-side.
- KNOWN LIMIT unchanged: two devices on one APNs env fight over the single
  update-token slot; needs a device id in the registration payload.

## Bugs

All found by the independent audit of the new code; all fixed same-session,
716 tests green, redeployed (PID 75908, 16:17:49):

1. **Timed-out request left a wedged HTTP/2 session pooled** (`apns.ts`) —
   subsequent sends would queue 10s stalls behind the same dead TCP path.
   Fixed: timeout now evicts + destroys the session; retry dials fresh.
2. **Session leak when `session.request` throws** (`apns.ts`) — un-pooled
   without destroy. Fixed with the same `evict()`.
3. **Permanent non-410 rejection livelock** (`watcher.ts`) — all-accepted
   advancement + an unprunable `400 DeviceTokenNotForTopic` = re-send every
   2s forever. Fixed: that reason now prunes like a 410 (sender-side 403s
   deliberately excluded); pinned by a new test.
4. (Pre-existing, observed live at 08:11:36Z, not fixed): a `client-ended`
   landing between a tick's decide and its sends is clobbered by that tick's
   state advancement. Harmless churn; predates this change.
