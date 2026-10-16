# Phase 4 r2: visual verification of the desktop sessions list against `dA2-sessions`

**Verdict: FAIL.** One confirmed delta remains (F1). When the Working group is collapsed, the app still shows its "by last activity" hint. The board hides it.

Everything else matches the board to 1pt, or is covered by an accepted exception. That includes the time column, which r1 failed. The title-bar hairline from r1 appears only in the off-screen inactive render; the on-screen captures have none.

## Scope and provenance

| Item | Value |
| --- | --- |
| Scope | Live harness render of the real desktop window (`--window-shot --board`), compared with a rendered HTML board. Five states: all expanded; Working, Needs input or Recent collapsed; all collapsed. Visual only. The click-to-toggle behaviour was not exercised (G1). |
| Reference | HTML board `http://127.0.0.1:8793/dA2-sessions.dc.html`. Saved copy `reference-dA2-sessions.dc.html`, sha256 `987f9d9c…db5a8`. `support.js` saved as `reference-support.js`, sha256 `3f160299…0f10`. No other assets: no images, fonts from the system. |
| Renderer | Chrome 154 via claude-in-chrome, a new tab of my own. DPR 1, viewport 1135×1266, `document.fonts.status = loaded`. Root `div` 400×860 at (0,0). |
| Board states | Driven by the board's own header buttons (`button[aria-expanded]` `.click()`), checked by `aria-expanded` after each change. Captured with the zoom tool at native resolution: 480×1032 PNG, 1 px = 1 CSS px, no ICC profile. The window is x 0–400, y 0–860. Board colours match the CSS to 1 level (bg 26,26,30 for #1B1B1E; amber 255,159,11 for #FF9F0A). |
| Board DOM | One query per state inside the 400×860 root: box, text box, colour, background, font size and weight, line height, radius, borders, opacity, shadow, numeric variant. Files `board-dom-<state>.tsv` (180 / 130 / 146 / 135 / 51 elements). |
| Implementation | `desktop/build/lfg.app/Contents/MacOS/lfg`, built Oct 16 13:54:32, sha256 `232fb38e…a45b`. It is newer than every desktop source file (`LFGSessions.swift` 13:53:40, `SessionsListS2.swift` 13:51:17, LFGCore `DesktopSessionList.swift` 13:01:16). Worktree HEAD `395f804` with uncommitted desktop edits. Host Eugenes-MacBook-Pro, macOS 26.6. Not rebuilt; `/Applications/lfg.app` not touched. |
| App captures | `lfg --window-shot 400 <png> --height 860 --board [--collapse <groups>]`. Each is 400×912 at 1x: a 52pt title bar plus 860pt of content. Embedded profile "Mi monitor". Converted to sRGB from that profile (ImageCms, relative colorimetric) into `*-srgb.png`. All colour readings use the converted files. |
| On-screen captures | Supplied, not taken by me: `phase4-r1-fixes/onscreen-win-active-top.png` and `onscreen-win-inactive-top.png`, 568×400, written 13:55:52 (after the build). They show live data ("No sessions."), and a notification banner covers x 208–552, y 15–105, including the switcher and search button. I used them only for the title-bar shade, the hairline check and the window buttons. sRGB copies are in this folder. |
| Alignment | Board and app images are top-aligned in one coordinate system, title bar included. No per-component offsets. |
| Exceptions applied | 1x rounding (about 1pt, more where rounded sizes add up). Native window buttons (size, spacing, colour, inactive grey). The harness's inactive drawing (title-bar shade and any hairline seen only off-screen). Text metrics. Icon rasterisation. Tolerance: 1.5pt or less is an observation; colours within a few levels. |

## Method

