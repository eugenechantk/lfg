# iOS Visual Evidence Audit

Verdict: PASS
Timestamp: 2026-09-19 18:47–18:52 (local, Eugenes-MacBook-Pro)
Repository: /Users/eugenechan/dev/personal/lfg
Simulator: iPhone 17 Pro, iOS 26.3, UDID E0DC8228-3248-4630-8929-FBC5DFC6AE6D
App: com.eugenechan.lfg (scheme LFG, Debug; FlowDeck app E6301081 before relaunch, FCA54EAC after `flowdeck run --no-build`)

## Change Audited

`ios/LFG/SessionListView.swift` `sessionRow`: new `.swipeActions(edge: .leading)` driven by
`ManualUnread.listAction(sessionID:isUnread:isClosed:)` (`ios/LFGCore/Sources/LFGCore/ManualUnread.swift`).
Non-Unread rows get a blue "Mark Unread" (envelope.badge, id `markUnread-<id>`); Unread rows get a blue
"Mark Read" (envelope.open, id `markRead-<id>`); closed and `local-` rows get nothing. Trailing
"Hide <directory>" swipe must be unchanged. Feature doc:
`.claude/feature/session-list-swipe-mark-unread.md`. Implementer's claims were treated as unverified;
every criterion below was driven independently on the live app signed into the real Pro host.

Starting state (01-launch): Working 1 / Unread 21 / Idle 5 / Closed 60.

## Success Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1a: leading swipe on an Idle row reveals "Mark Unread" | PASS | `05-sc1-idle-row-leading-swipe-reveals-mark-unread.jpg` — blue badged-envelope action beside Idle row "Phone sign-in flow fixes and release"; `05-sc1-tree.json` contains label `Mark Unread`. Tap resolved to id `markUnread-61069356-928d-497a-b05f-2bd72e50de3d` (label_exact). Video `flow-a-mark-read-mark-unread.mov` ~1:20–1:45. |
| SC1b: tapping it moves the row into Unread (Unread +1, Idle −1) | PASS | `06-sc1-after-mark-unread-unread-21-idle-4.jpg` / `06-sc1-tree.json`: headers Unread 20→21, Idle 5→4, row gone from Idle. `09-sc1-before-relaunch-row-under-unread.jpg` / `09-sc1-tree-before-relaunch.json`: Unread expanded, row present at y=773 under "Unread, 21". |
| SC1c: row is still under Unread after `flowdeck stop` + `flowdeck run --no-build` | PASS | `10-sc1-after-relaunch.jpg` / `10-sc1-tree-after-relaunch.json`: new process (app FCA54EAC, pid 80964, clock 6:51), header "Unread, 21", row "Phone sign-in flow fixes and release" listed under Unread. `11-final-after-relaunch-idle-4.jpg` / `11-final-tree.json`: Idle still 4 and the row absent from Idle. Discriminating: the row was Idle (no unseen messages) before the swipe, so only the persisted manual flag can place it in Unread on a cold launch. |
| SC2a: leading swipe on an Unread row reveals "Mark Read" | PASS | `02-sc2-unread-row-leading-swipe-reveals-mark-read.jpg` — blue open-envelope action beside Unread row "Asian character scene storyboard"; `02-sc2-tree.json` contains label `Mark Read`. Tap resolved to id `markRead-79b6a3bd-8e43-4417-ba87-98a8ca051876` (label_exact). Video ~0:05–0:30. |
| SC2b: tapping it moves the row out of Unread (−1) into Idle | PASS | `03-sc2-after-mark-read-unread-20.jpg` / `03-sc2-tree.json`: Unread 21→20, row gone from Unread. `04-sc2-row-now-under-idle-5.jpg` / `04-sc2-tree-idle.json`: row is first under "Idle, 5". Persisted across relaunch too (`11-final-tree.json`: still first Idle row). |
| SC3: leading swipe on a Closed row reveals no action | PASS | `07-sc3-closed-row-leading-swipe-no-action.jpg` / `07-sc3-tree.json`: zero `Mark Read`/`Mark Unread` labels. With no leading actions SwiftUI let the drag fall through as a tap and opened the closed session's detail ("You are maintaining the session list…"), the same behaviour the implementer reported; navigated back with `ui simulator back`, counts unchanged (Working 1 / Unread 21 / Idle 4 / Closed 60). Video ~1:55–2:05. |
| SC4: trailing swipe on any row still shows the "Hide …" action | PASS | `08-sc4-trailing-swipe-hide-action.jpg` / `08-sc4-tree.json`: trailing swipe on Idle row "Asian character scene storyboard" reveals grey eye-slash "Hide AI girl game"; no other actions in the tree. Dismissed by swiping back (not tapped). Video ~2:15–2:25. |
| SC5: iPad split-view selection clearing | NOT AUDITED | Out of scope per caller. |

