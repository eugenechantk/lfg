# Delegation Brief: phase2d2 — Live Activities client (widget extension + tokens)

**Goal:** the iOS half of Live Activities: a widget extension rendering a session activity on
the lock screen / Dynamic Island, the shared `LFGSessionAttributes` type matching the server's
pinned content-state, and ActivityKit push-token registration against the D1 endpoints that
already exist on the server (committed).

**Repo:** git worktree of `lfg`; work ONLY under `ios/`. Server side is DONE — do not touch
`src/`. Build system: `project.yml` is the source of truth (xcodegen), never hand-edit
`LFG.xcodeproj`. After editing project.yml run `cd ios && xcodegen generate`.
Swift 6, strict concurrency complete — everything crossing actors must be Sendable.

## Context (read first)

- `ios/project.yml` — current single-target app (`LFG`, bundle id `com.eugenechan.lfg`,
  iOS 17.0 target as configured — raise app + extension to 17.2 minimum, needed for
  `pushToStartTokenUpdates`).
- `ios/LFG/PushManager.swift` — APNs lifecycle + AppDelegate; house style for registration
  state + server POSTs.
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift` — stateless client; add the two token POSTs
  here (plain endpoints, lenient decode, follow `registerPush`-style precedent if present).
- Server endpoints (LIVE, already committed — verify with curl if desired):
  - `POST /api/push/live-activity/start-token` body `{token: <hex>, env: "dev"|"prod"}`
  - `POST /api/push/live-activity/update-token` body `{token: <hex>, env, sessionId}`
- Server content-state (PINNED, must match field-for-field):
  `{title: String, state: "working"|"blocked"|"idle", sid: String, since: Number (unix seconds)}`
  Attributes: `{sid: String, hostName: String}`; attributes-type string `LFGSessionAttributes`.

## Spec

1. **Shared type** `ios/Shared/LFGSessionAttributes.swift`, included in BOTH the app target and
   the widget extension target (via project.yml sources; `#if canImport(ActivityKit)` guard):
   `struct LFGSessionAttributes: ActivityAttributes` with `sid`, `hostName`;
   `ContentState: Codable, Hashable` with `title`, `state` (String — keep lenient, do NOT make
   it an enum that hard-fails on unknown values), `sid`, `since` (Double unix seconds).
   The Swift type name MUST stay `LFGSessionAttributes` (the server sends it as attributes-type).
2. **Widget extension target** `LFGWidgets` in project.yml: bundle id
   `com.eugenechan.lfg.LFGWidgets`, embedded in the app, `NSExtension` point
   `com.apple.widgetkit-extension`. Minimal `ActivityConfiguration` UI: lock-screen banner
   showing title + state (working = accent dot, blocked = orange, idle = gray) + elapsed time
   since `since` (use `Text(timerInterval:)`/relative date so it ticks without pushes);
   compact + expanded Dynamic Island variants (compact: state dot + title initial; expanded:
   title + state + elapsed).
3. **Plist/entitlement keys** (project.yml `info` properties, not manual plists):
   app target: `NSSupportsLiveActivities: true`, `NSSupportsLiveActivitiesFrequentUpdates: true`.
4. **Token registration** — new `ios/LFG/LiveActivityManager.swift` (@MainActor, owned by
   AppDelegate/PushManager next to existing push registration):
   - On launch (iOS 17.2+): task consuming
     `Activity<LFGSessionAttributes>.pushToStartTokenUpdates` → hex-encode → POST start-token.
     `env`: `"dev"` for DEBUG builds, `"prod"` otherwise (match how existing push register
     picks env if it does; else this rule).
   - Task consuming `Activity<LFGSessionAttributes>.activityUpdates`; for each activity, a
     child task consuming `activity.pushTokenUpdates` → POST update-token with
     `sessionId: activity.attributes.sid`. Handle already-running activities at launch too.
   - Registration failures: log and continue (never crash/block launch); retry next launch is
     acceptable for this phase.
5. **LFGClient additions**: `registerLiveActivityStartToken(_ hex: String, env: String)` and
   `registerLiveActivityUpdateToken(_ hex: String, env: String, sessionId: String)`. Add a
   LFGCore unit test asserting the request bodies (there is existing test precedent for
   client request shapes; if not, test the body-building helper).

## Verification (run what the sandbox permits; report what you couldn't)

1. `cd ios && xcodegen generate` — clean.
2. `cd ios/LFGCore && swift test` — green (106 existing + your new ones).
3. Build BOTH targets for simulator. If flowdeck/xcodebuild is blocked in your sandbox, say so
   explicitly — the delegator builds and runs the sim verification.

## Definition of done
- [ ] `LFGSessionAttributes` compiles into both targets; ContentState fields exactly
      `{title, state, sid, since}` — lenient String state.
- [ ] Widget extension target builds; lock screen + Dynamic Island views exist.
- [ ] Push-to-start + per-activity update tokens registered against the two endpoints.
- [ ] project.yml-only project changes; xcodegen regenerates cleanly; no `src/` changes.
- [ ] LFGCore tests green including new request-shape tests.

**Report back:** files changed, test output, build status (or sandbox limitation), any
deviation from the pinned content-state.
