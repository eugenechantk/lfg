# Feature: live-activity-single-card

Fixes 1 and 2 from `.claude/diagnosis-live-activity-duplicate-cards-20260918.md`.
Tier: product.

## User Story

As the phone's user, I want exactly one fleet Live Activity card on my Lock Screen and
Dynamic Island, so that the card I glance at is the live one and I am not scrolling
past four stale copies of it.

## User Flow

1. Sessions are working; a fleet card exists (created by the app or by a server
   push-to-start).
2. The phone, for whatever reason, ends its card and reports "ended" to the server.
3. The server does NOT immediately push-to-start a replacement for the same
   population of sessions. Only a session that was not active at the time of the
   ended report can justify a new card.
4. If a push-to-start card nevertheless arrives while a card already exists (a
   race, a stale token, a server restart), the app ends every fleet card except the
   most recently updated one, the moment the duplicate appears.
5. At any instant the phone holds at most one fleet card.

## Success Criteria

- [x] SC1: Given N>1 fleet activities, the client keeps the one with the newest
  `updatedAt` and ends the rest — **Verify by:** `FleetActivityDedupeTests` (LFGCore,
  `swift test`) for the pure selection; iOS app build green for the wiring.
- [x] SC2: With no server-side card and a client-ended veto whose population covers
  every currently active session, the reducer sends no `start` — **Verify by:**
  `src/push/watcher-fleet-veto.test.ts` (`bun test`).
- [x] SC3: A session id outside the veto population lifts the veto and a `start` is
  sent — **Verify by:** same test file.
- [x] SC4: An empty/unknown veto population never blocks a start — **Verify by:**
  same test file.
- [x] SC5: Existing watcher and LFGCore suites stay green — **Verify by:** `bun test
  src/push` and `swift test` in `ios/LFGCore`.
- [ ] SC6: On the live Pro server, a `client-ended` is followed by a `start-vetoed`
  trace line (not a `decide start`) when the population is unchanged — **Verify by:**
  restart the server with the new code, wait for the next `client-ended` in
  `~/.lfg/liveactivity.log`, read the following lines. Requires a real phone event;
  may land after this session. Unverified until then.

## Platform & Stack

- **Platform:** iOS client (Swift/ActivityKit) + Bun server (TypeScript)
- **Key frameworks:** ActivityKit, SwiftUI widgets; bun:test; XCTest in LFGCore

## Steps to Verify

1. `cd ios/LFGCore && swift test --filter FleetActivityDedupe`
2. `bun test src/push`
3. `flowdeck build` (iOS app compiles with the new dedupe wiring)
4. Server restart on the Pro by port; watch `~/.lfg/liveactivity.log` for
   `start-vetoed` after the next `client-ended`.

## Implementation Phases

### Phase 1: Client dedupe

- Scope: `ios/LFGCore/Sources/LFGCore/FleetActivityDedupe.swift` (pure selection),
  `ios/LFG/LiveActivityManager.swift` (end the losers on launch and on every
  `activityUpdates` yield).
- Success criteria covered: SC1
- Verification gate: LFGCore tests green, app build green.

### Phase 2: Server change-gated restart

- Scope: `src/push/watcher.ts` — the fleet box carries `lastPopulation` (every
  active sid from the last tick) and `clientEnded` (the population at the moment the
  phone reported ended). `reduceFleetLiveActivity` refuses to `start` while every
  active sid is inside `clientEnded.population`; a successful start or an
  update-token registration clears the veto. New trace event `start-vetoed`.
- Success criteria covered: SC2, SC3, SC4, SC5
- Verification gate: `bun test src/push` green.

### Phase 3: Deploy and observe

- Scope: restart the Pro's server (by port, after `bun install --frozen-lockfile`
  is not needed here — no package change). Observe the log.
- Success criteria covered: SC6

## Decision Log

- **Veto lives in memory, not on disk.** A server restart forgets it, costing at most
  one extra start after a restart. Persisting it means changing the
  `LiveActivityActive` file shape for a rare case. Alternative rejected for now.
- **Veto population = every active sid, not the rendered rows.** `since` already
  tracks every active session; rows are capped at 3.
- **Survivor = newest `updatedAt`, tie → larger id.** ActivityKit exposes no creation
  time; `updatedAt` is what the server and app both stamp. The tie-break is
  deterministic across calls, unlike `activities` order.
- **Dedupe runs in `LiveActivityManager`, not `FleetActivityController`.** The
  manager already owns the `activityUpdates` stream where a push-started card first
  appears; the controller only runs on foreground sync.
- **New test file rather than editing `watcher.test.ts`.** That file is dirty with
  another session's in-flight work.
- **Veto is not cleared on `client-ended` with an unknown population.** If the
  phone reports ended before the server ever ticked, `lastPopulation` is empty and
  the veto is empty, which blocks nothing (SC4).

## Verification Evidence

| SC | Command / action | Observed | Artifact |
|---|---|---|---|
| SC1 | `cd ios/LFGCore && swift test --filter FleetActivityDedupe` (2026-09-19 00:19) | 5 tests, 0 failures: single card kept, empty input, newest `updatedAt` wins regardless of order, tie → larger id in both orders, survivor never in the end list | terminal |
| SC1 wiring | `flowdeck build` (2026-09-19 00:24) | first attempt failed with Swift 6 `sending 'activity' risks causing data races` at the dedupe loop; restructured into a static lookup-and-consume helper; second build `SUCCESS` | `~/.flowdeck/logs/d926691c10b8/build.log` |
| SC2, SC3, SC4 | `bun test src/push/watcher-fleet-veto.test.ts` | 8 pass, 0 fail (covered-population veto, subset veto, new sid lifts veto, empty veto, no veto, veto ignored while a card is tracked, empty fleet under veto not vetoed, population reported) | terminal |
| SC5 | `bun test src/push` → 105 pass / 0 fail across 7 files; `bunx tsc --noEmit -p .` → clean; `cd ios/LFGCore && swift test` → 536 tests, 0 failures, 1 skipped | terminal |
| SC6 | not run — needs the Pro server restarted and a real phone `client-ended` event | pending Eugene's go on the restart (23 tmux sessions live; 0 waiting phone sign-ins; server process from Sep 17 14:38 also carries another session's uncommitted watcher edits, whose tests pass) |

Auditor: skipped. Both changes are internal (a pure reducer and a boundary that only
acts when ActivityKit reports two cards); the only user-observable effect needs a
real APNs event on a real phone, which no auditor can drive. SC6 is the live check.

Checked: SC1–SC5. SC6 stays unchecked until observed in `~/.lfg/liveactivity.log`.

## Bugs

_None yet._
