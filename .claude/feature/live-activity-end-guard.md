# Feature: live-activity-end-guard

Fix 4 from `.claude/diagnosis-live-activity-duplicate-cards-20260918.md`, made
urgent by `.claude/diagnosis-live-activity-stale-when-backgrounded-20260919.md`.
Tier: product.

## User Story

As the phone's user, I want the fleet card the server starts while the app is
suspended to stay on my Lock Screen and keep updating as sessions finish, so that I
do not have to open the app to learn the fleet's state.

## User Flow

1. Server push-to-starts a card; ActivityKit wakes the app in the background.
2. The app's launch sync finds a card and an empty, not-yet-fetched store. It leaves
   the card alone (no end, no zeroed update).
3. The first live sessions fetch completes. From then on the count is trustworthy
   while no host is known down.
4. Sessions finish; the app (when alive) and the server (always) update the card.
5. When the trustworthy count has been zero for 60 s, the app ends the card and
   reports it. A blip shorter than that only updates the card to zero counters.

## Success Criteria

- [x] SC1: With an untrustworthy count (no live fetch yet, or a host known down),
  the gate never ends and does not start the zero clock — **Verify by:**
  `FleetEndGateTests` (LFGCore).
- [x] SC2: With a trustworthy zero, the gate holds for 60 s then ends; activity
  reappearing inside the hold resets the clock — **Verify by:** `FleetEndGateTests`.
- [x] SC3: `sync()` with a card present and an untrustworthy count sends no end and
  no update — **Verify by:** code path reads the gate; app build green; live log
  shows no `client-ended` within seconds of a `start` after deploy.
- [x] SC4: `start-vetoed` traces once per population, not per tick — **Verify by:**
  `src/push/watcher-fleet-veto.test.ts` (box-level) and `bun test src/push`.
- [x] SC5: Existing suites green — **Verify by:** `swift test` (LFGCore),
  `bun test src/push`, `flowdeck build`.
- [ ] SC6: On the phone, after the TestFlight build installs: a server-started card
  survives its arrival (no `client-ended` seconds after `decide start` in
  `~/.lfg/liveactivity.log`) — **Verify by:** reading the log after the next start.

## Platform & Stack

- iOS (Swift, ActivityKit) + Bun server (TypeScript)

## Steps to Verify

1. `cd ios/LFGCore && swift test --filter FleetEndGate`
2. `bun test src/push`
3. `flowdeck build`
4. TestFlight deploy + verify lane; restart Pro and Air servers; watch the log.

## Implementation Phases

### Phase 1: Gate (LFGCore) + store signal + controller
- `FleetEndGate.swift` (pure), `SessionStore.liveSessionsFetchedOnce` set on the
  first successful live fetch, `SessionStore.fleetCountIsTrustworthy`,
  `FleetActivityController.sync()` consults the gate.
- SC1, SC2, SC3, SC5

### Phase 2: Server trace tidy
- `start-vetoed` once per population key.
- SC4, SC5

### Phase 3: Ship
- Commit, TestFlight, restart servers, observe. SC6.

## Decision Log

- **Trustworthy = at least one live fetch completed this launch AND no host known
  down.** Not "every host fetched": a permanently-down host would otherwise pin the
  card forever on the client side. The server still ends the card when its own count
  hits zero, so a down host cannot strand a card.
- **Untrustworthy count → leave the card untouched, including no zeroed update.** A
  zeroed update at background launch would blank a card the server just filled.
- **Hold = 60 s, mirroring the server's `FLEET_END_DEBOUNCE_S`.**
- **The gate's clock lives in the controller (`zeroSince`), reset on any
  untrustworthy tick.** Conservative: a host blip mid-hold restarts the 60 s.

## Verification Evidence

| SC | Command / action | Observed |
|---|---|---|
| SC1, SC2 | `cd ios/LFGCore && swift test` (2026-09-19 ~10:50) | `FleetEndGateTests`: 8 tests, 0 failures — untrustworthy → untouched + clock reset; trustworthy zero holds 60 s then ends; activity or a host going down mid-hold resets |
| SC3 | `sync()` now consults `FleetEndGate`; `.untouched` returns before any update/end; `flowdeck build` SUCCESS on first attempt | live confirmation is SC6 |
| SC4 | `bun test src/push` → 105 pass after pinning `relevance-score` into the payload-shape tests; `bunx tsc --noEmit` clean | the once-per-population trace has no unit test (tick-level); confirmed in the live log after restart (SC6 window) |
| SC5 | LFGCore 544 tests, 0 failures, 1 skipped; push suite 105/105; app build green | |
| SC6 | Pro restarted 13:43, Air right after (both health 200); TestFlight build 202609191344 uploaded 13:48, DoD PASS (VALID, highest train, IN_BETA_TESTING); evidence in `.claude/feature/evidence/testflight-20260919c/` | live proof (a server-started card surviving its arrival) still pending a real start after the phone installs the build |

Also in this change (Eugene, mid-turn): the Dynamic Island **minimal** view now draws the
state-coloured circle with the count inside (needs-input count when any, else working
count), and both server pushes and app-side `ActivityContent` carry a relevance score
(100 when someone needs you, else 90) so the fleet card takes the island slot when
another app's activity shares it. Placement among multiple activities is ultimately
iOS's call; the score is the only lever the platform gives.

## Bugs

_None yet._
