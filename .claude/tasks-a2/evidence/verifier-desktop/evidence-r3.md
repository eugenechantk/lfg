# Desktop Tasks (dA2-*): independent design verification, round 3

Verdict: **PARTIAL**. Structure, copy, glyphs, layout and surfaces now match the boards on every screen and every edit variant. The round-2 failures are fixed: the tone regression, the row insets and truncation, the host-strip seam, and the Monthly control.

What remains is a short list of small colour and spacing deltas, plus one toolbar inconsistency: the + button has no visible surface while the search button beside it does.

## Contents
1. Scope and method
2. List toolbar (now in scope)
3. List body and host strip
4. Task view (next run, failed, needs input)
5. Edit page (all variants)
6. Remaining deltas
7. Round-2 findings: status
8. Carry-overs / unverified
9. Files

## 1. Scope and method

- **Boards:** unchanged since 13:22, so the round-1 board captures and DOM dumps are reused.
- **App bundle:** rebuilt at 17:11:22.
- **Shots:** the list on the 8933 host, plus one 8932 shot for Paused and Closed. Tasks 14, 03 and 01. `--edit` on 14 and 32–44.
- **Colour:** all colours are sRGB (`app-r3/srgb/`). A round-trip test through the "Mi monitor" profile returns #FF9F0A, #FFB340, #FF6B61, #5BE37A and #32D74B within 1 level. So the colour deltas below are real, not artefacts of the conversion.
- **Scope changes this round:**
  - The list toolbar contents are in scope. Glass surfaces count as native, and the inactive-window limits still apply.
  - The host-strip label font is out of scope, but the strip's layout and surface are in scope.
- **Excluded as data:** names, times, counts, model names, fixture cron and day values, and the Sessions badge. The harness has no sessions, so a Sessions count of 0 hides that badge.

## 2. List toolbar (`pairs-r3/list-toolbar-strip.png`, `pairs-r3/list-toolbar-zoom.png`)

| Component | Result | Measured, design vs app |
|---|---|---|
| Switcher | PASS | Container 158×32 at x=121, y=10 (board 180×32; the 22px difference is the Sessions badge, which is absent as data). Selected "Tasks" segment 76×26 at y=13 (board 78×26). |
| Tasks badge | PASS (minor tone) | 16×16 at x=249, y=18 (board 16×16 at 253,18). Digit is dark (26,18,2). Fill **(255,158,50)**, board #FF9F0A (255,159,10). |
| Search button | PASS (native) | Glass circle 35×35 at x=313 (board 30×30 at x=320). Glyph 12×12. |
| + button | **PARTIAL** | The glyph is present at x≈367, but there is **no visible circular surface**: background (49,49,49) on a (48,48,48) band. The board draws a 30×30 circle like the search button's. The search button in the same inactive capture does show its surface, so the inactive state does not explain the difference. |
| No ••• button | PASS | Matches the board. |
| Titlebar band | unverified | The band behind the toolbar renders (48,48,48), the page (26,26,30). The board is #1B1B1E throughout. This may be inactive-window chrome; it needs a key-window check. |

## 3. List body and host strip

| Component | Result | Measured |
|---|---|---|
| Host strip: surface | PASS | (26,26,30), the same surface as the list. The seam is gone. |
| Host strip: layout | PASS | Dot and label chips from x=16, then "· 1 running", hairline, 30px tall. The connected/offline dot colours and the "All hosts" filter are untested: the strip's hosts come from the local config, unresolved, and there is a single task host. |
| Section headers | PASS | Chevron 6×4 at x=20; label at x=37. |
| Rows | PASS | Time at x=17, title at x=75 (board 16 / 74). Chevron at x=376–380 (board 378–382). Pitch 74 (board 75). Separators x=74–399, matching the board. |
| Paused row text | PASS | "Paused by you · Oct 8 · its run time has passed" is shown in full (`pairs-r3/list-paused.png`). |
| Tones | PASS | Amber (255,179,63) = #FFB340. Red (255,106,97) = #FF6B61. "Now" and running text (90,227,122) = #5BE37A. Running dot (47,209,88) ≈ #32D74B. ✓ is #5BE37A. |
| Glyphs | PASS | Question glyph is now a plain bubble; ✕ and ✓ at board size. |
| Paused / Closed | PASS | |
| Internal consistency | PASS | Uniform from the strip down. |

