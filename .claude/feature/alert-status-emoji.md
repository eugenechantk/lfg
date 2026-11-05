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

## Part 3: Mac alerts quote the reply, not "The agent finished its turn."

**Report (2026-11-04):** Mac notifications are still generic, not specific to each session.

**Ground truth:** macOS's delivered-notification database (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`,
app `com.eugenechan.lfg-desktop`), last 25 alerts: 13 read "The agent finished its turn." Matching each
alert's second against its transcript: all 13 fired 0–1 s after the turn's final assistant text, so a real
reply existed every time (the "turn had no text" theory is disproved).

**Cause:** the Mac app's live feed decodes only `busy`, `prompt` and `notification` events — message
events are dropped on purpose — so a session's `last` is whatever the 10 s poll last fetched. On
`busy:false` the 200 ms settle read that stale row (a tool call, or the previous reply) and fell back to
the generic body. Phone pushes are built on the host from the transcript at tick time, so they quote it.

**Fix:** `settleNotifications(host:)` fetches that host's rows once (`latestReplies`) and builds the
alert from their `last` / `lastUserAt`; an unreachable host keeps the held rows. Nothing else changes.

- [x] SC7: a finished alert quotes the fetched reply over a stale held row — **Verify by:** `lfg --desktop-feature-test` (288 pass; the new check fails on the old path, which gave the generic body for a held tool-call row)
- [x] SC8: the fetch returns the reply on a real host — **Verify by:** `lfg --notification-probe 34546475-… body` → `fresh: ✅ iPad layout redesign | Finished: TestFlight build 202611041524 is ready…`
- [x] SC9: real turn ends, live feed — **Verify by:** `lfg --notification-probe watch 480` prints `sent:` (new) beside `held:` (old) for each alert. 17:41:51 "Meta ads benchmarking": sent "Finished: I've updated the table on the same link…" (the reply that ended the turn); held "Finished: 1: desktop, scrolled sideways…" (the PREVIOUS turn's reply — the old path could quote the wrong turn, not only fall back to generic). Log: `alert-status-emoji-evidence/mac-watch-probe-20261104.log`.
- Not live until `/Applications/lfg.app` is rebuilt and reinstalled.

## Part 4: "needs input" only when a question is open

**Report (2026-11-05):** sessions send "needs input" alerts with no needs-input event — this session had
just done it.

**Ground truth:** `~/.lfg/session-notifications.json`: 45 agent alerts, 7 `needs-input`. For all 7 the
transcript shows no AskUserQuestion/ExitPlanMode within 10 min and the turn ending 46–75 s later — a
question written into the reply. 5 of the 7 were this session. The Mac's history of 🙋 alerts: the one
detector-sent alert (a phone sign-in request) was real; every false one was agent-sent.

**Cause:** the instruction said "at completion or when user input is required" and offered `needs-input`,
so agents (me included) used it for "Needs you:"-style questions in a finished reply.

**Fix:**
- Host (`SessionNotifications.send`): an agent's `needs-input` is recorded and delivered as `completed`
  (✅, "Completed: …", APNs kind `finished`), and the receipt says `reclassified`. It also counts as the
  turn's completion, so the watcher's generic "finished" no longer doubles it. Retries stay idempotent.
  `blocked` is unchanged.
- Instructions and `lfg notify --help` no longer offer `needs-input`: "Use completed when your turn ends,
  also when your reply asks the user something … lfg alerts an open question by itself."
- "Needs input" alerts now come only from the watcher, when a prompt actually opens.

- [x] SC10 — `bun test src/session-notifications.test.ts src/session-notification-instructions.test.ts src/push/ src/chat-jobs.test.ts src/chat-sessions.test.ts`: 173 pass.
- [x] SC11 — real CLI → scratch host route: `--status needs-input` → `{"status":"completed","reclassified":"needs-input → completed: lfg alerts open questions itself"}`.
- Not live until the host restarts; running sessions keep their launch prompt, but the host rule covers them.