1. **Element table.** For every text node, SVG, dot and ring in each board DOM dump, `tools/measure.py elements` finds the ink box and core colour in the board image and the app image. It searches the same region in both (DOM box, +4 px horizontally, +2 px vertically). Results are in `element-compare-<state>.tsv`. Ink is compared with ink, so CSS line boxes do not need converting.
2. **Pixel scans.** `tools/scan.py` reads run-length colours along rows and columns, and ink runs inside boxes. It covers fills, edges, separators, glyph spacing and hints. The plans are in `tools/plan-*.txt`; the outputs are in `scan-chrome-expanded.txt`, `scan-text-expanded.txt` and `scan-collapsed.txt`.
3. **Crops.** `pairs.json` produced 30 native-resolution pairs (`crops/`, with `index.json` hashes and review sheets). `zoom/` holds magnified stacks, board on top and app below. These are for viewing only; every number comes from the native images.

## Findings (deltas)

**F1. Working, collapsed: the app still shows the "by last activity" hint. The board hides it.**
- Board: the hint area of the Working header has no ink when the group is collapsed (x 290–395, y 280–306 in `board-collapse-working`; y 129–155 in `board-collapse-all`). The board's script sets the hint to empty when a group is collapsed, and the rendered DOM has no hint span.
- App: the hint is drawn in both collapsed states. Collapse-working: glyph runs x 309–383, y 289–299. Collapse-all: x 309–383, y 138–148. These are the same position and colour (136,135,144) as in the expanded state.
- **Board: no hint / app: "by last activity" at x 309–383** whenever Working is collapsed. Measured with ink runs (`scan-collapsed.txt`, rows `hint_area_working*` and `seps_col380`).
- Crops: `crops/20-header-working-collapsed-*`, `crops/21-collapse-working-context-*`, `crops/29-headers-all-collapsed-*`, `crops/22-…` and `crops/30-…` (whole window). Zooms: `zoom/20-header-working-collapsed-zoom3x.png`, `zoom/29-headers-all-collapsed-zoom3x.png`.
- Needs input and Recent have no hint, so their collapsed headers match.
- Hypothesis, not checked in source: the header draws the hint whether or not the group is expanded.

## Observations (within tolerance or covered by an exception)

- **O1. r1's time column (F1) is fixed.** Every label now sits in one column. "1m": board "1" at x 17–22 and "m" at 26–37; app 17–22 and 25–37. "1d": "d" at 26–33 against 25–32. Right edges 37/37 for every "Nm" label. Residual is 1pt or less.
- **O2. r1's title-bar hairline (F2) is in the harness only.** The harness draws row y 51 at 35,35,35 between a 30,30,30 title bar and the 26,28,30 host strip. Both on-screen captures (active and inactive) read 26,26,30 continuously from y 1 to 81, and the list border at y 82 (44,44,47). That matches the board (26,26,30, border at 82). It is covered by the inactive-drawing exception.
- **O3. Window buttons are native.** App and on-screen: 14pt circles at x 19–32 / 42–55 / 65–78, y 19–32 (pitch 23). Board: 12pt at x 14–25 / 34–45 / 54–65, y 20–31 (pitch 20). The vertical centre is the same (25.5). The first button starts 5pt further right. These are the system's own size, spacing and inset, covered by the exception. On screen the active window shows red, yellow and green (255,92,95 / 250,200,0 / 52,199,89) and the inactive window shows grey (65,65,69).
- **O4. Title bar shade.** Harness 30,30,30 against board 26,26,30. On screen it is 26,26,30, active and inactive. Covered by the inactive-drawing exception.
- **O5. The right-hand title-bar items are 1pt right.** Capsule x 122–302 against 122–301. Tasks badge 273–288 against 272–287. Search circle 359–388 against 358–387, and its glyph 368–379 against 367–378. The Sessions segment (125–221) and its badge (195–210) match exactly. Vertical positions match.
- **O6. Host strip.** The dot, "Pro" and "Air offline" match to 1pt. The ring is x 63–69 against 62–68, and it has an anti-aliased stroke of about 1.5pt; Chrome snaps the CSS 1.5px border to 1px. The "·" in "· 3 working" is x 142–143 against 140–142, so its centre is about +1.5pt; "3" and "working" are +1. "Air offline" ends at 131 in both, so this is the U+00B7 glyph's side bearing (text metrics).
- **O7. Rows of text sit 0–1pt lower in the app.** Titles and meta are +1, status lines 0/+1, "ago" −1/0. One title per state lands +2 at board y 433: "Fix queued message reconciliation" in collapse-working, "Polish onboarding copy" in collapse-needsInput. In those rows the meta is +1 and the status 0, and the separators around them are identical. That is 1x rounding of the board's fractional row (75.27) and header (37.55) heights.
- **O8. Separators.** Expanded: board 82/195/270/383/458/533/646/722/797, app the same except 534 for 533. Collapse-working: 82/195/270/420/496/571 against 421 for 420. Collapse-needsInput: identical (232/308/383/496/571/646). Collapse-recent: 533 against 534. Collapse-all: only the list border at 82, in both. Every row separator runs x 62–400 in both; the list border runs the full width.
- **O9. Colours.** List background 26,28,30 against 26,26,30 (2 levels; 26,26,30 on screen). "ago" core 134,134,143 against 138,138,147 (4 levels on 11pt glyphs). Header counts 136,136,145 against 138,138,147. The By status chevron is 194,196,204 against 201,203,211 on 5×3 px of ink (icon rasterisation). Everything else is within 1–2 levels: ink 244,244,246; meta 168,168,176; amber 255,179,63; green 90,227,122; grey 138,138,147; dimmed row 144/103 levels; badges 255,159,11 and 237,148,20.
- **O10. Chevrons.** Header chevrons match to the pixel, open (x 20–26, 5 rows) and closed (x 21–25, 7 rows), in every state. The By status chevron is 7×3 px against 5×4 (icon rasterisation).
- **O11. Window height.** The harness window is 912pt (860 content + 52 title bar); the board window is 860 including its title bar. The extra 52pt at the bottom is empty background (no ink at y 798–911).

