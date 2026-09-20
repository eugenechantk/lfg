# Feature: Live Activity broadcast channel

Replace the per-card APNs **update token** with a **broadcast channel**, so the server can
update and end the fleet card without the phone ever having to wake up and register
anything. Raise the iOS deployment target to 18.0 so the token path can be deleted rather
than run alongside.

## User Story

As Eugene, when my phone is locked and idle and the last running session finishes, I want
the Live Activity to update and dismiss on its own, so that I can trust what the lock
screen says without opening the app.

## The bug this fixes

The server can only `update`/`end` a card whose **update token** the phone handed it.
A push-started card only yields that token if iOS wakes the app in the background, which on
an idle phone frequently does not happen — **9 of 14 starts on 2026-09-19 got no token
back**. Worse, a dead Live Activity token answers **200**, so the server counts the
undelivered `end` as delivered, nulls `active.current`, unlinks its state file, and the
frozen card stays on screen with nobody left who believes it exists.

With a channel there is **no per-card token at all**: any card subscribed to the channel
receives every broadcast, awake or not.

## Research — verified against live Apple docs (fetched 2026-09-20)

Sources: `usernotifications/sending-channel-management-requests-to-apns`,
`usernotifications/sending-broadcast-push-notification-requests-to-apns`,
`usernotifications/setting-up-broadcast-push-notifications`,
`activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications`.

**CORRECTION to `.claude/diagnosis-live-activity-idle-updates-need-broadcast-channel-20260919.md`:**
that doc gives one management host/port. There are **two, and they differ in both**:

| | Management (channels) | Broadcast (publish) |
|---|---|---|
| Sandbox | `api-manage-broadcast.sandbox.push.apple.com:2195` | `api.sandbox.push.apple.com:443` * |
| Production | `api-manage-broadcast.push.apple.com:2196` | `api.push.apple.com:443` * |

\* **Unresolved ambiguity:** the broadcast page's prose says `api.sandbox.push.apple.com:443`,
but every worked example in the same page uses `host = api-broadcast.sandbox.push.apple.com`.
Must be settled empirically in Phase 2 — try prose host first, fall back to the example host.

**Channel management** — `POST|GET|DELETE /1/apps/<bundleId>/channels`, plus
`GET /1/apps/<bundleId>/all-channels`. Create body:
`{"message-storage-policy": 1, "push-type": "LiveActivity"}`. Success is **201** with the id
in the **`apns-channel-id` response header**, base64. Policy `0` = no storage (higher
publishing budget); `1` = most recent message stored, max 8 h. **Policy is immutable after
creation.** Channels cannot be shared across environments. Limit 10,000 per app per env.
Do not assume the channel id's size.

**Broadcast publish** — `POST /4/broadcasts/apps/<bundleId>`. Required headers:
`apns-channel-id`, `apns-expiration`, `apns-priority`, `apns-push-type: liveactivity`.
There is **no `apns-topic`** on this path — the bundle id is in the path. Payload ≤ **5 KB**.
**A nonzero `apns-expiration` against a policy-0 channel is rejected**, so policy and
expiration must agree.

**Broadcast CANNOT start an activity** — verbatim: *"You can't use broadcast push
notifications to start a Live Activity."* Push-to-start still goes to the per-device
push-to-start token. The start payload carries **`input-push-channel: "<channelId>"`**, and
the resulting card then listens on the channel. This is what removes the update token
without removing push-to-start.

**App-started cards** use `Activity.request(attributes:content:pushType: .channel(channelId))`.
**"If the channel ID isn't a valid channel, the Live Activity fails to start."**

**Ordering** — APNs *may reorder* broadcasts on a channel. `aps.timestamp` is what lets the
system "always display the most recent" update, so it must stay correct (it already is).

**Budget** — priority `10` counts against the push budget; **priority `5` does not**.
Apple explicitly recommends a mix. We currently send `10` unconditionally.

**Capability** — Certificates, IDs & Profiles → Identifiers → select `dev.omg.lfg` → enable
**Broadcast Capability** under Push Notifications. *"You can't enable broadcast capability
through Xcode."* Disabling it later **deletes every channel irreversibly**.

## User Flow

1. The lfg server creates one channel per APNs environment on first use and persists the id.
2. The app asks its default host for the channel id and caches it.
3. A card is created either by the app (`pushType: .channel(id)`) or by the server
   (push-to-start carrying `input-push-channel`).
