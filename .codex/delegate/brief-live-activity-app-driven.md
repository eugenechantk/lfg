# Delegation Brief: app-driven Live Activity (fix staleness #1, host labels #2, drop conn line #3)

## Why
The fleet Live Activity is currently updated only by the server pushing APNs. That's
why it goes stale: (a) the server keeps "which activity is live" in an in-memory map
wiped on every restart → after a restart it never sends `end`, so the card is frozen
on "running"; (b) APNs delivery has ~1% intermittent drops. The fix: **make the app
drive the Live Activity from its own live session state** while it's running, and
harden the server fallback. The app knows sessions in real time, the host DISPLAY
labels (fixes #2), and per-host reachability.

Read first: `.claude/brainstorm/live-activity-redesign.md`. Prior briefs:
`.codex/delegate/brief-live-activity-fleet.md`, `brief-live-activity-host-status.md`.

## Conventions
iOS: put logic reasonable-about-without-the-runtime in `LFGCore` with a test; app
target is the thin shell. Swift 6 strict concurrency, `@MainActor` where the store is.
Server: Bun/TS, `bun test`. Lenient Codable (optional-with-default). Don't reformat
unrelated code. Do NOT build the iOS app / run a sim — Claude does FlowDeck build +
visual verification.

## Part A — App drives the Live Activity (the core fix)

Add an app-side controller that turns `SessionStore` state into Live Activity
start/update/end, so updates are instant and correct whenever the app is running or
background-active (no dependence on server APNs or its restart state).

### Data the app already has (in `ios/LFG/SessionStore.swift`, `@MainActor @Observable`)
- `sessions: [Session]` — all sessions.
- `busy: [String: Bool]` — per-session working state.
- `prompts: [String: AgentPrompt]` — non-nil ⇒ that session needs input (blocked).
- `host(forSession id: String) -> Host?` — the owning host; **`Host.label`** is the
  display name (`LFGCore/HostConfig.swift`) — use it for the row host pill (fixes #2).
- `reachabilityByHost: [String: Reachability]` — `== .ok` ⇒ online.
- `settings.hosts` (each `Host` with `.id`, `.label`).

### Fleet snapshot → ContentState (pure; put the mapping in LFGCore with a test)
Add a pure function that, given the relevant inputs, produces `LFGFleetAttributes.ContentState`:
- A session's state: `prompts[sid] != nil` ⇒ `"blocked"` (needs input); else
  `busy[sid] == true` ⇒ `"working"`; else `"idle"`.
- `rows`: sessions whose state is working/blocked → `{ sid, title, host: <Host.label>,
  state, since }`. Order blocked-first then working, oldest-`since` first, cap 3.
  Preserve `since` across recomputes when a row's (sid,state) is unchanged (pass the
  prior rows in), else `now`.
- `working` = count busy (not blocked); `needsInput` = count blocked.
- `hosts`: for each `settings.hosts` that owns a shown/active session (or all configured
  hosts), `{ name: host.label, online: reachabilityByHost[host.id] == .ok }`.
- `updatedAt = now`.
Because the app builds rows from `Host.label`, the host pills now show the DISPLAY
name — #2 fixed. Because `hosts[].online` comes from real reachability, the pill offline
(orange ⚠) state is now truthful.

### The controller (`ios/LFG/` — e.g. `FleetActivityController.swift`, `@MainActor`)
- Holds a weak ref to `SessionStore` + `AppSettings`; wired up in `LFGApp.init`/configure
  next to `LiveActivityManager`.
- **Observe** the fleet-relevant store state with a re-arming `withObservationTracking`
  loop (reads `sessions`, `busy`, `prompts`, `reachabilityByHost`); on any change,
  recompute the snapshot and `sync()`, then re-arm. Also `sync()` on app foreground
  (scenePhase `.active`, wired in `RootView`) and after store refreshes.
- **sync()** (iOS 17.2+, guard `ActivityAuthorizationInfo().areActivitiesEnabled`):
  - Find the current fleet activity via `Activity<LFGFleetAttributes>.activities.first`.
  - `activeTotal = working + needsInput`.
  - If `activeTotal > 0` and no activity → `Activity.request(attributes: .init(fleetId:"fleet"),
    content: .init(state: snapshot, staleDate: nil), pushType: nil)`. (Local start — the
    app owns it while alive; still register for push tokens via the existing
    `LiveActivityManager` path so the server can update it when the app is suspended.)
  - If activity exists and `activeTotal > 0` and content changed → `await activity.update(.init(state: snapshot, staleDate: nil))`.
  - If activity exists and `activeTotal == 0` → `await activity.end(.init(state: snapshot, staleDate: nil), dismissalPolicy: .immediate)`.
  - Coalesce rapid changes (e.g. skip if snapshot equals last-synced snapshot; a tiny
    debounce is fine). Content equality = same counts + same rows (sid,title,host,state) + same hosts.
- The existing `LiveActivityManager` push-token registration STAYS (push-to-start +
  update token) so the server can still drive the card when the app is fully suspended.
- Keep the existing DEBUG `LFG_LA_MOCK` hook working (it can bypass the controller).

**Coordination note (keep simple):** app-driven updates and server push updates can
both target the one activity. While the app is alive its frequent `update()`/`end()`
is authoritative and converges the card; the server is the fallback when the app is
suspended. Don't build a locking protocol — just let the app's updates win when alive.

## Part B — Harden the server fallback (small)
In `src/push/watcher.ts` the fleet `active` map is in-memory (`const active = new Map()`
in `startPushWatcher`) so a restart orphans a live card (never sends `end`). Persist it:
- Write the single fleet `LiveActivityActive` (startedAt + last contentState) to a small
  JSON file under `PATHS.data` (e.g. `fleet-activity-state.json`), updated whenever the
  decision changes it; load it on `startPushWatcher` so `active` survives restarts.
- Keep it minimal + defensive (missing/corrupt file → empty, same as the token store).
- Add/adjust a unit test.

## Part C — Widget: drop the connection line (#3)
In `ios/LFGWidgets/LFGSessionActivityWidget.swift`:
- Remove the header line-2 connection-status text (`connectionStatus(...)`) from both
  `FleetHeaderView` and `FleetIslandHeader`. Header becomes just the app icon + summary
  line (`N agents · M need you` / `working`). Keep everything else (host pills with
  offline orange ⚠, rows, overflow) as-is. Remove now-dead `connectionStatus` helper.

## Verification (you run; report exact output)
1. `cd /Users/eugenechan/dev/personal/lfg && bun test src/push/` — green (incl. new persistence test).
2. `cd ios/LFGCore && swift test` — green (incl. the new pure snapshot-mapping test).
   (If SwiftPM sandbox blocks the cache, use `--disable-sandbox` + `CLANG_MODULE_CACHE_PATH`.)
Do NOT build the app target.

## Definition of done
- [ ] Pure fleet-snapshot mapping in LFGCore (+test): correct state classification, ordering,
      cap, since-preservation, host labels, host online from reachability.
- [ ] `FleetActivityController` drives start/update/end from SessionStore while the app is
      alive; wired into app lifecycle; observes store + foreground.
- [ ] Host pills show `Host.label` (display name), not the machine hostname (#2).
- [ ] Server persists the fleet `active` map across restarts (#1 fallback), with a test.
- [ ] Widget header line-2 connection text removed (#3).
- [ ] `bun test src/push/` and LFGCore `swift test` green.

## Report back
Files changed, exact test output, and any interface shaped differently from this brief.
