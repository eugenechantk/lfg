# Evidence — "Mark as unread" + unread badges (iOS client)

Spec: `.claude/feature/mark-as-unread-and-unread-badges.md`
Implementation: delegated to Codex (`codex resume 019fa9a8-4ede-7e62-9704-f417f110260e`).
Verification below was run independently by the supervising Claude session.

## Result: all six success criteria pass

| SC | Criterion | Verdict | Evidence |
| --- | --- | --- | --- |
| SC1 | `ManualUnread` unit tests green | PASS | `swift test` in `ios/LFGCore`: **141 tests, 0 failures** (baseline before the change: 137 → 4 new) |
| SC2 | Menu action marks unread, returns to list, lands in Unread | PASS | `10-menu.png` (menu item), `11-after-mark-unread.png` (popped to list, session in Unread with purple dot) |
| SC3 | Stays unread across poll + relaunch; cleared by re-opening | PASS | `13-after-relaunch.png` (still unread after stop → rebuild → relaunch); on-disk `lfg.manualUnread = ['4501fc50-…']`; `15-menu-after-reopen.png` (menu offers "Mark as unread" again → flag consumed); `16-count-after-read.png` (6 → 5, session moved to Idle) |
| SC4 | Top-bar bubble + Unread header count; Mark all read clears | PASS | `06-list-live.png`, `12-unread-header.png` (red 6 in both places), `33-mark-all-read.png` (Unread section and both counters gone) |
| SC5 | App icon badge = unread session count | PASS | `32-icon-badge.png` (red **6** on the lfg icon), `36-badge-zero.png` (badge gone at 0) |
| SC6 | No regression to derived unread | PASS | 6–7 sessions surfaced as Unread from the derived predicate throughout; Working/Idle/Closed grouping unaffected (`06`, `35`) |

## How it was verified

- **Build:** FlowDeck, iOS 26.3 simulators. One fix was needed by me: the new
  `ios/LFG/UnreadBadges.swift` wasn't in the Xcode project → `xcodegen generate`
  (project.yml is the source of truth). Build green after that.
- **Sim A — iPhone 17** (`D69C6DC8…`, existing read-state + host config, repointed to
  `http://127.0.0.1:8766`): SC2, SC3, SC4, SC6. Real taps via `flowdeck ui simulator`,
  nav-bar buttons driven with raw HID `touch down/up` (synthetic taps don't fire them).
- **Sim B — iPhone 16e** (`9CD8C593…`, **erased** so the notification prompt would
  re-appear): SC5. iPhone 17 had notifications *denied*, which suppresses the icon badge
  at the OS level, and its Settings toggle wouldn't respond to synthetic taps (the sim
  then wedged on its lock screen). Erasing a spare sim and accepting the real permission
  prompt was the faster deterministic path.

## Notes / judgement calls

- **Mark-as-unread pops back to the list.** Staying parked in the transcript reads as
  "nothing happened", and the pop makes the new Unread row + counters immediately visible.
  Implemented via a distinct `onMarkedUnread` callback (not by reusing `onEnded`).
- **Manual unread does not override Needs-you / Paused / Working** — those are more
  actionable. The flag persists and surfaces once the session goes idle.
- **`unreadCount` is user-filtered but not host-filtered** (documented in the code): the
  host filter is a list-view concern, and the app icon badge should not lie about other
  hosts' sessions.
- **Badge transient:** the badge briefly read `1` right after Mark all read while the app
  was backgrounded, then cleared to 0 on the next foreground refresh. That is the existing
  derived read-state/busy churn (a live session's message landing during the background
  grace), not the manual flag.
- The repo had another agent's in-flight work in `SessionStore.swift` /
  `SessionDetailView.swift` / `Components.swift` (offline-composer queue) throughout. The
  delegated diff is additive and does not touch those hunks.