## Component × state × criterion matrix

P = PASS, F = FAIL, PT = PARTIAL, N/A = not applicable or no board reference. Numbers refer to findings (F) and observations (O).

| Component / state | Structure / layout | Copy | Typography | Colour | Glyphs | Spacing / shape | State: expanded | State: collapsed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Window controls | P (native, O3) | N/A | N/A | P (native, O3) | P (native) | P (native, O3) | N/A | N/A |
| Title bar surface | P (O2) | N/A | N/A | P (O4) | N/A | P (no hairline on screen, O2) | N/A | N/A |
| Sessions/Tasks switcher, Sessions selected | P (O5) | P | P | P (capsule 47,46,50 against 46,46,50; segment 85,85,88 both) | N/A | P (capsule 32pt tall; segment 125–221 exact; badges 16pt) | N/A | N/A |
| Search button | P (O5) | N/A | N/A | P (214,215,221 glyph; fill 47,46,50) | P (glyph 12×12 both) | P (30pt circle) | N/A | N/A |
| Host strip (Pro dot, Pro, offline ring, "Air offline", "· 3 working") | P (O6) | P | P | P (dot 51,215,76; ring 250,157,10; amber 254,179,63; grey 138,138,147) | P (O6) | P | N/A | N/A |
| By status pill | P (x 309–380, y 54–71 exact) | P | P | P (pill 42,42,44 against 42,42,45; text 200,202,210) | P (O10) | P | N/A | N/A |
| List top border | P (y 82, full width) | N/A | N/A | P (44,44,47 both) | N/A | P | P | P |
| Header: Needs input 2 | P | P | P | P | P (O10) | P | P | P (chevron right; rows removed; next header at 120.5/121) |
| Header: Working 3 + "by last activity" | P | P | P | P | P (O10) | P (hint right edge 383 both) | P | **F (F1)** in collapse-working and collapse-all |
| Header: Recent 43 | P | P | P | P | P (O10) | P | P | P (chevron right; rows removed; nothing below) |
| Row: needs input, question (2m) | P (O7) | P | P | P | P (ask icon 63–73 × 171–181 both) | P (separator 195) | P | N/A (whole group folds: P in collapse-needsInput) |
| Row: needs input, permission (6m) | P (O7) | P | P | P | P | P | P | as above |
| Rows: working ×3, incl. "from a task" | P (O7) | P | P | P (green time; dot 51,215,76 with glow 36,75,42, 13×13 both) | P | P | P | P (rows absent when folded) |
| Rows: recent closed ×2 | P (O7) | P | P | P | N/A | P | P | P (rows absent when folded) |
| Row: offline host, dimmed (2d) | P | P | P | P (title 144,145,147; meta 102,103,108; separator 35,37,39) | N/A | P | P | P (absent when folded) |
| Time column (all rows) | P (O1) | P | P (O1) | P (O9) | N/A | P (O1) | P | N/A |
| Whole window | P (O8, O11) | P | P | P (O9) | P | P | P | F (F1) |

