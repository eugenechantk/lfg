# Feature: iOS Push Notifications for Session Events

## User Story

As an lfg user driving Claude/Codex agents from my phone, I want my native iOS/iPadOS
app to push me a notification when a session **finishes its turn** or **needs my input**,
so that I can step away from the app and still be pulled back the moment an agent is
waiting on me — without keeping the app open.

## User Flow

1. User installs the lfg iOS app and configures the server host (existing flow).
2. On first launch (or from Settings), the app requests notification permission.
3. On grant, the app registers for remote notifications, obtains an APNs device
   token, and POSTs it to `lfg serve` (`/api/push/register`).
4. The user backgrounds/closes the app and goes about their day.
5. A session the server is tracking transitions:
   - **Agent stops working with a pending prompt** → push: _"Needs you — <session>: <question>"_
   - **Agent stops working, turn complete, no prompt** → push: _"Finished — <session>"_
6. Tapping the notification deep-links into that session's detail view.
7. User can mute/unmute notifications globally (and optionally per category) from Settings.

## Success Criteria

- [ ] SC1: A registered device receives an APNs push within ~5s of a tracked session's
  agent stopping with a pending prompt. — **Verify by:** integration test driving the
  server watcher with a synthetic transcript/pane that flips to a prompt state; assert the
  APNs sender is invoked with the correct payload (sender mocked). Plus one real end-to-end
  device test (manual, screenshot of lock-screen banner).
- [ ] SC2: A registered device receives a "finished" push within ~5s of a tracked session's
  agent stopping its turn with no pending prompt. — **Verify by:** integration test (busy
  true→false, no prompt) asserting payload; manual device screenshot.
- [x] SC3: No duplicate/notification storm — a single stop emits exactly one push (done OR
  needs-input, never both), and a session that stays idle emits nothing on subsequent polls.
  — **Verify by:** unit test of the transition/dedup reducer over a scripted state sequence.
- [x] SC4: `POST /api/push/register` persists the device token (deduped by token) and
  `POST /api/push/unregister` removes it; tokens survive a server restart. — **Verify by:**
  API test (curl register → inspect store file → restart → still present → unregister → gone).
- [ ] SC5: Tapping a notification opens the app to the corresponding session detail view.
  — **Verify by:** manual device test with screenshot; unit test of the deep-link/route
  reducer that maps a notification payload's `sid` to the selected session.
- [ ] SC6: Notification permission flow works — denied permission degrades gracefully (no
  crash, Settings shows disabled state), granted permission registers a token. — **Verify
  by:** manual device test + LFGCore unit test of the registration state machine.
- [x] SC7: Existing behavior is unchanged when no devices are registered and when push is
  not configured (no APNs key) — the watcher is a no-op and `lfg serve` runs as today.
  — **Verify by:** server starts and serves with `LFG_APNS_*` unset; existing tests green.

## Platform & Stack

- **Server:** Bun + TypeScript (`src/commands/serve.ts`, new `src/push/`). APNs over
  HTTP/2 with **token-based auth (.p8 JWT, ES256)** — no certs. Bun has HTTP/2 client +
  WebCrypto/`crypto.sign` for ES256, so no third-party push lib required.
- **iOS:** SwiftUI app (`ios/LFG`), `LFGCore` SPM package. `UNUserNotificationCenter` +
  `UIApplicationDelegate` remote-notification registration. New `PushManager` in the app
  target; payload/route models in `LFGCore`. Push Notifications capability + `aps-environment`
  entitlement via `project.yml` (XcodeGen).
- **Team:** 39GJBP8V5A · **Bundle id:** dev.omg.lfg.

## Server-side Design

### Device registry (`src/push/store.ts`)
- JSON file under `PATHS.data` (e.g. `data/push-devices.json`), mirroring `src/auto/store.ts`.
- Record: `{ token, platform: "ios", env: "sandbox"|"production", owner?: string|null, mutedCategories?: string[], createdAt, lastSeenAt }`.
- Deduped by `token`. Register upserts; unregister deletes. APNs "BadDeviceToken"/410
  responses prune the token automatically.

### Always-on session watcher (`src/push/watcher.ts`)
- A single interval loop started by `lfg serve` (only when `LFG_APNS_*` configured AND ≥1
  device registered). Independent of any client SSE connection.