## Artifacts

Directory: `/Users/eugenechan/dev/personal/lfg/.claude/evidence/20260919-184735-ios-visual-audit/`

- `01-launch.jpg` — starting list: Working 1 / Unread 21
- `02-sc2-unread-row-leading-swipe-reveals-mark-read.jpg` + `02-sc2-tree.json`
- `03-sc2-after-mark-read-unread-20.jpg` + `03-sc2-tree.json`
- `04-sc2-row-now-under-idle-5.jpg` + `04-sc2-tree-idle.json`
- `05-sc1-idle-row-leading-swipe-reveals-mark-unread.jpg` + `05-sc1-tree.json`
- `06-sc1-after-mark-unread-unread-21-idle-4.jpg` + `06-sc1-tree.json`
- `07-sc3-closed-row-leading-swipe-no-action.jpg` + `07-sc3-tree.json`
- `08-sc4-trailing-swipe-hide-action.jpg` + `08-sc4-tree.json`
- `09-sc1-before-relaunch-row-under-unread.jpg` + `09-sc1-tree-before-relaunch.json`
- `10-sc1-after-relaunch.jpg` + `10-sc1-tree-after-relaunch.json`
- `11-final-after-relaunch-idle-4.jpg` + `11-final-tree.json`
- `flow-a-mark-read-mark-unread.mov` — 150 s h264 recording of the whole gesture flow (SC2 → SC1 → SC3 → SC4) up to the point just before the relaunch

## Commands

```
flowdeck config get --json
flowdeck apps --json
flowdeck ui simulator session start -S E0DC8228-3248-4630-8929-FBC5DFC6AE6D --json
flowdeck ui simulator record -o …/flow-a-mark-read-mark-unread.mov -t 150 --codec h264 --force -S <udid> --json
flowdeck ui simulator swipe right --from 30,320 --to 150,320 --duration 0.4 -S <udid>     # SC2 leading swipe (Unread row)
flowdeck ui simulator tap "Mark Read" -S <udid>                                           # → markRead-79b6a3bd-…
flowdeck ui simulator tap "Unread, 20" -S <udid>                                          # collapse Unread to reveal Idle
flowdeck ui simulator swipe right --from 30,460 --to 150,460 --duration 0.4 -S <udid>     # SC1 leading swipe (Idle row)
flowdeck ui simulator tap "Mark Unread" -S <udid>                                         # → markUnread-61069356-…
flowdeck ui simulator swipe right --from 30,745 --to 150,745 --duration 0.4 -S <udid>     # SC3 leading swipe (Closed row)
flowdeck ui simulator back -S <udid>
flowdeck ui simulator swipe left --from 370,385 --to 200,385 --duration 0.4 -S <udid>     # SC4 trailing swipe
flowdeck ui simulator swipe right --from 100,385 --to 300,385 --duration 0.3 -S <udid>    # dismiss Hide without tapping
flowdeck ui simulator tap "Unread, 21" -S <udid>                                          # expand Unread (pre-relaunch check)
flowdeck stop E6301081 --json
flowdeck run --no-build --json                                                            # → app FCA54EAC, pid 80964
flowdeck ui simulator tap "Unread, 21" -S <udid>                                          # collapse Unread (post-relaunch Idle check)
flowdeck ui simulator session stop -S <udid> --json
```

## Notes

- Swipes used explicit coordinates (row centre y from the accessibility tree's StaticText frames);
  the actions themselves were tapped by label and FlowDeck resolved them to the expected
  `markRead-<id>` / `markUnread-<id>` identifiers, so the ids are confirmed live.
- SC3's "no action" is proven negatively (no Mark label in the tree, no action drawn) plus the
  fall-through-to-tap side effect. Opening a closed session from the swipe is SwiftUI's default when
  a row has no leading actions, not a regression introduced by this change; noting it as a minor
  UX rough edge, not a criterion failure.
- The relaunch path reinstalls the app (`flowdeck run --no-build` logs "Installing app…"); the manual
  flags and the Mark Read seen-stamp still survived, which is the stronger persistence proof.
- Group headers were collapsed/expanded via header taps during the audit; the app was left running
  with Unread collapsed (Working / Unread 21 / Idle 4 / Closed 60 visible).
- Net state change left on the real host's client: "Asian character scene storyboard" is now read,
  "Phone sign-in flow fixes and release" is now manually unread.
- SC5 (iPad) not attempted, per caller.