## 4. Task view

| Screen / component | Result | Measured |
|---|---|---|
| Next run: header, chips, card, Run now / Pause, instructions, runs, ↗, bottom button | PASS | Card fill #26262B. Run now #3B8EFF. Accent #8FB8FF. Timeline text red (255,106,97). |
| Timeline nodes | minor | Done node **(90,227,122)** vs board #32D74B (50,215,75). Failed node **(255,106,97)** vs board #FF5A50 (255,90,80). Round 2 had the done node near #32D74B; it now uses the text green. |
| Last run failed | PASS | Border (114,57,55), fill (50,35,37), label (255,106,97), 17pt title, Ask to fix ↗, "Fix or change with chat", full instructions. |
| Needs input: card, label, question, context, footer "on Pro", instructions | PASS | Border (115,84,44), fill (50,41,34), label #FFB340, context line pitch 19. |
| Needs input: Answer in iTerm | **minor tone** | Fill **(255,146,48)** vs board #FF9F0A (255,159,10). Visibly redder in `pairs-r3/input-card.png`. |
| Needs input: dot | minor tone | (255,146,48) vs #FF9F0A. |
| Needs input: card spacing | minor | Question to button 69px (board 75). Card height 202 (board 216). |
| Spacing below Show more | minor | Runs block sits about 4–5px higher than the board. |

## 5. Edit page (tasks 14, 32–44)

Every variant matches on structure, copy, chip formats and accent tokens: once, 5min, 7min, 5hours, hourly, daily, 3days, 3days-after, weekly, monthly, custom, after-n, on-date and weekdays. The page rows are byte-for-byte at the same y positions as round 2.

- **Monthly:** now reads "On the 16th at" as one label with a time pill, matching the board's row. The extra spacing and control are gone. `pairs-r3/edit-monthly-row.png`
- **Weekday dots:** selected (244,244,246) = #F4F4F6. Fixed.
- **Ends labels:** (244,244,246) vs board white (255). Negligible.
- **Spacing (minor, unchanged):** gaps between cards 51px (board 44–45). Name row 52px (board 59). Time-zone row 39px (board 35).

Full-page pairs: `pairs-r3/full-edit*.png`.

## 6. Remaining deltas (all minor)

| # | Where | Design | App |
|---|---|---|---|
| 1 | List toolbar + button | 30×30 circle surface, like search | No visible surface; search has one |
| 2 | Answer in iTerm fill, waiting dot | #FF9F0A (255,159,10) | (255,146,48) |
| 3 | Tasks badge fill | #FF9F0A | (255,158,50) |
| 4 | Timeline done node | #32D74B | (90,227,122) |
| 5 | Timeline failed node | #FF5A50 | (255,106,97) |
| 6 | Waiting card spacing | question→button 75, height 216 | 69, 202 |
| 7 | Edit card gaps / Name row / time-zone row | 44–45 / 59 / 35 | 51 / 52 / 39 |
| 8 | Task view runs block | — | about 4–5px higher |

## 7. Round-2 findings: status

All fixed:
- Danger and warning tone regression.
- Row insets and the "…pass…" truncation.
- Separator extent.
- Host-strip surface seam.
- Monthly inline control.
- Selected weekday-dot fill.
- Success green for Now, running text and ✓.

Still open: the Answer in iTerm fill (now joined by the waiting dot), the card and spacing minors, and the done-node green (newly drifted).

## 8. Carry-overs / unverified

- Titlebar band colour and any key-window rendering, including whether the + surface appears once the window is active.
- Host-strip connected/offline states and the "All hosts" filter (single task host).
- The Sessions badge (no sessions in the harness).
- "Open session in iTerm" and the "2nd in a row" label (fixture limits).
- The fade over scrolled content.
- Interactive states.

## 9. Files

- `app-r3/` (raw), `app-r3/srgb/` (sRGB)
- `pairs-r3/` (design left, app right)
