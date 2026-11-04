# Feature: hidden directories also mute notifications

## User Story

As Eugene, when I hide a directory (Settings → Hidden directories, or "Hide <dir>" on a row), I want
that device to stop alerting me about sessions in it, so churny populations (gbrain autopilot, scratch
dirs) don't buzz my phone or Mac for sessions I chose not to see.

## User Flow

1. On the phone, hide `~/.gbrain` (or a pattern like `*/gbrain-claude-cli-cwd-*`).
2. A session in that directory finishes a turn or asks a question → no push on that phone.
3. An agent in that directory runs `lfg notify` → no push on that phone.
4. On the Mac app, hiding a directory there stops its local alerts the same way.
5. Unhide the directory → alerts resume for the next new transition (no backlog burst).

## Where alerts come from (found during investigation)

| Source | Sender | Filter point |
| --- | --- | --- |
| Turn finished / needs input | server `runPushTick` (`src/push/watcher.ts`) → APNs | server, per device |
| Agent `lfg notify` | server `SessionNotifications.send` → APNs | server, per device |
| Scheduled chat job | `ChatJobs.afterTick` → APNs | n/a: chats have `cwd: null`, never hidden |
| Mac app local alerts | `DesktopNotificationTracker` over `notificationItems` | client |
| Fleet Live Activity | broadcast channel, one card for all devices | **out of scope** (see Decision Log) |

iOS cannot drop a visible push after it arrives (a Notification Service Extension needs Apple's
filtering entitlement), so the phone must tell each host what it hides.

## Success Criteria