4. Every later update and the final end are published once to the channel.
5. The card stays correct on a locked, idle phone — including the last session finishing.

## Success Criteria

- [ ] SC1: The server creates (or reuses) exactly one channel per APNs env and persists the id across restarts — **Verify by:** unit tests on the channel store + a live `POST /1/apps/dev.omg.lfg/channels` against sandbox returning 201 with an `apns-channel-id`, then `GET /all-channels` listing it.
- [x] SC2: `POST /api/push/live-activity/channel` returns the channel id for the caller's env — **Verify by:** `curl` against a local `lfg serve` on a non-canonical port, asserting the JSON body. **DONE.**
- [ ] SC3: A broadcast `update` reaches a live card with no update token registered — **Verify by:** on a real device, start a card, confirm no `activityUpdate` token exists in the store, publish a broadcast, observe the card change. Screenshot before/after.
- [ ] SC4: **The bug.** Phone locked and idle, one running session, session finishes → the card updates and dismisses without the app being opened — **Verify by:** device test with the phone locked ≥10 min; `~/.lfg/liveactivity.log` shows `decide end` + a 200 broadcast; photo/screen recording of the lock screen before and after.
- [x] SC5: Update tokens are gone — `supersede`, `listActivityUpdateTokens`, the `/update-token` endpoint and `registerLiveActivityUpdateToken` no longer exist — **Verify by:** `git grep` returning no hits; `bun test` green.
- [x] SC6: iOS deployment target is 18.0 and the app builds and runs — **Verify by:** `flowdeck` build + launch on the iPhone 17 Pro simulator, and `grep deploymentTarget ios/project.yml`.
- [ ] SC7: Existing Live Activity behaviour is unregressed — one card per phone, correct rows/counts/ordering, dismissal at zero — **Verify by:** the existing LFGCore test suite plus `ios_visual_evidence_auditor` on the lock-screen card.

## Platform & Stack

- **Platform:** iOS 18+ client (Swift 6 / SwiftUI / ActivityKit / WidgetKit) + Bun server (TypeScript)
- **Key frameworks:** ActivityKit, WidgetKit, APNs HTTP/2 (existing JWT machinery in `src/push/apns.ts`)
- **Test frameworks:** `bun test` (server), Swift Testing via `swift test` in `ios/LFGCore` (pure logic), FlowDeck for device/simulator

## Steps to Verify

1. Server: `bun test src/push/` — all green.
2. LFGCore: `swift test` in `ios/LFGCore` — all green.
3. Live channel round trip against **sandbox** (create → read → all-channels → delete).
4. Build + install to the iPhone 17 Pro simulator via `/flowdeck`; confirm a card appears.
5. Device test for SC3/SC4 — `simctl push` cannot exercise background delivery, so the real
   phone is mandatory here.

## Implementation Phases

### Phase 1 — Server: channel management + broadcast transport

- Scope: extend `src/push/apns.ts` with a broadcast/management request path (different host,
  port, header set, no `apns-topic`); new `src/push/channel-store.ts` persisting
  `{env -> channelId}` in `~/.lfg/live-activity-channels.json`; create-or-reuse on demand.
- Success criteria covered: SC1.
- Verification gate: unit tests + a real sandbox create/read/delete round trip.
- **Blocked on:** Broadcast Capability being enabled on `dev.omg.lfg` before the live round
  trip can pass. Code and unit tests can land first.

### Phase 2 — Server: publish updates/ends over the channel

- Scope: `buildUpdate`/`buildEnd` publish to `/4/broadcasts/...`; `buildStart` gains
  `input-push-channel`; delete `supersede`/`listActivityUpdateTokens`; simplify the delivery
  threshold (one broadcast, not N tokens); settle the sandbox-host ambiguity; adopt
  priority 5/10 split.
- Success criteria covered: SC2, SC5.
- Verification gate: `bun test` green, `git grep` clean, curl against a local server.

### Phase 3 — Client: subscribe to the channel, drop the update token

- Scope: raise `project.yml` deploymentTarget to 18.0 and regenerate; `FleetActivityController`
  requests `.channel(id)`; `LiveActivityManager` drops `track()`/`pushTokenUpdates`/
  `sendUpdateToken` and instead fetches + caches the channel id; keep a token-free
  "card started" ping so the server still knows a card exists.
