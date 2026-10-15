# Desktop Tasks (dA2-*) — independent design verification

Verdict: **FAIL**. The layout skeleton matches on every screen. The failures are specific: toolbar and host-strip structure on the list, copy and glyph details in the task view, the failed and waiting cards, and one root cause in the edit form (it uses the system accent instead of the board's accent tokens). Each delta is listed below with measured values.

## Contents
1. Scope and method
2. Global findings
3. List
4. Task view (next run)
5. Task view (last run failed)
6. Task view (run needs input)
7. Edit page (all variants)
8. Confirmed correct
9. Carry-overs / unverified
10. Files

## 1. Scope and method

- Design ground truth: the boards rendered in Chrome at `http://127.0.0.1:8931/` (1x, 400 px wide). Computed styles came from the rendered DOM of every board. The full dumps are in `design/dom/*.txt`. Glyph strokes came from the board source, because they are SVG attributes. Stitched board captures are in `design/*.png`.
- App: `mac_shot.sh shot … --onscreen` against the stand-in host on 8933. List, task 14, 03, 01 (and 07), and `--edit` for 14 and 32–44. One extra list shot used the base stand-in host on 8932 (the same harness, read-only), because the 13 variant tasks on 8933 push Paused and Closed below any window that fits the screen. Raw shots are in `app/*.png`.
- **Colour space:** screencapture tags its PNGs with the display profile ("Mi monitor"). All app colours below are measured after conversion to sRGB (`app/srgb/*.png`). Raw pixels read about 6 levels darker and are not comparable to CSS values. As a check, "Needs input" amber converts to (255,179,63), and the board token is #FFB340.
- Comparison: paired crops per component (`pairs/*.png`, design left, app right, scaled ×2 unless noted), plus pixel-run and ink-band measurements.
- Excluded as data: task names, times, counts, model names, instruction length, cron/day values of the fixture tasks.
- Capture limits (from the caller, applied): no key window. Traffic-light colours and the toolbar Save fill are not judged. No menus, hover or editing states.

## 2. Global findings

| # | Finding | Design | App (sRGB) | Status |
|---|---|---|---|---|
| G1 | Window/page background | #1B1B1E (27,27,30), cool tint | (48,48,48) neutral on list, task and edit pages | FAIL* |
| G2 | Card fill | #26262B opaque | white 7% over G1 → (63,63,63) | follows G1 |
| G3 | Edit-form accent | text #8FB8FF, fill #3B8EFF | system accent (1,122,255) everywhere in the form | FAIL |

\*G1 caveat: the app sets no page background. A plain SwiftUI List in a shell-launched (inactive) test window also measured (49,50,50), while `NSColor.windowBackgroundColor` in dark mode is (30,30,30). So part of G1 may be inactive-window rendering. The capture method cannot make the window key (`NSApp.activate` failed in a probe), so this could not be settled. Either way, the app does not set the board's #1B1B1E.

G3 is one root cause behind many edit-form rows (E5, E8, E11, E12, E13). The task view uses the correct tokens: "Show more", "Next", "Retry", "Pause" and the chat icon all measure (143,184,255) = #8FB8FF, and Run now measures (59,142,255) = #3B8EFF.

## 3. List (`dA2-list` vs `app/list.png`, `app/list-base-8932.png`)

| Component | Criterion | Result | Measured delta |
|---|---|---|---|
| Window toolbar | Structure | FAIL | Board: Sessions/Tasks switcher **with count badges** (Tasks badge = Needs input count 2) + search button + `+` button (30×30 each). App: switcher only, **no badges**; search and `+` are folded into a `•••` menu that the board does not have. |
| Window toolbar | Shape | native | App switcher 140×36 at x=130 vs board 180×32 at x=103. |
| Host strip | Presence | FAIL | Board row y=52–82: "● Pro ○ Air offline · 1 running" + "All hosts" filter + hairline. App: **no host strip at 400 pt** (the connection header only shows at ≥500 pt width). |
| Section headers | Glyph/position | PARTIAL | Chevron 9×6 px at x=10 vs 7×5 at x=20. Label x=30 vs 37. Colours ✓ (amber / grey), sizes ✓. |
| Rows | Rhythm | FAIL | Row pitch **82 vs 75 px** (+7 per row). |
| Rows | Insets | FAIL | Content starts x=8 vs 16 (time column). Title x=66 vs 74. Chevron right edge x=389 vs 382. |
| Rows | Typography/colour | PASS | "Release verification" ink width 131 vs 132 px (14/600). Time 15/semibold. Tones ✓. |
| Rows | Chevron | PARTIAL | App chevron (63,63,65) on (48,48,48) is barely visible. Board #5A5A62 on #1B1B1E is clearly visible. |
| Rows | Result glyphs | PARTIAL | Failure ✕ 11×11 px vs 7×7 px. Success ✓ larger than the board. Question glyph is `questionmark.bubble` (with "?") vs a plain speech bubble. |
| Row separators | Extent | FAIL | App hairline spans **x=8–399** (full width). Board runs from the title column, **x=74–400**. |
| Paused / Closed | State | PASS | Grey times, blank time for a passed Once, pause glyph, "Paused by you · <date>", Closed collapsed with ›. |
| Internal consistency | Uniformity | PASS | Background uniform (48,48,48) from y=52 to the bottom. No seams or bands. |

Crops: `pairs/list-toolbar.png`, `pairs/list-needs-input.png`, `pairs/list-active.png`, `pairs/list-paused.png`, `pairs/list-row-glyphs-zoom.png`, `pairs/full-list.png`.

## 4. Task view, next run (`dA2-detail` vs task 14)

| Component | Result | Measured |
|---|---|---|
| Toolbar back + Edit/••• pill | PASS (native) | Back 36×36 at x=96 vs 30×30 at x=78. Pill 70×36 vs 68×30. These are system toolbar metrics. Pencil is the SF symbol. |
| Title, schedule line, chips | PASS | Title band y=63–84 vs 63–83. Schedule y=97–110 vs 96–111. Chips 24 px tall ✓. Page inset 20 vs 18 px (minor). |
| Status card | PASS | Card x=20–379, y=163–295 vs 18–382, 161–296. Buttons 160/161 wide vs 164. Run now fill (59,142,255) = #3B8EFF ✓. Label, title and sub sizes ✓. |
| Instructions + Show more | PASS | 20 px line pitch ✓. Show more #8FB8FF ✓. |
| Runs header + count | PASS | |
| Timeline, upcoming | PASS | 33 px pitch ✓. Hollow nodes ✓. "Next" #8FB8FF ✓. |
| Timeline, past rows | **FAIL** | Trailing glyph is **"6 min ›" vs "6 min ↗"**. The board's ↗ says the run opens in iTerm. 51 vs 52 px pitch ✓. |
| Change with chat + caption | PASS | Button x=14–385, 40 tall ✓. ↗ ✓. Caption copy ✓. |
| Internal consistency | PASS | Page uniform. No seam around the bottom button. |

Crops: `pairs/detail-header.png`, `pairs/detail-card.png`, `pairs/detail-instructions-runs.png`, `pairs/detail-bottom.png`, `pairs/detail-toolbar-zoom.png`.

## 5. Task view, last run failed (`dA2-detail-failed` vs task 03)

| Component | Result | Measured |
|---|---|---|
| Card container | **FAIL** | Board: fill rgba(255,90,80,0.08) **+ 1 px border rgba(255,90,80,0.28)**. App: **no border**. Fill (89,59,57) on (48,48,48) is about 17% tint vs 8%, so the card reads as solid brown. |
| Card label | **FAIL** | App adds an `xmark.circle` glyph before "LAST RUN FAILED". The board has no glyph. |
| Card title | **FAIL** | App title is 19 pt (ink band 19 rows). Board failed title is **17px/650**. Only the next-run title is 19. |
| Reason, "Open session in iTerm ↗" | data | Fixture run has no session ("no session started"). The link's absence is consistent with the data. Not verifiable here. |
| Retry now / Ask to fix | PARTIAL | **"Ask to fix" lacks the trailing ↗** (board: "Ask to fix ↗"). Retry ✓. |
| Footnote | PASS | Clock glyph + "Schedule still on. Next run: …" ✓. The date wording depends on the data. |
| Instructions | **FAIL** | App clamps to **2 lines with "…"**. The failed board shows the full text with no clamp (`<p>` has no line-clamp on this board). |
| Timeline | as §4 | Same › vs ↗ delta. |
| Bottom button | **FAIL** | Copy: **"Change with chat" vs "Fix or change with chat"**. |

Crops: `pairs/failed-card.png`, `pairs/full-detail-failed.png`.

## 6. Task view, run needs input (`dA2-detail-input` vs task 01)

| Component | Result | Measured |
|---|---|---|
| Card container | **FAIL** | Board: rgba(255,159,10,0.08) + **1 px border rgba(255,159,10,0.3)**. App: no border. Fill (89,73,52), about 17% tint. |
| Label row | PASS | Dot + halo, "RUN IS WAITING FOR YOU" amber, wait time right-aligned. |
| Question title | PASS | 17 pt. Ink width 217 vs 221 px. |
| Context text | PARTIAL | Line pitch **16 vs 19 px**. |
| Answer in iTerm | **FAIL** | Fill **(255,179,63) #FFB340 vs #FF9F0A**. This is a custom capsule, not an AppKit prominent button, so its fill is judgeable. Height 36 ✓, terminal glyph ✓. |
| Footer copy | **FAIL** | "The run's session is open in tmux. It continues…" vs board "…open in tmux **on Pro**. It continues…". Pitch 15 vs 16. |
| One-time footnote | PASS | |
| Instructions | **FAIL** | Clamped to 2 lines with "…". The board shows 3 full lines, no clamp. |
| Change with chat | PASS | |

Crops: `pairs/input-card.png`, `pairs/full-detail-input.png`.

## 7. Edit page (`dA2-edit*` vs tasks 14, 32–44 with `--edit`)

Rows shared by all variants:

| # | Component | Result | Measured |
|---|---|---|---|
| E1 | Toolbar Cancel / title / Save | PARTIAL | App draws "Edit task" **inside a glass capsule** (54×36 at x=173), centred on the window (x≈200). Board: plain 13/600 text centred between Cancel and Save (x≈237). Cancel 59×36, Save 64×36 vs 66×30 and 58×30 (native heights). Save fill not judged. |
| E2 | Name / Instructions card | PARTIAL | Instructions line pitch **17 vs 20 px**. Name label/value ✓. |
| E3 | Once · Repeat segmented | PASS | |
| E4 | Sentence + how-it-runs line | PASS | Copy matches on every variant (data aside). Sentence→subline 20 vs 23 px. |
| E5 | Preset chips | FAIL | Selected fill **(1,122,255) vs #3B8EFF**. The strip clips at the content inset (x≈370), so "Weekly" shows as **"Weekl"**, even when it is the selected chip (weekly variant). The board clips at the card edge (x=384) and shows "Weekly". |
| E6 | Weekday dots | PASS | About 28×24 vs 30×26. Selected fill (228) vs (244,244,246). Minor. |
| E7 | Every N field | PASS | Blue ring, 56×28, unit label ✓. |
| E8 | Time / Starts pills | FAIL | Pill text **(1,122,255) vs #8FB8FF**. |
| E9 | Ends segmented | PARTIAL | Unselected labels (202,202,202) vs white. |
| E10 | Number of runs / End date | FAIL | App inserts a **divider between "Ends" and its sub-row** (3days-after y=561, after-n y=556, on-date y≈558). The board keeps them in one block (no border until "Next runs"). On-date pill reads **"Thu, Dec 31" vs "Thu, Dec 31, 2026"**. "Last run: …" copy ✓. |
| E11 | Next runs chips | FAIL | Text (1,122,255) vs #9CC2FF. **Format:** board "Fri 9:00" (daily, weekdays, weekly, after-n, on-date) → app "Fri 9:00 AM". Board "10:15" (5min) → app "3:50 PM". Board "Nov 1 · 9:00" (monthly) → app "Oct 16" (time dropped). 7min, 5hours, hourly and 3days formats ✓. Count: hourly and monthly show 4 chips vs 3. |
| E12 | Time zone · Change | FAIL | "Change" (1,122,255) vs #8FB8FF. |
| E17 | Runs on card | PASS | Host dot, mono folder, Agent segmented, Model row ✓ (model value is data). |
| E18 | Internal consistency | PARTIAL | Surfaces uniform, no seams. Only the chip-strip clip in E5. |

Variant-specific:

| Variant | Result | Notes |
|---|---|---|
| once (32) | FAIL | **No divider above the calendar** (board border-top at y=373). Month label **blue (1,122,255) vs white #F4F4F6**. Calendar row pitch **32 vs 28 px**. Selected day #007AFF-ish vs #3B8EFF. "15" and arrows system blue vs #8FB8FF. Shortcut chips + "Runs once…" ✓. `pairs/edit-once-calendar.png` |
| 5min (33) | PARTIAL | E11 format "3:50 PM" vs "10:15". Rest per shared rows. |
| 7min (34) | PASS* | *Shared rows E5/E8/E11-colour/E12 only. Starts row ✓. Chip format ✓. |
| 5hours (35) | PASS* | As above. |
| hourly (36) | PARTIAL | "At minute" row ✓. 4 chips vs 3. |
| daily (37) | PARTIAL | E11 format. |
| 3days (38) | PASS* | `pairs/edit-3days-when.png` |
| 3days-after (39) | FAIL | E10 extra divider. `pairs/edit-3days-after-ends.png` |
| weekly (40) | FAIL | Selected "Weekly" chip clipped to "Weekl". E11 format. |
| monthly (41) | FAIL | App row is "On the [16th] at" with an **extra day-picker pill**. Board row is the label "On the 1st at" + time pill only. Chips drop the time. `pairs/edit-monthly-row.png` |
| custom (42) | FAIL | Cron field: **no 1 px #3B8EFF border**. Bg (48,48,48) vs #1E1E22 on card. Mono text about 16–17 pt (10 px advance) vs **13 px** (8 px advance). Height 28 ✓. Sentence: the fixture cron shows "Custom schedule". Running the app's own describer (LFGCore, compiled ad hoc) on the board's cron `30 8 1,15 * *` returns "On days 1 and 15 of every month at 8:30 AM" vs the board "At 8:30 AM on the 1st and 15th of every month". This is derived, not rendered. `pairs/edit-custom-cron.png` |
| after-n (43) | FAIL | E10 extra divider. Copy ✓. |
| on-date (44) | FAIL | E10 divider + missing year. `pairs/edit-on-date-ends.png` |
| weekdays (14) | PARTIAL | Shared rows only. `pairs/edit-top.png`, `pairs/edit-when.png`, `pairs/edit-runs-on.png` |

## 8. Confirmed correct

- Every screen has the right sections in the right order. The list has four groups with Closed collapsed. No buttons in rows.
- Task view: header, chips, next-run card (tokens exact), instructions clamp + Show more, timeline nodes and pitch, bottom "Change with chat" button and caption.
- Failed state shows on a first failure (streak 1, no "2nd in a row" label), with Retry now / Ask to fix and the "Schedule still on" footnote.
- Waiting state shows the question and context with a single "Answer in iTerm" button, no options and no text field.
- Edit form: Once/Repeat, presets, Every field, Starts only on exact-gap variants, At minute for hourly, weekday dots for weekly and weekdays, Ends segmented, Number of runs and Last run, Next runs, time zone row, Runs on with Agent and Model rows, Cancel/Save in the title bar. Sentences and "how it runs" lines match the board wording for every variant except custom.

## 9. Carry-overs / unverified

- G1 background: inactive-window rendering could not be excluded (see §2).
- Traffic lights, Save fill, and any key-window toolbar styling: capture limit.
- "Open session in iTerm ↗" in the failed card and the "2nd in a row" streak label: the fixture has no session and a streak of 1.
- Bottom fade gradient over scrolled content: no scrolled state is reachable.
- Interactive states (menus, host filter, popovers, editing focus).
- Custom sentence for the board's cron: derived from app code, not rendered (fixture cron differs).
- Paused/Closed came from the 8932 host. The 8933 list pushes them below the screen height.

## 10. Files

- `design/*.png`: stitched board captures (1x, Chrome).
- `design/dom/*.txt`: computed-style dumps per board.
- `app/*.png`: raw harness shots. `app/srgb/*.png`: the same, converted to sRGB (use these for colour).
- `pairs/*.png`: paired crops, design left, app right.
