# Delegation Brief: B1 (session vanishes after host recovery) + B2 (unread never fires)

**Goal:** find and fix the root causes of two client bugs observed during a live two-host test
of the lfg iOS client (repo `/Users/eugenechan/dev/personal/lfg`, client in `ios/`). Evidence and
context: `.claude/feature/track-a-soak-test-plan.md` ("Sim pass results" section).

## Observed facts (all verified live, 2026-07-10)

Setup: iOS client in a simulator, two live hosts (Pro + Air over tailnet). A headless `aisdk`
session `e03fc30f-cb26-490d-b29d-3b29b8a77ae5` was created on the Air (cwd `/Users/eugenechan/dev/personal/lfg`).
The Air's serve process was SIGSTOPped twice (15s, then 60s ×2) and SIGCONTed; assistant-message
marker lines were appended to the session's transcript during/after the outages.

- **B1:** The session's row was present in the app's list at bootstrap (tapped, viewed, streamed).
  After the outage/recovery sequence it was ABSENT from the entire list (multiple full-list scans
  over several minutes, well past the 60s reconcile cadence) — while `GET /api/sessions` on the Air
  returned a perfectly normal row for it the whole time (title, lastActivityAt fresh, agent aisdk).
  A fresh app relaunch restored the row immediately (IDLE section).
- **B2:** The last marker (`UNREAD-MARKER-CHARLIE`, arriving while the session was idle, list open,
  session NOT focused) never surfaced the row as Unread. Even after the relaunch that restored the
  row, it rendered in IDLE (read), not UNREAD.
- Exoneration checks already done — do not re-litigate these:
  - The server's `normalizeLineMessages` parses the synthetic marker lines fine and derives
    `last.id = "unread-c-1"` (verified by running the parser on the transcript directly).
  - The Pro never listed the session in `/api/sessions` (no cross-host guess-bind).
  - Read state: the session was viewed in the detail view up through marker `blip-b-1`, then
    dismissed (Back) minutes before CHARLIE arrived. So persisted `lastSeenMessageID[sid]` should be
    `"blip-b-1"`, and `ReadState.isUnread("unread-c-1", "blip-b-1")` should be true. It rendered IDLE.

## Where to look (code map, hypotheses — verify, don't assume)

All in `ios/LFG/SessionStore.swift` unless noted:

- `applyHostFetch` (~line 868): failure KEEPS `lastSessionsByHost` (last-good snapshot) — so the
  outage alone shouldn't remove the row. The bug is likely in what happens on/after RECOVERY.
- `rebuildSessions` (~886): merge of per-host live lists + `optimisticSessions` + `closedCache`
  (excluding live/optimistic/`resumedIds`). Question: can the row be eaten by `MultiHost.mergeSessions`
  first-wins dedupe (`ios/LFGCore/Sources/LFGCore/MultiHost.swift`), e.g. id collision with a
  session lacking `sessionId`, or by `Session.id` identity quirks for aisdk rows?
- The events path: `applyIngested` (~447) has an unknown-sessionId → `refresh()` trigger. CHARLIE's
  msg event arrived on the recovered Air link for a sessionId that (per B1) was missing from the
  in-memory list. Did that path mark something inconsistent (e.g. transcripts dict got the message,
  read-state marked, but the session row never re-added)?
- `group(for:)` (~1109) + `ReadState.isUnread` (LFGCore): B2's predicate. Post-relaunch the row's
  `s.last?.id` should be `"unread-c-1"` from the REST row. Check whether the IDLE-not-UNREAD
  rendering means `lastSeenMessageID[sid]` somehow BECAME `"unread-c-1"` — e.g. `markOpened`
  stamping while not actually focused (focusedID staleness), `rebuildSessions`'s
  `if let f = focusedID { markOpened(f) }`, or the busy-seeding path. Also check whether a session
  row served from the CLOSED/resumable synthesis path renders with a different `last` than the live
  row (closed rows can't be unread — `group` returns `.closed` first).
- The per-host closed pages (`closedFirstPageByHost` etc.) interplay: during the outage the session
  existed as a SYNCED transcript on the Pro, so the Pro's resumable list includes it. When the Air's
  live row disappeared from the merge (B1), the row should have fallen back to the Pro's closed
  entry — it did NOT render anywhere. Check `rebuildClosedCache(for:)` + `MultiHost.reconcileResumable`
  — the `liveIds` exclusion may be using a stale liveIds set that still contains the id while the
  merged live list doesn't render it (the row is in neither bucket = vanishes). This is my strongest
  hypothesis for B1: **live-set and closed-set disagree about who owns the id, and the row falls
  through the gap.**

## Requirements

1. Reproduce each mechanism with a UNIT test first (LFGCore or a testable extraction — the repo
   convention is logic in LFGCore with `swift test`; `SessionStore` logic may need a small pure
   extraction to test, keep it minimal). Do NOT attempt full simulator automation — the live repro
   is the supervisor's job after your fix.
2. Fix both. Keep edits minimal and additive; `SessionStore.swift` is high-traffic (concurrent
   agent sessions) — check `git status` before editing and don't reformat.
3. All existing suites green: `cd ios/LFGCore && swift test`, plus `bun test` at repo root
   (server untouched — don't modify server code for this).
4. Follow repo conventions per `ios/CLAUDE.md` (Swift 6 strict concurrency, logic → LFGCore+test).
5. Do not commit or push.

## Verification (run + paste output)

- `cd ios/LFGCore && swift test` — green, including your new tests that fail before the fix and
  pass after (state which tests those are).
- `bun test` — green (proves no server change needed/made).
- Build check: `cd ios && xcodegen generate` if you touch project.yml (you shouldn't need to), and
  report if the app target compiles (the supervisor will do the full sim build).

## Report back

Root cause of each bug (mechanism, file:line), the failing-then-passing test names, files changed,
verification output, any deviation from the hypotheses above.