- Success criteria covered: SC6.
- Verification gate: builds and launches on the iPhone 17 Pro sim; card still appears.

### Phase 4 — Device verification

- Scope: no new code. Run SC3, SC4, SC7 on a real device.
- Verification gate: evidence recorded below; `ios_visual_evidence_auditor` PASS.

## Decision Log

- **2026-09-20 — Keep both card creators.** The channel makes server-only creation viable
  for the first time, but going server-only also requires settling the population divergence
  (the server sees one host, no muted dirs, no user filter — see the artifact). Out of scope
  here; this change swaps the transport only.
- **2026-09-20 — `message-storage-policy: 1` (most recent stored, 8 h).** Policy 0 buys a
  higher publishing budget, but policy 1 means a card that comes online late still receives
  the latest state — which is precisely this feature's failure mode. Revisit if throttled.
- **2026-09-20 — Deployment target 18.0, not 26.0.** 18.0 is the minimum that unlocks
  channels and lets the token path be deleted. Going to 26.0 would additionally retire ~24
  availability guards, but bundling that with a delivery rewrite makes the diff unreviewable.
  Proposed as a separate follow-up.
- **2026-09-20 — App caches the channel id; no card if absent.** A card cannot be created
  with an invalid channel id, so an app that has never reached its host simply creates no
  card and lets the server push-to-start one. The alternative — falling back to
  `pushType: .token` — would preserve the whole token path we are deleting.

## Verification Evidence

| Criterion | Command / action | Result |
|---|---|---|
| SC1 (partial) | `bun test src/push/channel-store.test.ts`, `…/broadcast.test.ts` | 7/7 and 14/14 pass. Management host/port per env, create body, 201 + `apns-channel-id` header, get-or-create, failure→null all pinned. **Live sandbox round trip still blocked on the capability flag.** |
| SC2 ✅ | `lfg serve` on port 8793, `POST /api/push/live-activity/channel -d '{"env":"production"}'` | `{"ok":true,"channelId":null,"reason":"apns-not-configured"}` — correct degradation on a host without APNs creds, and it exercises the "null is a normal answer" contract. `POST …/started` → `{"ok":true}`; legacy `…/update-token` alias → `{"ok":true}`. |
| SC3 | — | **Blocked**: needs a real device + the capability flag. |
| SC4 | — | **Blocked**: needs a real device + the capability flag. |
| SC5 ✅ | `git grep` over `src` and `ios` | No `listActivityUpdateTokens`, `supersede`, `registerLiveActivityUpdateToken`, `pushTokenUpdates`, or `pushType: .token` remain. Residual hits are `Activity.activityUpdates` (a different ActivityKit API) and deliberate legacy-pruning fixtures. |
| SC6 ✅ | `xcodegen generate` + `flowdeck build -S "iPhone 17 Pro"` | **Build Completed.** 6 × `IPHONEOS_DEPLOYMENT_TARGET = 18.0` in the regenerated pbxproj. |
| SC7 (partial) | `swift test` in `ios/LFGCore`; `bun test src/` | 561 XCTest + 162 Swift Testing, 0 failures. 126/126 push tests; 894/896 full server suite — the 2 failures are pre-existing Playwright/MV3 browser tests, confirmed by re-running with these changes stashed. Visual auditor not yet run (Phase 4). |

### Blocked on you

1. **Enable Broadcast Capability** — developer.apple.com → Certificates, IDs & Profiles → Identifiers → `dev.omg.lfg` → Push Notifications → Broadcast Capability. Cannot be done in Xcode or by me. *Disabling it later deletes every channel irreversibly.*
2. Then Phase 4: device verification of SC1 (live round trip), SC3 and SC4.

## Bugs

_None yet._

## Out of scope / follow-ups

- `stale-date` + `activityStateUpdates` so a card that stops receiving broadcasts says
  "unknown" instead of lying (host down, server restart, past the 8 h store window).
- The population divergence: the server's card counts one host and ignores muted
  directories and the user filter; the app's counts all hosts and applies both.
- Raising the deployment target to 26.0 and retiring the `available(iOS 17.2/17.4/18.0)` guards.
- Local `main` is 1 ahead / 2 behind `origin/main` with a duplicated commit, and origin has
  `fb23f0d fastlane: gate every archive on the bundled Cloudflare Access payload` that this
  tree lacks. Reconcile before any TestFlight build.