Behaviour (clicking a header to fold or unfold it): not verified by me (G1).

## Coverage gaps

- **G1. Toggle interaction not exercised.** The collapsed states came from the harness's `--collapse` flag. I did not click a header in the app: the caller supplied off-screen capture only, with no screen access. The board's own toggle was exercised (each click flipped `aria-expanded` and removed the rows). The app's collapsed rendering is verified; its click path is not.
- **G2. Active-window rendering of the switcher and search button.** In the on-screen captures a notification covers them. Their colours come from the harness's inactive drawing only. That drawing matches the board to 1 level, and the exception covers inactive shade.
- **G3. Harness window, not the shipping scene.** The harness builds its own `NSWindow` with the board's sample data. The on-screen captures (live data) agree with it on the title bar, host strip position, list border and window buttons.
- **N/A (no board reference):** the search row, the By status menu when open, directory grouping, hover and pressed states, live-data rows.

## Timing (observed, HKT)

| Phase | Time |
| --- | --- |
| Preparation (scope, server check, build provenance) | 13:56–13:58 |
| App capture (5 harness runs, about 2 s each, sRGB conversion) | 13:58–14:01 |
| Design capture (render, 5 zoom captures, 5 DOM dumps) | 14:00–14:04 |
| Comparison (element tables, scans, crops, zooms) | 14:04–14:11 |
| Report | 14:11–14:15 |

Tool failures and recoveries (each once):
- I ran `lfg --help` to read the flags. It is not a CLI flag, so it launched a normal GUI instance of the worktree build. I stopped it within 2 minutes; no process was left. `/Applications/lfg.app` was not touched.
- The worktree hook rejected Bash commands with shell variables, loops and heredocs. Plain single commands worked.
- `to_srgb.py` writes beside its input, so the two on-screen sRGB copies first landed in `phase4-r1-fixes/`. I moved them here at once; that folder is back to its original files.
- Zoom captures with a `scale` below 1 also saved at the reduced size. I re-took them at full scale.
- I could not close my Chrome tab: no close tool is available, and `about:blank` was refused. Tab 1045567359 stays on the board, with all groups expanded.
- A loopback receiver on 127.0.0.1:8797 (`tools/recv.py`) took the DOM dumps as POSTs. It is stopped.

## Files

- App: `app-<state>.png` (raw), `app-<state>-srgb.png`. States: `expanded`, `collapse-working`, `collapse-needsInput`, `collapse-recent`, `collapse-all`.
- Board: `board-<state>-480x1032.png`, `board-dom-<state>.tsv`, `reference-dA2-sessions.dc.html`, `reference-support.js`.
- On-screen (sRGB copies of the supplied captures): `onscreen-win-active-top-srgb.png`, `onscreen-win-inactive-top-srgb.png`.
- Measurements: `element-compare-<state>.tsv`, `scan-chrome-expanded.txt`, `scan-text-expanded.txt`, `scan-collapsed.txt`.
- Crops: `pairs.json` and `crops/` (30 pairs, `index.json`, `review-01…07.png`). Viewing aids: `zoom/`.
- Tools: `tools/` (`measure.py`, `scan.py`, `to_srgb.py`, `zoom.py`, `gen_pairs.py`, `recv.py`, `plan-*.txt`).
