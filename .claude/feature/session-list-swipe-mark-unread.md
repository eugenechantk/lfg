# Feature: session-list-swipe-mark-unread

## User Story

As the person triaging a fleet of sessions from the phone, I want to swipe a session row to the right and mark it unread, so I can flag "come back to this" without opening the session (which would mark it read) and without digging into the detail view's ⋯ menu.

## User Flow

1. In the session list, swipe a row from left to right (leading edge).
2. A blue "Mark Unread" action appears. **Swiping past the threshold commits it with no tap** (Mail); a short swipe reveals the button for a tap instead.
3. The row moves into the **Unread** group; haptic success tick.
4. If the row was already Unread (manually or because it has unseen messages), the same swipe shows "Mark Read" instead, and tapping it moves the row out of Unread.
5. Opening a session later consumes the manual flag exactly as it does today (existing `ManualUnread.afterOpening`).

## Success Criteria

- [x] SC1: Leading swipe on an idle, read row offers "Mark Unread"; a full swipe (no tap) or a tap puts the row in the Unread group and persists across relaunch — **Verify by:** `ManualUnreadTests.testListActionOffersMarkUnreadForReadRow` + simulator recording of swipe → row moves to Unread → relaunch → still Unread.
- [x] SC2: Leading swipe on a row already in Unread offers "Mark Read"; a full swipe (no tap) or a tap moves the row out of Unread — **Verify by:** `ManualUnreadTests.testListActionOffersMarkReadForUnreadRow` + simulator recording.
- [x] SC3: No leading action for placeholder (`local-`) rows or closed rows, where the flag could not surface — **Verify by:** `ManualUnreadTests.testListActionIsNilForPlaceholderAndClosed`.
- [x] SC4: The trailing "Hide directory" swipe is unchanged — **Verify by:** simulator screenshot of a trailing swipe after the change.
- [ ] SC5: Marking the currently-selected row unread (iPad split view) clears the selection, mirroring the detail view's "Mark as unread" exit — **Verify by:** code path shares `selection = nil` with `RootView.onMarkedUnread`; residual risk noted, not simulator-verified on iPad.

## Platform & Stack

- **Platform:** iOS (lfg client, `ios/`)
- **Language:** Swift
- **Key frameworks:** SwiftUI `List` + `.swipeActions(edge: .leading)`; `LFGCore.ManualUnread`; `SessionStore.markUnread/markRead`

## Test Strategy

The list row's swipe menu is a thin view; the decision "which action, if any" is pure and lives in `LFGCore.ManualUnread.listAction(sessionID:isUnread:isClosed:)`, exercised by XCTest in `LFGCore`. The store primitives (`markUnread`, `markRead`) already exist and are what the detail view's ⋯ menu calls, so the swipe reuses them rather than adding a second path.

## Tests

### Package Unit
- `ios/LFGCore/Tests/LFGCoreTests/ManualUnreadTests.swift`
  - `testListActionOffersMarkUnreadForReadRow` — SC1
  - `testListActionOffersMarkReadForUnreadRow` — SC2
  - `testListActionIsNilForPlaceholderAndClosed` — SC3

## Implementation Details

- `LFGCore/ManualUnread.swift`: add `ListAction { markRead, markUnread }` and `listAction(...)`.
- `LFG/SessionListView.swift` `sessionRow`: add `.swipeActions(edge: .leading)` before the trailing one. Blue tint, `envelope.badge` / `envelope.open` icons (same as the detail menu). Identifiers `markUnread-<id>` / `markRead-<id>`.
- On mark-unread of the selected row: `selection = nil` (same as `RootView`'s `onMarkedUnread`).

## Decision Log

- **Toggle, not one-way.** Mail's leading swipe flips between Mark Read / Mark Unread depending on state. Alternative: always "Mark Unread". Toggle chosen because a manual-unread row otherwise has no list-level undo, and the detail menu already toggles.
- **No action on closed rows.** `closed` outranks `unread` in `SessionStore.group(for:)`, so the flag would be invisible; offering a dead action is worse than none. Working / needs-input rows DO get the action: the flag surfaces once the session goes idle, which is a plausible "remind me when it's done" use.
- **Full swipe commits** — Eugene: "I should not need to tap the button … swipe to a certain point will mark as unread". `allowsFullSwipe: true` is now explicit in code (it was the default, but the first verification pass only exercised the tap path).

## Verification Evidence

Build: `flowdeck build` succeeded 2026-09-19 10:43Z. Package tests: `cd ios/LFGCore && swift test --filter ManualUnreadTests` → 7 tests, 0 failures. Live checks on iPhone 17 Pro sim `E0DC8228…` against the real Pro host (21 Unread / 5 Idle at start).

| SC | Action | Observed | Artifact |
| --- | --- | --- | --- |
| SC2 | Leading swipe on Unread row "Asian character scene storyboard" | Blue "Mark Read" (envelope.open) revealed; tap → Unread 21→20, row moved to Idle (5) | `.flowdeck/automation/sessions/28EB5622` frames (self-run) |
| SC1 | Leading swipe on the same row now in Idle | Blue "Mark Unread" (envelope.badge) revealed; tap → Unread 20→21, Idle 5→4 | same |
| SC1 (persist) | `flowdeck stop` + `flowdeck run --no-build` | Row still under Unread (21) after cold relaunch. Discriminating: the prior Mark Read had stamped its newest message seen, so only the manual flag can put it back | `evidence-swipe-after-relaunch-unread-21.jpg` |
| SC1+SC2 full swipe | Edge-to-edge drag (`--from 10,y --to 395,y`), no tap, on rebuilt app C43971FF | Unread row "Sticker photo booth assets": Unread 21→20, row into Idle. Same row from Idle: Unread 20→21, Idle 5→4 | `evidence-full-swipe-mark-read.jpg`, `evidence-full-swipe-mark-unread.jpg` |
| SC3 | Leading swipe on a Closed row | No action revealed; the drag fell through as a tap and opened the session (SwiftUI's behaviour when no leading actions exist) | `evidence-swipe-closed-row.jpg` |
| SC4 | Trailing swipe on an Unread row | "Hide AI girl game" still present, unchanged | `evidence-swipe-trailing-unchanged.jpg` |
| SC5 | — | Not driven on iPad; reasoned from code (`selection = nil` mirrors `RootView.onMarkedUnread`) | residual risk |

Independent audit: **PASS** (SC1–SC4) — `ios_visual_evidence_auditor`, report `.claude/evidence/20260919-184735-ios-visual-audit/evidence.md`, recording `flow-a-mark-read-mark-unread.mov`, screenshots 01–11 + trees. The auditor drove a different Idle row ("Phone sign-in flow fixes and release") for SC1 and confirmed the `markUnread-<id>` / `markRead-<id>` identifiers resolve live.

## Shipped

TestFlight build **202609191931** on train 1.3.0, DoD PASS (VALID, IN_BETA_TESTING) at 19:37 HKT 2026-09-19. Logs: `ios/fastlane/deploy-202609191931.log`, `ios/fastlane/verify-202609191931.log`. Evidence: `.claude/feature/evidence/testflight-20260919d/README.txt`.

## Residual Risks

- SC3 side effect: a leading swipe on a Closed row has no action, so SwiftUI lets the drag fall through as a tap and opens the session. Stock List behaviour, not a regression; noted by the auditor as a minor rough edge.

- iPad split-view selection clearing (SC5) is reasoned from code, not driven on an iPad sim.

## Bugs

_None yet._