- Each tick (~2s): `listSessions()`, and for each session reuse the **existing** detection
  primitives already in `serve.ts`/`sessions.ts`:
  - `capturePane(target)` + `isBusy(pane)` → busy
  - `resolveSessionPrompt(tp, pane)` → pending prompt (null/non-null)
  - pane-less (aisdk/codex) sessions: busy from the registry, as the SSE loop already does.
- Maintain per-session prior state `{ busy, promptPresent, lastNotifiedAt }`.
- **Transition rule (the reducer, unit-tested in isolation):**
  - `busy: true → false`: agent stopped. If a prompt is present → **needs-input** push;
    else → **finished** push.
  - `promptPresent: false → true` while already idle (prompt can land a tick after busy
    flips) → **needs-input** push, deduped against a needs-input/finished already sent for
    this stop within a short window (e.g. 10s).
  - Debounce: ignore stops where the session was never observed busy (avoids start-up noise),
    and coalesce so one stop = one push.
- On a qualifying transition, fan out an APNs push to all registered devices (subject to
  targeting + mute — see Decision Log).

### APNs sender (`src/push/apns.ts`)
- Build an ES256 JWT from `LFG_APNS_KEY` (.p8 contents or path), `LFG_APNS_KEY_ID`,
  `LFG_APNS_TEAM_ID`; cache it (~50 min TTL).
- HTTP/2 POST to `api.development.push.apple.com` (sandbox) / `api.push.apple.com`
  (production) per device `env`, path `/3/device/<token>`, headers `apns-topic: dev.omg.lfg`,
  `apns-push-type: alert`, `authorization: bearer <jwt>`.
- Payload: `{ aps: { alert: { title, body }, sound: "default", "thread-id": sid }, sid, kind }`.
- Handle 410 / BadDeviceToken → prune device from store. Surface other errors to a log only.

### New endpoints (`src/commands/serve.ts`)
- `POST /api/push/register` — body `{ token, env, owner? }` → upsert; start watcher if idle.
- `POST /api/push/unregister` — body `{ token }` → delete.
- `GET /api/push/health` (optional) — returns `{ configured: bool, devices: n }` for the app
  to show registration status in Settings.

### Configuration (`.env`)
| Var | Purpose |
| --- | --- |
| `LFG_APNS_KEY` | .p8 contents or path to the APNs Auth Key |
| `LFG_APNS_KEY_ID` | Key ID of the .p8 |
| `LFG_APNS_TEAM_ID` | Apple Team ID (39GJBP8V5A) |
| `LFG_APNS_TOPIC` | bundle id (default `dev.omg.lfg`) |
| `LFG_APNS_ENV` | default env for new devices (`sandbox`/`production`) |

## iOS Design

- **Capability:** add `aps-environment` entitlement + Push Notifications + Background Modes
  (remote-notification optional) in `project.yml`; XcodeGen regenerates the project.
- **`PushManager` (app target):** `UNUserNotificationCenterDelegate` + app-delegate adaptor
  (`UIApplicationDelegateAdaptor`) for `didRegisterForRemoteNotificationsWithDeviceToken` /
  `didFailToRegister`. Requests authorization, registers, POSTs the token via `LFGClient`.
- **`LFGClient` (LFGCore):** add `registerPush(token:env:owner:)` / `unregisterPush(token:)`.
- **Routing:** `UNUserNotificationCenterDelegate` reads `sid` from the payload and tells the
  store/RootView to select that session (foreground present-as-banner; tap → navigate).
- **Settings:** a notifications section — permission status, enable/disable, re-register.

## Steps to Verify

1. Server: `bun test` (new push reducer/store/api tests) + `bun run serve` boots with and
   without `LFG_APNS_*`.
2. iOS: `cd ios && xcodegen generate && flowdeck build`; `cd ios/LFGCore && swift test`.
3. Register a real device, background the app, start a session that asks a question →
   observe lock-screen push (screenshot). Let a session finish a turn → observe push.
4. Tap a push → app opens to that session (screenshot).

## Implementation Phases

### Phase 1: Server push infrastructure (no device needed)
- Scope: `src/push/{store,apns,watcher}.ts`, register/unregister/health endpoints, env wiring,
  start/stop the watcher from `serve`. APNs sender unit-tested with a mocked HTTP/2 transport.
