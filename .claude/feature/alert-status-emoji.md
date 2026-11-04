# Feature: a status emoji on every alert title

## User Story

As Eugene, I want every lfg notification title to start with an emoji for its status, so I can tell
"done", "needs me" and "stuck" apart at a glance. Today some alerts have ✅/🙋 and some have none.

## Cause of the inconsistency

| Sender | Before |
| --- | --- |
| Push watcher (turn finished / needs input), `src/push/watcher.ts` | ✅ / 🙋 |
| Agent `lfg notify`, `src/session-notifications.ts` | plain title (status only in the body: "Completed: …") |
| Scheduled-task result, `src/chat-jobs.ts` | plain task name |
| Mac app: watcher-style alerts | ✅ / 🙋 |
| Mac app: agent `lfg notify` alerts | plain title |
| Start Session Shortcut confirmation (iOS) | plain title |

## The table (one source per language)

`src/alert-title.ts` (server) and `ios/LFGCore/Sources/LFGCore/AlertStatus.swift` (Mac app + iOS
Shortcut). Both must stay identical.

| Status | Emoji |
| --- | --- |
| completed / finished | ✅ |
| needs-input | 🙋 |
| blocked | ⚠️ |
| working (progress) | ⏳ |
| reminder | 🔔 |
| job (scheduled task result) | 📅 |
| started (Shortcut) | 🚀 |

Rule: a leading run of status emoji in the title is dropped, then the right one is added. So an
agent that types "✅ Done" for a reminder gets "🔔 Done", never "🔔 ✅ Done". Other emoji stay.

## Success Criteria

- [x] SC1: All three server senders put the status emoji first — **Verify by:** `bun test src/alert-title.test.ts src/session-notifications.test.ts src/chat-jobs.test.ts src/push/`
- [x] SC2: The stored `lfg notify` receipt keeps the agent's title (retries compare it) — **Verify by:** session-notifications test asserts `notification.title` has no emoji
- [x] SC3: Mac alerts use the same table, including agent alerts — **Verify by:** `lfg --desktop-feature-test`
- [x] SC4: The phone shows the emoji on real server payloads — **Verify by:** build payloads with the real server code, deliver them with `flowdeck simulator push`, screenshot the banners

## Decision Log

- Kept ✅ and 🙋: they are what the phone already shows for the two most common alerts.
- The emoji is added at the alert surface only, not stored in the receipt or the journal event.
- Bodies keep their word labels ("Completed: …"): VoiceOver reads them, and the emoji alone is ambiguous.

## Verification Evidence

| SC | Command / action | Observed |
| --- | --- | --- |
| SC1 | `bun test src/alert-title.test.ts src/chat-jobs.test.ts src/session-notifications.test.ts src/push/` | 160 pass, 0 fail; chat-job push title starts with `📅 ` |
| SC2 | same run | receipt `notification.title` is `"Fix notifications"`; the APNs title is `"✅ Fix notifications"` |
| SC3 | `desktop/build.sh` + `lfg --desktop-feature-test` | `{"ok":true,"tests":286}`; agent alert "✅ Review" sent as a reminder posts "🔔 Review" |
| SC4 | payloads built by the real `buildPayload` and `SessionNotifications.send`, delivered with `flowdeck simulator push` | titles on the wire: `✅ Fix the login bug`, `🙋 Fix the login bug`, `⚠️ Ship release`, `🔔 Review the PR` (`*.json`, bytes `e2 9c 85` = ✅). Banners appear, but **the slimmed simulator draws every emoji as a missing-glyph box** — including the ✅ the phone already shows today (`banners.png`). So glyph rendering is verified on the real phone only for ✅/🙋; the other five are standard emoji, not yet seen on a device. |

Also: LFGCore `swift test` 651 XCTest + 584 Swift Testing pass (incl. `AlertStatusTests`); iOS app builds; `tsc --noEmit` clean.

## Part 2: alert descriptions say what was built

Request (2026-11-03): the description should say which problem the session solved or which feature it
built; only when nothing was built should it say what was done.

### Where descriptions come from

| Alert | Description source |
| --- | --- |
| Agent `lfg notify` | the agent writes `--message`, guided by `withNotificationInstructions` / `chatNotificationInstructions` |
| Watcher "finished" fallback (no agent alert) | the opening of the agent's final reply, clipped to 350 chars |
| Mac app | same two sources |

### Measured before choosing

- All 5 agent alerts on record lead with process, not the feature: "Pro updated and verified…",
  "Dump build 202611030936 is on TestFlight: …", "…built and verified (audit PASS). Not live yet…".
- Tried preferring the reply's `**Done:**` footer line for the fallback, then measured: only 2 of 115
  recent final replies have one, and in one of the two the opening was better ("You can now delete
  saved links" vs "Build 202611031008 is on TestFlight with Delete…"). Reverted.

### Change

The agent instructions now say: start every message with what was built or which problem was solved,
in the user's terms, not the steps, builds or checks; then what the user must know or do; describe the
work only when nothing was built or fixed. With a good and a bad example. Same rule in the chat
instructions and in `lfg notify --help`. The watcher fallback is unchanged — the house reply rules
already put the result first.

- [x] SC5: managed and chat sessions get the new rule — **Verify by:** `bun test src/session-notification-instructions.test.ts` (1 pass)
- [ ] SC6: a new session's alert leads with the feature — **Verify by:** read the next agent alerts in `~/.lfg/session-notifications.json` after deploy. Not verifiable before: running sessions keep the prompt they started with, and the live server runs an Oct 29 release copy.
