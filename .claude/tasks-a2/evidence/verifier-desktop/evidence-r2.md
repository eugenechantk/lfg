# Desktop Tasks (dA2-*): independent design verification, round 2

Verdict: **FAIL**, with far fewer deltas than round 1. The task view and the edit form now match the boards almost everywhere. Four problems drive the FAIL:

1. Round 2 introduced a colour regression: the danger red and warning amber tones changed away from the board tokens.
2. The list rows are inset differently from the board, and that now cuts off a paused row's text.
3. The new host strip sits on a different surface from the list below it.
4. Monthly has an extra inline control.

## Contents
1. Scope and method
2. List
3. Task view (next run)
4. Last run failed
5. Run needs input
6. Edit page
7. Round-1 deltas: status
8. Confirmed correct
9. Carry-overs / unverified
10. Files

## 1. Scope and method

- **Design:** the round-1 board captures and DOM dumps are reused (`design/*.png`, `design/dom/*.txt`). The boards in `.claude/tasks-a2/design/` were last modified 13:22, before round 1, so they did not change.
- **App:** the rebuilt bundle (binary built 16:36:33), captured with `mac_shot.sh shot … --onscreen`.
  - The 8933 host was used for the list, tasks 14, 03, 01 and 07, and `--edit` on 14 and 32–44.
  - The 8932 host was used for a list shot with Paused and Closed visible.
  - Raw shots are in `app-r2/*.png`. The sRGB conversions (`app-r2/srgb/*.png`) are used for every colour value below. The screencapture PNGs carry the "Mi monitor" profile.
- **Out of scope (coordinator):** the window toolbar's contents, meaning the switcher, its badges, and where search and + live. Everything below the toolbar is in scope, including the host strip.
- **Excluded as data:** names, times, counts, model names, instruction length, and the fixture cron and day values.
- **8932 data drift:** on the 8932 host, tasks 01 and 03 are now "Running", not Needs input as in round 1. This is data, not a delta.

## 2. List (`dA2-list` vs `app-r2/list.png` and `app-r2/list-base-8932.png`)

| Component | Result | Measured, design vs app |
|---|---|---|
| Host strip: structure | PASS | Dot + host label chips, then "· 1 running", then a 1px hairline. The strip is 30px tall at y=52–82, same as the board. |
| Host strip: surface | **FAIL** | The strip background is **(48,48,48)** and the list below is **(26,26,30)**, a two-tone seam at y=81. On the board the strip and list are one #1B1B1E surface. |
| Host strip: type | PARTIAL | Host labels are about 11pt medium, "Pro" ink 16×8. The board is 12px/400, ink 18×9. "· 1 running" is (169,169,169), board (138,138,147). |
| Host strip: state | data | The chips are "Pro" and "Air" with grey dots. They come from the local host config that the app re-reads on refresh, in an unresolved state. The board's connected and offline colours cannot be compared. The single task host means no "All hosts" filter, as the coordinator stated. |
| Section headers | PASS | Chevron 6×4 at x=20, board 7×5 at x=20. Label at x=37 in both. "by next run" hint present. Closed collapsed. |
| Rows: rhythm | PASS | Row pitch 74, board 75. |
| Rows: horizontal insets | **FAIL** | Time column starts at x=24, board 16. Title at x=82, board 74. Row chevron at x=367–371, board 378–382. |
| Rows: truncation | **FAIL** | Because of the insets above, "Paused by you · Oct 8 · its run time has passed" is cut to "…has pass…". The board shows the full line, ending at x=355. Crop: `pairs-r2/list-paused.png`. |
| Row separators | PARTIAL | The separator now starts at the title column, but it runs **x=82–390**. The board runs x=74–400, to the window edge. |
| Glyphs | PASS | Failure ✕ 7×7, check 8×7, chevron 5×8 in (89,89,98). These now match the board. The question glyph is about 9×9; the board's is about 12×11. |
| Tone: danger red | **FAIL (regression)** | Failed time "2:00" and the result line are **(255,66,69)**, board #FF6B61 (255,107,97). Round 1 measured (255,105,97). |
| Tone: warning amber | **FAIL (regression)** | The "Needs input" header, amber time and "Asks:" line are **(255,146,48)**, board #FFB340 (255,179,64). Round 1 was exact. |
| Tone: success green | PARTIAL | "Now", "Running · started…" and the ✓ are (47,209,88), board #5BE37A (91,227,122). This was already present in round 1, and I missed it there. |
| Paused / Closed | PASS | Grey times, blank time for a passed Once, pause glyph, "Paused by you · date". Closed is collapsed with ›. |
| Internal consistency | FAIL | The strip/list seam described above. Below the strip, the page is uniform (26,26,30). |

