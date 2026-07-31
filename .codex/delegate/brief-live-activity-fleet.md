# Delegation Brief: single "fleet" Live Activity (replace per-session)

## Goal
Replace the current **per-session** Live Activity (N running sessions → N lock-screen
cards) with **one** Live Activity that summarizes all running + needs-input sessions
across every host. Full design + mockup: `.claude/brainstorm/live-activity-redesign.md`
and `.claude/feature/live-activity-redesign-mockup.png`. Read those first.

## Context you need (this is an lfg repo: Bun/TS server + SwiftUI iOS client)
- **Server** decides Live Activity start/update/end and pushes via APNs. Today's
  logic is per-session in `src/push/watcher.ts` (`reduceLiveActivityTransition`) +
  payload builders in `src/push/liveactivity.ts`. A background watcher polls every 2s.
- **iOS**: `ios/Shared/LFGSessionAttributes.swift` (the `ActivityAttributes`),
  `ios/LFGWidgets/LFGSessionActivityWidget.swift` (the widget UI),
  `ios/LFG/LiveActivityManager.swift` (ActivityKit token registration),
  `ios/LFGCore/Sources/LFGCore/LFGClient.swift` (HTTP client, register-token methods).
- Token store: `src/push/liveactivity-store.ts`. HTTP routes: `src/commands/serve.ts`
  (`/api/push/live-activity/start-token`, `/api/push/live-activity/update-token`).
- **Conventions:** server = Bun + TypeScript, run tests with `bun test`. iOS non-UI
  logic lives in `LFGCore` with tests (`swift test`). Lenient Codable decoding (every
  field optional-with-default in a custom `init(from:)`) — MATCH this for the new model.
  Swift 6 strict concurrency; keep types `Sendable`. Do NOT reformat unrelated code.

## The new data model (must match byte-for-byte across Swift ⇄ TS)
Rename the attributes type `LFGSessionAttributes` → **`LFGFleetAttributes`** (update the
server constant `LIVE_ACTIVITY_ATTRIBUTES_TYPE` to the string `"LFGFleetAttributes"`).

```
Attributes (static): { fleetId: String }         // one activity per install; e.g. "fleet"

ContentState (dynamic):
  working:    Int          // count of sessions currently working (busy)
  needsInput: Int          // count of sessions blocked on a prompt
  rows:       [Row]        // ordered, capped at 3 (see ordering)
  updatedAt:  Double       // epoch seconds

Row:
  sid:   String
  title: String
  host:  String            // host label, e.g. "pro" / "air"
  state: String            // "working" | "blocked" | "idle"
  since: Double            // epoch seconds the row entered its current state (for the timer)
```
Swift `ContentState`/`Row` must be `Codable, Hashable, Sendable` with lenient decoding.

**Row ordering & cap (pure, unit-test it):** sort `blocked` before `working` (drop
`idle` rows entirely), within each group oldest-`since`-first (longest running). Take the
first **3**. `overflowCount = (working + needsInput) − rows.count` (computed in the widget
for the "+N more" line; do not store it).

## Server changes

### `src/push/liveactivity.ts`
- `LiveActivityContentState` becomes the aggregate shape above (working, needsInput, rows,
  updatedAt). `buildStart/buildUpdate/buildEnd` carry it. `attributes` in `buildStart`
  becomes `{ fleetId: string }` (default `"fleet"`). `LIVE_ACTIVITY_ATTRIBUTES_TYPE =
  "LFGFleetAttributes"`.

### `src/push/watcher.ts` — the core refactor
Today `runPushTick` loops sessions and calls the per-session live-activity reducer inside
the loop. Change to: **collect all observations for the tick, then make ONE fleet decision.**
- Keep the existing per-session **alert-push** path (`reduceTransition` → `buildPayload` →
  APNs) EXACTLY as-is. Only the live-activity branch changes.
- Replace `reduceLiveActivityTransition` (per-session) with a pure
  **`reduceFleetLiveActivity`**:
  ```
  input:  observations: Array<{ session: PayloadSessionInput, observed: SessionState }>,
          active: { startedAt, contentState } | null,   // prior fleet activity, if any
          now (seconds), hostName
  output: { action: {event:"start"|"update"|"end", push} | null, nextActive }

  algorithm:
    rows  = observations where observed.busy or observed.promptPresent
            → map to Row{ sid, title(host-clipped), host, state: busy?working:blocked, since }
            → order (blocked-first, oldest-since-first), cap 3
    working    = count(observed.busy && !promptPresent)   // "working" = busy
    needsInput = count(!busy && promptPresent)             // blocked/needs-input
    activeTotal = working + needsInput
    // preserve `since`: if a row's (sid,state) matches the prior contentState row, reuse its since; else now
    content = { working, needsInput, rows, updatedAt: now }

    if activeTotal == 0:
        if active: return end (buildEnd(content, now)), nextActive=null
        else: return no-op, nextActive=null
    if !active: return start (buildStart(content, {fleetId})), nextActive={startedAt:now, content}
    if contentChanged(active.contentState, content): return update (buildUpdate(content)), nextActive={...active, content}
    return no-op, nextActive={...active, content}
  ```
  `working` = busy sessions; classify a session `working` if busy (even if a prompt is also
  present, busy wins → state "working"); `blocked` only if `!busy && promptPresent`. Match
  the existing `liveActivityState` precedence (busy→working, else prompt→blocked, else idle).
