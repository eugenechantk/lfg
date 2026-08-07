# Feature: live-activity-background-freshness

Fixes the defect diagnosed in
[`.claude/diagnosis-live-activity-background-updates.md`](../diagnosis-live-activity-background-updates.md).

## User Story

As someone running a fleet of agent sessions from my phone, I want the Live
Activity card to stay truthful while the app is closed, so that I can trust the
Lock Screen counter instead of opening the app to find out what is really running.

## User Flow

1. Several sessions are working; the Lock Screen card shows the correct counts.
2. The user locks the phone and leaves the app suspended.
3. Sessions finish, one by one. **The card's counter drops each time**, within a
   watcher tick.
4. Every session finishes. The card ends and disappears.
5. A new session starts while the app is still suspended. **A card reappears**
   showing it.
6. At no point does the user need to open the app for the card to be correct.

## Success Criteria

- [ ] **SC1**: The push watcher and the journal agree on `busy` for every session
      — the watcher no longer counts a session working after its turn ends or
      stalls. — **Verify by:** unit test pinning `observeSession`'s busy chain to
      `sessionTurnState` (hooks + transcript + stall demotion), plus a live
      run of `scratchpad/watch-drift.sh` showing journal-busy and card-working
      equal across ≥3 minutes of real session churn.
- [ ] **SC2**: A stalled session (transcript says `running`, nothing written for
      > `STALL_MS`) is **not** counted as working by the watcher. — **Verify by:**
      unit test with a synthetic transcript + injected clock past `STALL_MS`.
- [ ] **SC3**: Registering a new `activityUpdate` token supersedes the previous
      one for that env — the store never accumulates dead tokens. — **Verify by:**
      unit test in `liveactivity-store.test.ts`; plus
      `jq '[.[]|select(.kind=="activityUpdate")]|length'` on the live store
      returning 1 per env after a client re-registration.
- [ ] **SC4**: When the client ends the fleet card, the server learns about it and
      clears `active.current`, so the next active session triggers a **push-to-start**
      rather than an update into a dead activity. — **Verify by:** unit test on
      the new endpoint + `runPushTick` emitting `start` after the card is
      reported ended; plus live check that `fleet-activity-state.json` is cleared.
- [ ] **SC5**: A scratch/secondary `lfg serve` does not push to real devices. —
      **Verify by:** unit test on the gate; plus starting a server on a non-default
      port and confirming no APNs traffic from it.
- [ ] **SC6**: No regression — the existing push/live-activity suites stay green.
      — **Verify by:** `bun test src/push/`.

## Platform & Stack

- **Platform:** Bun/TypeScript server + iOS (SwiftUI, ActivityKit)
- **Language:** TypeScript, Swift 6
- **Key frameworks:** Bun, node:http2 (APNs), ActivityKit, SwiftUI

## Steps to Verify

1. `bun test src/push/` — server unit tests.
2. `cd ios/LFGCore && swift test` — client core tests.
3. Restart the primary server, then run `scratchpad/watch-drift.sh` and confirm
   journal-busy and card-working track each other.
4. Drive a real end→start cycle with the app suspended and confirm the card
   disappears and reappears without opening the app.

## Implementation Phases

### Phase 1: One owner for `busy` (server)

- Scope: `observeSession` in `src/push/watcher.ts` switches from
  `transcriptTurnState` to `sessionTurnState`, matching `journal-pump.ts:395`.
- Success criteria covered: SC1, SC2
- Verification gate: new unit tests + `bun test src/push/` green + live drift
  monitor clean.

### Phase 2: Token hygiene + delivery honesty (server)

- Scope: `activityUpdate` tokens supersede per env in `liveactivity-store.ts`.
- Success criteria covered: SC3
- Verification gate: `bun test src/push/` green; live store shows one token/env.

### Phase 3: Client reports card lifecycle (server + iOS)

- Scope: new `POST /api/push/live-activity/ended`; `FleetActivityController`
  calls it when it ends the card; watcher clears `active.current` on receipt.
- Success criteria covered: SC4
- Verification gate: unit tests + live end→start cycle with app suspended.

### Phase 4: Scratch servers don't push (server)

- Scope: gate `startPushWatcher` so only the primary server pushes.
- Success criteria covered: SC5
- Verification gate: unit test + non-default-port server sends nothing.

## Decision Log

- **Fix the watcher to call `sessionTurnState` rather than have it read the
  journal's emitted `busy`.** Alternative considered: subscribe the watcher to
  the journal so there is literally one computation. Rejected for now — the
  journal pump and the push watcher tick independently and the pump's values are
  keyed to delta-emission, not to a queryable current-state map; sharing the
  *derivation function* gets identical results with a one-line change and no new
  coupling. Noted as a follow-up if they drift again.