Crops: `pairs-r2/full-list.png`, `pairs-r2/list-host-strip.png`, `pairs-r2/list-needs-input.png`, `pairs-r2/list-active.png`, `pairs-r2/list-paused.png`, `pairs-r2/list-row-glyphs-zoom.png`.

## 3. Task view, next run (`dA2-detail` vs task 14)

| Component | Result | Measured |
|---|---|---|
| Page background | PASS | (26,26,30), board #1B1B1E. Uniform from y=52 to the bottom. |
| Title, schedule, chips | PASS | Title band y=63–84, board 63–83. Page inset 20, board 18 (minor). Chip fill (38,38,43), board about (43,43,46). |
| Next-run card | PASS | Fill (38,38,43) = #26262B. Card spans x=20–379 and y=163–295, board 18–382 and 161–296. Run now (59,142,255) = #3B8EFF. Pause fill (61,61,64). |
| Instructions + Show more | PASS | 20px line pitch. Show more is #8FB8FF. |
| Runs header, timeline | PASS | Upcoming rows 33px apart, past rows 51. "Next" and "Retry" are #8FB8FF. The trailing glyph is now **↗**. Everything below "Show more" sits about 4–5px higher than the board (minor). |
| Timeline failed node + text | **FAIL (regression)** | (255,66,69), board node #FF5A50 and text #FF6B61. |
| Change with chat + caption | PASS | Button x=14–385, 40 tall, fill (49,49,51), board about (48,48,50). ↗ and caption copy correct. |

Crops: `pairs-r2/detail-header-card.png`, `pairs-r2/detail-instructions-runs.png`, `pairs-r2/detail-bottom.png`.

## 4. Last run failed (`dA2-detail-failed` vs task 03)

| Component | Result | Measured |
|---|---|---|
| Card container | PASS | 1px border present, (114,42,44), board about (91,45,44) (slightly stronger). Fill (50,31,34), board about (45,32,35). |
| Label | PASS | "LAST RUN FAILED" with no glyph, (255,105,97). |
| Title | PASS | 17pt, ink band 17 rows, same as the board. |
| Reason / "Open session in iTerm ↗" | data | The fixture run has no session, so the link is absent. |
| Retry now / Ask to fix ↗ | PASS | Both buttons present, including the ↗ on Ask to fix. |
| Footnote | PASS | |
| Instructions | PASS | Full text, 3 lines, no clamp. |
| Timeline red | **FAIL** | Same regression as §3: (255,66,69). |
| Bottom button | PASS | Reads "Fix or change with chat ↗". |

Crops: `pairs-r2/failed-card.png`, `pairs-r2/failed-bottom.png`, `pairs-r2/full-detail-failed.png`.

## 5. Run needs input (`dA2-detail-input` vs task 01)

| Component | Result | Measured |
|---|---|---|
| Card container | PASS | Border (114,70,38), board about (95,66,24). Fill (49,37,32), board about (45,38,28). |
| Label row | PARTIAL | Label is #FFB340, matching the board. The dot is #FFB340 where the board uses **#FF9F0A**. |
| Question, context | PASS | 17pt question. Context line pitch 19, same as the board. |
| Answer in iTerm | **FAIL** | Fill **(255,146,48)**, board **#FF9F0A** (255,159,10). Height 36, matching the board. |
| Footer copy | PASS | "…open in tmux on Pro…". Line pitch 15, board 16. |
| Card spacing | PARTIAL | Question to button is 69px, board 75. Card height 202, board 216. |
| One-time footnote, instructions, bottom button | PASS | Instructions show the full 3 lines. |

Crops: `pairs-r2/input-card.png`, `pairs-r2/full-detail-input.png`.

## 6. Edit page (all variants, tasks 14 and 32–44)

Rows shared by every variant:

| Component | Result | Measured |
|---|---|---|
| Name / Instructions card | PASS | Instructions line pitch 20 px, same as the board. The Name row is 52px tall, board 59 (minor). |
| Mode segmented, sentence, how-it-runs line | PASS | Copy matches on every variant except custom, which differs only because the fixture cron differs. |
| Preset chips | PASS | Selected chip is #3B8EFF. The strip clips at the card edge, so "Weekly" is fully visible, including when selected. |
| Weekday dots | PARTIAL | Selected fill (225,225,226), board #F4F4F6 (244,244,246). Unselected fill (54,54,58), board about (55,55,60). |
| Every field, Time / Starts pills | PASS | Pill text #8FB8FF. Field ring #3B8EFF. |
| Ends segmented | PARTIAL | Labels are (227,227,228), board white. The selected segment fill (90,90,95) matches the board. |
| Number of runs / End date | PASS | No extra divider (Ends block 100–102px tall, board 103). The End date reads "Thu, Dec 31, 2026". |
| Next runs | PASS | Chip text #9CC2FF, chip fill (41,57,83). Formats match every board: "Fri 9:00", "4:40", "Fri 9:07 AM", "5:30 PM", "Oct 16", "Oct 16 · 9:00", "Oct 19 · 9:15". Hourly shows 3 chips. |
| Time zone · Change | PASS | Change link is #8FB8FF. |
| Runs on card | PASS | Card spans x=16–383 and y=720–879 (160px), board 16–384 and 162px. Rows are 40px each. |
| Vertical rhythm | PARTIAL | Each gap is within 4px of the board. The When card runs about 7px taller (time-zone row 39px, board 35), and the gaps between cards are 51px, board 44–45. |

Variant-specific:

| Variant | Result | Notes |
|---|---|---|
| once (32) | PASS | Divider above the calendar is present. Month label is white, the arrows and "15" are #8FB8FF, and the selected day is #3B8EFF. Calendar rows are 28px apart, same as the board. The calendar block is 197px, board 206. The arrows are heavier SF chevrons (minor). `pairs-r2/edit-once-calendar.png` |
| 5min, 7min, 5hours, hourly, daily, 3days, weekly, weekdays | PASS | Only the shared PARTIAL rows above apply. `pairs-r2/when-*.png` |
| 3days-after, after-n, on-date | PASS | `pairs-r2/when-edit-3days-after--edit-weekly.png`, `pairs-r2/when-edit-after-n--edit-on-date.png` |
| monthly (41) | **PARTIAL** | The row reads "On the  16th  at" with an inline day control: no chrome, but about 10px gaps around "16th". The board has only the label "On the 1st at" and a time pill. `pairs-r2/edit-monthly-row.png` |
| custom (42) | PASS | The cron field is 28px tall with a 1px #3B8EFF border and #1E1E22 fill. Its mono text has a 10px glyph height and 8px advance, which is 13px type, same as the board. The sentence "Custom schedule" depends on the fixture cron. |

## 7. Round-1 deltas: status

| Round-1 delta | Round 2 |
|---|---|
| Page background (48,48,48) | Fixed: (26,26,30) |
| Host strip missing | Fixed. New finding: its surface does not match the list (§2) |
| Row pitch 82, separators full width | Fixed: pitch 74, separators start at the title column. New finding: insets shifted +8 left and −11 right (§2) |
| Row chevron contrast, glyph sizes | Fixed |
| Past-run trailing › | Fixed: ↗ |
| Failed card border / tint / icon / 19pt title / Ask to fix ↗ / bottom label / instructions clamp | All fixed |
| Waiting card border / footer "on Pro" / context pitch / instructions clamp | Fixed |
| Answer in iTerm #FFB340 | Changed, still wrong: now (255,146,48), board #FF9F0A |
| Edit form uses the system accent | Fixed |
| Extra Ends divider, End date without year | Fixed |
| Chip formats, chip count, Weekly clipping | Fixed |
| Once divider, month label, calendar pitch | Fixed |
| Cron field border and font | Fixed |
| Monthly extra day pill | Partly fixed: the pill chrome is gone, but the inline control remains |
| Instructions pitch 17 in the edit form | Fixed |
| List toolbar switcher, badges, search, + | Out of scope this round |

## 8. Confirmed correct

- **Task view, failed and waiting states:** every round-1 structural and copy delta is fixed.
- **Edit form:** all 14 variants match the boards' structure, copy, chip formats and accent tokens.
- **Runs on card:** matches.
- **List:** the Paused and Closed sections match.

## 9. Carry-overs / unverified

- **Host strip connection states:** connected (green) and offline (orange) cannot be checked. The harness's strip shows hosts from the local config in an unresolved state.
- **Fixture limits:** the failed run has no session, so "Open session in iTerm" is untested. The failure streak is 1, so the "2nd in a row" label is untested.
- **Capture limits:** the bottom fade over scrolled content, interactive states, and anything that needs a key window.
- **Toolbar band colour (out of scope):** the titlebar renders (46–48,48,48) above the (26,26,30) page on every page. This is shell chrome, possibly in its inactive look, and is not counted.

## 10. Files

- `app-r2/` (raw), `app-r2/srgb/` (sRGB, use these for colour)
- `pairs-r2/` (design left, app right). `when-*.png` sheets put each variant's When card side by side.