- SCs: SC3 (reducer), SC4 (registry), SC7 (no-op when unconfigured).
- Gate: `bun test` green; `bun run serve` boots both configured and unconfigured.

### Phase 2: iOS registration + handling
- Scope: entitlements via project.yml, `PushManager`, `LFGClient` push methods, Settings UI,
  notification tap → route reducer.
- SCs: SC5 (route reducer unit test), SC6 (registration state machine unit test).
- Gate: `swift test` green; app builds; permission prompt appears in simulator.

### Phase 3: End-to-end on device
- Scope: wire real APNs creds, register a real device, exercise both event types + tap-through.
- SCs: SC1, SC2, SC5 (manual), SC6 (manual) — captured as screenshots.
- Gate: verification-auditor / manual evidence with screenshots.

## Decision Log

- **APNs token-based (.p8) auth over certificate auth.** .p8 keys don't expire, one key
  covers all the team's apps and both environments, and JWT signing is a few lines with
  Bun's crypto — vs. p12 certs that expire yearly and need per-app/per-env management.
  _Eugene must create the APNs Auth Key in the Apple Developer portal — see Prerequisites._
- **Remote push (APNs), not local notifications.** Local `UNNotificationRequest` only fires
  while the app is alive; iOS suspends the app shortly after backgrounding, so "notify when a
  session is done" while the phone is in a pocket is impossible without remote push.
- **One push per stop, classified done-vs-needs-input.** "Done" and "needs input" both mean
  "the agent wants you," and they happen at the same moment (busy→false). Sending both would
  double-notify. The reducer emits exactly one, choosing needs-input when a prompt is present.
- **Notify on every turn completion, not only session end.** lfg has no distinct "session
  finished forever" state — an agent that stops is waiting for you. Each busy→false is a
  legitimate "your turn" moment. (Open question below if this proves noisy.)
- **Watcher reuses existing detection, runs only when needed.** Same `capturePane`/`isBusy`/
  `resolveSessionPrompt` the SSE loop uses; the loop only runs when push is configured and
  devices exist, so unconfigured installs pay nothing (SC7).

## Resolved Decisions (Eugene, 2026-06-28)

1. **Events:** needs-input **and** finished (turn complete). One push per stop, classified.
2. **Targeting:** all sessions → all registered devices. No owner filtering in v1 (the
   `owner` field is still stored for a future filter, but the watcher fans out to all).
3. **Blocked:** out of scope for v1.
4. **Credentials:** build Phases 1–2 now with a mocked APNs transport; Eugene provides the
   .p8 / Key ID / Team ID and the Push capability later for the Phase 3 device test.

## Prerequisites (Eugene-provided, external)

- Apple Developer portal: create an **APNs Auth Key (.p8)**, note its **Key ID**; enable the
  **Push Notifications** capability for App ID `dev.omg.lfg`.
- Put `LFG_APNS_KEY` (.p8 path/contents), `LFG_APNS_KEY_ID`, `LFG_APNS_TEAM_ID=39GJBP8V5A`
  into the server `.env`.
- For a Debug build run from Xcode, devices use the **sandbox** APNs host; TestFlight/App
  Store builds use **production**. The app sends its `env` at registration accordingly.

## Verification Evidence

### Phase 1 — server infra (2026-06-28)

- **SC3 (reducer/dedup):** `bun test src/push/` → 26 pass / 0 fail. `watcher.test.ts`
  covers busy→idle→finished, busy→idle+prompt→needs-input, still-working→silent,
  idle-stays-silent, prompt-while-idle→needs-input, finished+late-prompt dedup within
  window (no double), and prompt-after-window fires. Plus `runPushTick` fan-out, dead-token
  prune, and no-devices no-op.
- **SC4 (registry):** `store.test.ts` (temp-file isolated) — empty list, register+dedupe by
  token (env updates, owner preserved), survives re-read (restart), unregister removes.
  Live API check: boot `lfg serve` (no APNs) → `POST /api/push/register {token,env,owner}`
  → `{ok:true,env:"sandbox"}`; `/api/push/health` → `devices:1`; bad token → `400 invalid
  token`; `POST /api/push/unregister` → `{ok:true}`.
