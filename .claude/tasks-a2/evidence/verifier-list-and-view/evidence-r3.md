# Verifier evidence, round 3: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 16:20–16:40 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PARTIAL**. No structural, copy or behaviour deltas remain. Three small colour deltas remain, one of them new this round.

Earlier rounds: `evidence.md` (round 1), `evidence-r2.md` (round 2).

## Scope and setup
- Boards: `tA2d-list`, `tA2d-detail` (+ paused), `tA2d-detail-failed` (+ retrying), `tA2d-detail-input` (+ answered). The board files are unchanged since 13:22 (mtime checked), so the Chrome renders in `raw/design-*.jpg` are still the reference.
- App: the rebuilt app on sim `1D902A87-…`, captured at 1x in `raw-r3/`. Every FlowDeck call passed `-S`.
- Full pass: list (All hosts and the Pro filter, top, bottom, Closed expanded, dock on both tabs) and the task view in all six states.
- Excluded: the shared status bar, and wraps where iOS avoids a one-word last line.
- The fixture host was reset after Retry and Answer. It is now PID 63082 (log `fixture-verifier.log` in the session scratchpad). Pause was undone with Resume; the host confirms `enabled: true, pausedAt: null`.

## Colour note: the board's amber and red are the old system colours
The boards' `#FF9F0A` and `#FF453A` are exactly Apple's dark-mode system orange and red from before iOS 26. On iOS 26 those system colours render as about (255,146,48) and (255,66,69). This round the app uses the system colours again for list times, result lines, the Needs input label, the badge, the paused label and the timeline. I count that as a native translation of "system orange/red", not a delta. The measured gap is green +13/−13 and blue +38 on orange; red is near identical. The lighter label tones (`#FFB340`, `#FF6961`) are back to where the board uses them: the waiting and failed card labels.

## Per-component table

| Component / state | Consistency | Structure | Copy | Type | Colour | Glyphs | Spacing |
|---|---|---|---|---|---|---|---|
| Section headers | PASS | PASS | PASS | PASS | **PARTIAL**: chevron grey | PASS (7×5) | PASS (38 pt) |
| Rows (time, title, schedule, result, chevron) | PASS | PASS | PASS | PASS (87 pt) | PASS (system tones) | PASS | PASS (separator x 78→401) |
| Paused rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Closed rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| End of list | PASS (no footer) | PASS | — | — | — | — | PASS |
| Dock + badge | PASS | PASS (badge shows on both tabs) | PASS | PASS | PASS | minor: filled Tasks icon | PASS |
| Task view top bar | PASS | PASS | — | — | native glass | native | PASS |
| Title, schedule, chips | PASS | PASS | **PASS**: "Every weekday at 9:00 AM" | PASS | PASS | PASS | PASS |
| Card: next run | PASS | PASS | PASS | PASS | PASS (`#0A6EE0`, `#409CFF`) | PASS | PASS |
| Card: paused | PASS | PASS | PASS | PASS | PASS (system orange) | PASS | PASS |
| Card: failed | PASS | PASS | PASS | PASS | PASS: label `#FF6961`, tint (43,11,12) vs board (41,11,9); **minor**: x icon `#FF6961` vs `#FF453A` | PASS | PASS (orphan-avoidance wrap) |
| Card: retrying | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Card: waiting | PASS | PASS | PASS | PASS | PASS: label `#FFB340`; **minor**: dot `#FFB340` vs `#FF9F0A` | PASS | PASS |
| Card: answered | PASS | PASS | PASS | PASS (pitch 23) | PASS | PASS | PASS |
| Instructions | **PASS**: retrying is now 2 lines with no button | PASS | PASS | PASS (pitch 22) | PASS | — | PASS |
| Runs header + timeline | PASS | PASS | minor: full error text | PASS | PASS (system red node and body) | PASS | PASS (37/59) |
| Ask bar + bottom fade | PASS | PASS | PASS | PASS | native glass | minor: filled sparkles | PASS (fade present) |

## Remaining deltas (design vs app)
1. **Section header chevron is too dim** (new this round). Board stroke `#A1A1A6` (rendered about 165). App `.tertiary`, max about 61: about a third of the board's brightness. Round 2 had 132, but at a larger size. The size is now right (7×5 vs 8×5). Crop: `r3-list-06-header-chevrons.png` (6x).
2. **Waiting card dot** `#FFB340` vs board `#FF9F0A`. The board only uses the light amber for the label text. Crop: `r3-waiting-02-card.png`.
3. **Failed card x icon** `#FF6961` vs board `#FF453A`. The board only uses the light red for the label text. Crop: `r3-failed-01-status-card.png`.

### Minor carry-overs (not counted against the verdict)
- Failed result text in the list and timeline is the full error sentence ("Failed · Opus 5.5 was unavailable, so no sessio…"). The board has "Failed · model unavailable · no session". This comes from the fixture's raw error text and the app's first-sentence rule.
- Filled SF symbols where the board draws outlines: the Tasks dock icon and the sparkles.
- Transient after Retry now: for about 1 s the timeline showed the failed run on top with no live row and no Retry tail (`raw-r3/app-retrying.png`). The next capture showed the board's layout (`raw-r3/app-retrying-2.png`).
- Low confidence at 1x: the schedule line and the "by next run" hint are a little darker than `#A1A1A6`. Unchanged since round 1.

## Fixed since round 2 (re-measured)
- Retrying instructions: 2 lines, no "Show more" (frames: text 41 pt tall, no toggle element).
- Task-view schedule line: "Every weekday at 9:00 AM". List rows keep "Weekdays at 9:00 AM".
- List amber and red are system orange and red again: "10:00" (255,156,51), "2:00" (255,71,75), failed result (231,60,63). Timeline failed node (255,66,69). Paused label (255,149,48). The failed-card tint matches the board.

## Build verified
The installed `LFG.app` binary on the sim is from 16:18:59. `shared/Tasks/TaskListViews.swift` (16:34), `TaskEditorViews.swift` (16:31) and `ScheduledTasksView.swift` (16:36) were all edited after that build. This report covers the 16:19 build only; any later source change is unverified until it is rebuilt.

## Files
- Pairs: `r3-list-01-needs-input.png`, `r3-list-02-active.png`, `r3-list-03-dock.png`, `r3-list-04-paused.png`, `r3-list-05-closed.png`, `r3-list-06-header-chevrons.png`, `r3-next-01…06`, `r3-paused-01/02`, `r3-failed-01/02/03`, `r3-retrying-01/02/03`, `r3-waiting-01/02/03`, `r3-answered-01-card.png`
- Full screens: `r3-full-list-top.png`, `r3-full-list-paused-closed.png`, `r3-full-view-{next,paused,failed,retrying,waiting,answered}.png`
- Raw: `raw-r3/`