- **Supersede `activityUpdate` tokens per `env`, not per device.** The
  registration payload carries no device identifier, and the store's own comment
  states there is exactly one fleet Live Activity per device. Per-env supersede
  is correct for the single-device case and is the shipped reality. A second
  device on the same env would fight over the slot — recorded as a known
  limitation rather than inventing a device-id protocol in a bug fix.

## Verification Evidence

Run 2026-08-07, `Eugenes-MacBook-Pro`.

| Criterion | Method | Result |
| --- | --- | --- |
| SC1 (unit) | `bun test src/session-state.test.ts` — `resolveBusy` behaviour + both call sites | **PASS** 24 pass / 0 fail |
| SC1 (structural) | `bun test src/session-state-parity.test.ts` — pins `journal-pump.ts` and `push/watcher.ts` to `sessionTurnState` + `resolveBusy`, forbids reaching past to `transcriptTurnState` | **PASS** 11 pass / 0 fail |
| SC1 (live) | `scratchpad/probe-drift-fixed.ts` — new derivation vs the running server's journal busy, across every pane-backed session | **PASS** — `checked=3 drift(old)=0 drift(NEW)=0`. Weak on its own: no session happened to be stalled at that moment, which is why SC2's corpus scan below carries the real weight. |
| SC2 | `bun test src/session-state.test.ts` — stalled verdict (`assistant` record, mtime past `STALL_MS`) → `resolveBusy` false | **PASS** |
| SC2 (real corpus) | `scratchpad/probe-stalled-corpus.ts` over all 275 real transcripts in `~/.claude/projects` | **PASS** — 47 transcripts read "running" but are stale past `STALL_MS` (oldest idle 29 days). **Old watcher counted all 47 busy; new watcher counts 0.** This is the "counter keeps increasing" report, quantified. |
| SC3 | `bun test src/push/liveactivity-store.test.ts` — supersede per env, envs independent, `pushToStart` exempt, same-token refresh, dual-kind token | **PASS** 14 pass / 0 fail |
| SC3 (live HTTP) | isolated scratch server (`LFG_DATA` temp dir, no real tokens): registered update tokens A then B on `production` → store kept only B; a `sandbox` token coexisted; the `pushToStart` token survived | **PASS** — store ended as `[cccc3333 update/prod, eeee5555 update/sandbox, 9999aaaa start/prod]` |
| SC4 | `bun test src/push/watcher.test.ts` — update-while-live vs start-after-ended, `noteFleetActivityEnded` clears disk, adoption prevents a duplicate card | **PASS** |
| SC4 (live HTTP) | seeded `fleet-activity-state.json`, then `POST /api/push/live-activity/ended` | **PASS** → `{"ok":true}` and the state file was unlinked |
| SC5 | `bun test src/push/watcher.test.ts` — `pushWatcherEnabled` port gate + both overrides | **PASS** |
| SC5 (live) | same scratch server with **real APNs creds** (`configured:true`) on port 8799: `[push] watcher started` count = **0**; re-run with `LFG_PUSH_WATCHER=1` → count = **1** | **PASS** — a scratch server cannot push |
| SC6 | `bun test` (whole server suite) | **PASS** 385 pass / 0 fail |
| Build (server) | `npx tsc --noEmit -p tsconfig.json`, filtered to touched files | **PASS** no errors |
| Build (client core) | `cd ios/LFGCore && swift build && swift test` | **PASS** 11 tests / 2 suites |
| Build (app) | `flowdeck build --scheme LFG --simulator "iPhone 17 Pro"` | **PASS** Build Completed |

## Deployed 2026-08-07

Committed as `ee8b056`, pushed to `main`.

**Server** — restarted and confirmed running the new code:

- `POST /api/push/live-activity/ended` → **200** (returned 404 before the restart,
  which is the cleanest proof the new build is live).
- The token store collapsed from **8** `activityUpdate` tokens to **1** the moment
  the client re-registered — the supersede working on real data.
- **SC1 in production:** card and journal now agree exactly —
  card `working=1 rows=[284eede0]` vs journal `busy count=1 [284eede0]`.

**Client** — TestFlight build **202608071032** on train **1.2.0**, built from a
clean worktree at `ee8b056` (the working tree held other agents' in-flight code
that must not ship). `fastlane ios verify_testflight_build` DoD: ipa ground truth
OK → `VALID` → highest train → `internalBuildState=IN_BETA_TESTING`.

## Still unverified

**End-to-end device behaviour** — user flow steps 3–5 (counter drops as sessions
finish, card ends, card reappears while the app stays suspended). This needs
Eugene's phone with build 202608071032 installed and a real backgrounded run; a
simulator cannot receive APNs pushes. Everything it depends on is verified
individually above.

## Bugs

_None open._