- Update tokens are now **fleet-level, not per-session**. In the `liveActivities` deps,
  replace `updateTokensForSession(sid)` with a `fleetUpdateTokens()` that returns ALL
  `activityUpdate` tokens (there is only one fleet activity per device now). The `active`
  map collapses to a single nullable fleet entry (a plain variable or a 1-key map — your call).

### `src/push/liveactivity-store.ts`
- Update tokens no longer carry a `sessionId`. Make `sessionId` optional for the
  `activityUpdate` kind and add `listFleetUpdateTokens()` returning all `activityUpdate`
  tokens. You may keep `listActivityUpdateTokens(sessionId)` or remove it — if you remove it,
  update its test.

### `src/commands/serve.ts`
- `/api/push/live-activity/update-token` no longer requires `sessionId` (drop that 400 check);
  register the token with `kind: "activityUpdate"` and no sessionId.

## iOS changes

### `ios/Shared/LFGSessionAttributes.swift` → rename file/type to `LFGFleetAttributes`
Define the new `LFGFleetAttributes` per the model above (lenient decoding, Sendable).

### `ios/LFGWidgets/LFGSessionActivityWidget.swift`
Rebuild the lock-screen + Dynamic Island views to render the fleet ContentState per the
**mockup** (`.claude/feature/live-activity-redesign-mockup.png`):
- **Lock screen:** header (`lfg` mark + `"{working+needsInput} agents · {needsInput} need you"`,
  amber accent when `needsInput>0` else blue, hosts subtitle, relative updated time) + up to
  3 rows (dot colored by state: blocked→amber, working→blue, idle→gray; title; host meta;
  trailing = "needs input" amber pill when blocked, else elapsed timer from `since`) +
  "+{overflowCount} more" muted line when overflow > 0.
- **Dynamic Island:** compactLeading = status dot (amber if needsInput>0 else blue);
  compactTrailing = count `"{needsInput>0 ? needsInput : working}"` with an amber badge when
  needsInput>0; minimal = one dot (amber if needsInput>0 else blue); expanded = header
  (summary + longest-running elapsed) + top 2 rows.
- Reuse the elapsed-timer approach already in the file (`Text(timerInterval:…)`).

### `ios/LFG/LiveActivityManager.swift`
- There is now ONE activity. `track(activity)` registers its single update token via
  `registerLiveActivityUpdateToken(hex, env)` — **drop the `sessionId` argument** everywhere.
- **Add a DEBUG-only local-start hook for simulator verification** (no APNs round-trip):
  ```
  #if DEBUG
  func startMockFleetActivityIfRequested()   // called at launch
      guard ProcessInfo.processInfo.environment["LFG_LA_MOCK"] == "1"
      guard ActivityAuthorizationInfo().areActivitiesEnabled
      // end any existing fleet activities first, then:
      Activity.request(
        attributes: LFGFleetAttributes(fleetId: "fleet"),
        content: .init(state: <mock ContentState>, staleDate: nil),
        pushType: nil)          // local, no push token needed
  #endif
  ```
  Mock ContentState = 2 needs-input + 2 working across hosts "pro"/"air", exactly like the
  mockup (titles: "redesign live activity widget" (pro, blocked), "fix sendq bracketed paste"
  (air, blocked), "migrate push tokens store" (pro, working, since=now-724s), "reelly ad
  pipeline" (pro, working) → so rows cap shows 3 and overflow "+1 more"). Call
  `startMockFleetActivityIfRequested()` from `LiveActivityManager.configure(...)` (guarded so
  release builds never touch it).
- Confirm `NSSupportsLiveActivities` is already YES in the app Info.plist (the feature exists,
  so it should be) — if missing, add it.

### `ios/LFGCore/Sources/LFGCore/LFGClient.swift`
- `registerLiveActivityUpdateToken(_ hex:env:)` — drop the `sessionId` parameter and stop
  sending it in the JSON body.

### `ios/LFGCore/Tests/LFGCoreTests/LFGClientLiveActivityTests.swift`
- Update the update-token test for the new signature (no `sessionId` in body).

## Verification (you run these; report exact output)
1. `cd /Users/eugenechan/dev/personal/lfg && bun test src/push/` — all green. Add/adjust
   tests in `watcher.test.ts` + `liveactivity.test.ts` for the fleet reducer: start on first
   active session, update on aggregate change, end on all-idle, blocked-first ordering, row
   cap = 3, `since` preservation, needsInput/working counts.
2. `cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test` — all green.
3. Do NOT try to build the iOS app target or run a simulator — Claude will build via FlowDeck
   and visually verify. Just make sure the code compiles logically and the two test suites pass.

## Definition of done
- [ ] `LFGFleetAttributes` (renamed) with the aggregate ContentState, lenient + Sendable.
- [ ] Widget renders header + ≤3 rows + overflow + Dynamic Island per the mockup.
- [ ] Server aggregates per tick into ONE start/update/end decision; alert-push path untouched.
- [ ] Update tokens are fleet-level (no sessionId) end-to-end (client, route, store, watcher).
- [ ] DEBUG `LFG_LA_MOCK=1` launch env starts a representative local fleet activity.
- [ ] `bun test src/push/` and `swift test` (LFGCore) both green; new reducer covered.

## Report back
Files changed, the exact `bun test` + `swift test` output, and anything left incomplete or
any interface you changed differently from this brief (and why).