- [x] SC1: The watcher sends no APNs alert to a device whose hidden set hides the session's cwd; other devices still get it — **Verify by:** `bun test src/push/watcher.test.ts` (new case)
- [x] SC2: `lfg notify` skips muted devices and reports them; all-muted reads `state: "muted"`, not "unavailable" — **Verify by:** `bun test src/session-notifications.test.ts` (new case)
- [x] SC3: `POST /api/push/register` stores a normalized `hiddenDirs`; omitting the field keeps the stored set (old clients don't wipe it) — **Verify by:** store unit test + curl against a scratch server, then read `push-devices.json`
- [x] SC4: The phone sends its hidden set on every registration and re-registers when the set changes — **Verify by:** LFGCore test of the request body + scratch-server log of the re-register after hiding in the sim
- [x] SC5: Foreground backstop: a push for a hidden session that still reaches the phone (stale host) shows no banner — **Verify by:** pure LFGCore test of the presentation decision
- [x] SC6: Mac app posts no local alert for hidden-dir sessions; unhiding seeds without a burst — **Verify by:** desktop tracker test / `--notification-probe` against a hidden session
- [x] SC7: Settings footer text matches the new behavior — **Verify by:** screenshot of Hidden directories screen

## Platform & Stack

- Server: Bun + TypeScript (`src/`)
- iOS: SwiftUI + LFGCore (`ios/`)
- Mac: SwiftUI (`desktop/`)

## Decision Log

- **Per-device hidden set on the server, not a global one.** Hidden dirs are documented as "on this
  device"; the phone and the Mac keep separate lists. The phone uploads its own list with its token.
- **Missing `hiddenDirs` in a register body keeps the stored value.** Old app builds re-register on
  every launch; replacing with `[]` would unmute everything until the new build ships.
- **Live Activity left alone.** The fleet card is one broadcast to every device, so per-device
  filtering is impossible there. Muting it would need a shared (cross-device) hidden list. Flagged
  as a follow-up question, not built.
- **Chat job pushes untouched.** Chats have no cwd, so no hidden directory can match them.

## Verification Evidence

Run 2026-11-03 on the Pro (`Eugenes-MacBook-Pro`), uncommitted working tree.

| SC | Command / action | Observed |
| --- | --- | --- |
| SC1 | `bun test src/push/ src/session-notifications.test.ts src/hidden-dirs.test.ts` | 161 pass, 0 fail; new case "a device that hides the session's directory gets no push; others still do" sends `ipad:s1, ipad:s2, phone:s2` only |
| SC2 | `bun test src/session-notifications.test.ts` | new case passes: one muted device skipped (`muted: 1`), all-muted → `state: "muted"`, in-app event still emitted |
| SC3 | scratch server on :8792 (`LFG_DATA` in scratchpad), `curl POST /api/push/register` with `["/Users/e/.gbrain/","relative","*/gbrain-claude-cli-cwd-*"]`, then a second POST without the field | stored `["/Users/e/.gbrain","*/gbrain-claude-cli-cwd-*"]`; unchanged after the field-less POST |
| SC4 | sim `cc-62b7cad1` running this build against :8792; Allow notifications → hide `inbox` → swipe Show | `push-devices.json` for token `80cab62f…`: `[]` on launch → `["/Users/eugenechan/dev/inbox"]` 3 s after hide → `[]` after Show |
| SC5 | `flowdeck simulator push` while foreground, inbox hidden: payload with `session.cwd=/Users/eugenechan/dev/inbox/scratch`, then control with `/Users/eugenechan/dev/personal/lfg` | muted push: no banner (`after-muted-push.jpg`); control: "SHOWN test" banner (`after-shown-push.jpg`) |
| SC6 | `desktop/build.sh` (`-Onone`) + `lfg --desktop-feature-test` | `{"ok":true,"tests":285}`; with the filter reverted the same run fails, so the test discriminates |
| SC7 | Filter directories sheet in the sim | footer reads "…stay out of the list, the counts and search on this device, and send it no notifications. They keep running." |

Regression: LFGCore `swift test` 651 XCTest + 582 Swift Testing pass; `bunx tsc --noEmit` clean; `src/push/*` (161) and the 9 other test files that import the changed modules (97) pass. A single-process run of every server test file gets SIGKILLed partway (exit 137), so the whole suite was NOT run green. In that combined run `title-write-safety` fails on another test's leaked data path; run alone it passes (13/13). Both look pre-existing and unrelated.

Evidence images: `.claude/feature/hidden-dirs-mute-notifications-evidence/`.

### Independent audit (verification-auditor) — PASS on SC1–SC7

Report: `.claude/feature/hidden-dirs-mute-notifications-evidence/audit/evidence.md`. Each new test also
fails with its filter turned off. Gaps it raised, and what happened:

| Gap | Outcome |
| --- | --- |
| A host that is down when a directory is hidden keeps alerting until the next launch | Fixed: `PushManager` remembers hosts whose registration failed and retries them on every foreground. Live: scratch host stopped → hid `dump` → host restarted, still `[inbox]` for ~1 min → Home, reopen → `[inbox, dump]` 1 s later |
| Overlapping hide/unhide registrations could land out of order | Fixed: registrations run one at a time, in order; each reads the hidden set when it runs |
| `registerPush(hiddenDirs:)` defaulted to `[]`, so a new caller would unmute everything | Fixed: the parameter is now required |
| Fleet Live Activity and cwd-less sessions are never muted | Not changed — see Decision Log; open question for Eugene |

Full server suite, in batches of 25 files (one process gets SIGKILLed): 150 files, 1,492 pass, 3 fail.
The 3 failures are source-scan tests of `ios/LFG/RichContent.swift` and `ios/LFG/SessionDetailView.swift`,
which this work does not touch and which are unmodified in the tree, so they already fail on `main`.

## Not live until deployed

- Server: both hosts' `lfg serve` must restart to load the filter (Pro and Air). Check `~/.lfg/phone-sign-in-history.json` for `waiting` rows first.
- Phone: needs a new build; the shipped build never sends `hiddenDirs`, so hosts mute nothing for it.
- Mac app: needs a rebuild and reinstall of `/Applications/lfg.app`.

## Bugs

_None yet._