- **SC7 (no-op when unconfigured):** boot without `LFG_APNS_*` → server serves, health
  `{configured:false}`, watcher does not start, register still works. Boot WITH a throwaway
  P-256 .p8 + key id + team → health `{configured:true}`, log `[push] watcher started`.
  `bunx tsc --noEmit` clean for `src/push/*` (the two serve.ts errors are pre-existing Bun
  typing quirks in untouched code).
- **SC1/SC2 (server half):** `runPushTick` tests assert the correct payload (`finished` /
  `needs-input` with the question text) is sent to every registered device on the
  transition. Full on-device delivery is Phase 3.

### Phase 2 — iOS (2026-06-28)

- **SC5 (routing) + SC6 (registration), unit half:** `cd ios/LFGCore && swift test` → 24
  pass / 0 fail (was 15; +9 push tests in `PushTests.swift`, run reports 8 methods + the
  rest). Covers `PushNotification(userInfo:)` sid/kind extraction + rejection of missing
  sid (SC5 route reducer), `apnsTokenHex`, and the `reducePushRegistration` state machine:
  happy path → `.registered`, denied, server-failure surfaces reason, denial-after-register
  deactivates (SC6). _Manual device half (permission prompt + tap-through screenshots) is
  Phase 3._
- **App compiles:** `flowdeck build -S <sim>` → **Build Completed** with the full push
  wiring (entitlement, `PushManager`, `AppDelegate` adaptor, `LFGClient.registerPush`,
  Settings `NotificationStatusRow`, RootView `requestedSelection` routing). Swift 6 strict
  concurrency clean after marking the `UNUserNotificationCenterDelegate` methods
  `nonisolated` and parsing the Sendable `PushNotification` before the main-actor hop.

  ⚠️ A later `flowdeck run` failed to rebuild because a **concurrent edit by another lfg
  session** to `SessionStore.swift` (the optimistic-create feature, which consumes this
  feature's new `requestSelection`) introduced an unrelated compile error:
  `LFGError.http(0, …)` should be `LFGError.http(status: 0, body: …)` (~line 532). Left for
  the owning session to fix — not part of this feature. Once that lands, the on-sim run +
  permission-prompt screenshot can be captured.

### Phase 3 — on-device E2E (2026-06-29)

**APNs credentials provisioned (via Apple Developer portal, driven through Chrome):**
- APNs Auth Key `lfg APNs`, **Key ID `39853G64CJ`**, Environment **Sandbox & Production**,
  **Team Scoped (All Topics)**. `.p8` stashed at `~/.lfg/AuthKey_39853G64CJ.p8` (chmod 600).
- App ID **`dev.omg.lfg`** registered with **Push Notifications** capability enabled (was a
  wildcard-only team before).
- Host `.env` wired: `LFG_APNS_KEY` (path), `LFG_APNS_KEY_ID=39853G64CJ`,
  `LFG_APNS_TEAM_ID=39GJBP8V5A`, `LFG_APNS_TOPIC=dev.omg.lfg`. `serve-forever` restarted →
  `/api/push/health` = `{"configured":true,"devices":1}`.

**SC1/SC2 server→APNs delivery — VERIFIED LIVE:** a real `sendApns` to the registered
sandbox device returned **`{ok:true,status:200}`** — Apple accepted the push. This exercises
the full chain: ES256 JWT signed from the real `.p8`, topic `dev.omg.lfg` matching the
Push-enabled App ID, and a real device token over HTTP/2.

> **Bug found & fixed by the live test (Decision Log):** the original `realTransport` used
> `fetch`, which fails against APNs with `Malformed_HTTP_Response` (Bun 1.3.x can't handle
> APNs's HTTP/2-only responses). Rewrote it on `node:http2`. The mocked-transport unit tests
> had passed — only the real send surfaced this. 26 push tests still green after the change.

**Remaining (Eugene, visual confirmation):**
1. Watch the registered device for the test banner / trigger a real session and let it finish
   or ask a question → observe "Finished" / "Needs you" push (SC1/SC2 on-device visual).
2. For a physical device: `flowdeck run -D "Hihi"`, set the Tailscale host URL, grant the
   permission prompt → Settings shows "On — registered" (SC6), tap a push → opens session (SC5).
   (A physical device uses sandbox under the Debug build, matching this key.)

## Bugs

_None yet._
