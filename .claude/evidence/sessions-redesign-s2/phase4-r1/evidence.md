# Phase 4 r1: visual verification of the desktop sessions list against `dA2-sessions`

**Verdict: FAIL.** One confirmed delta needs a code fix (F1). Two more need either an active-window capture or a decision from you (F2, F3). One board state was not verified (G1).

Everything else matches to 1pt or better. That covers layout, copy, colours, separators, row states, the switcher, the search button, the host strip and the By status pill.

## Scope and provenance

| Item | Value |
| --- | --- |
| Scope | Live harness render of the real desktop window versus a rendered HTML board. Static comparison of the board's pictured state, plus the board's interactive collapse state (see G1). |
| Reference kind | HTML: `http://127.0.0.1:8793/dA2-sessions.dc.html`. Copy: `reference-dA2-sessions.dc.html`. sha256 `987f9d9c3f6bb50015aa725234a71a83a796c8a12ed8483ed179d747f32db5a8`. Its `support.js` sha256 is `3f160299989dc595cf434dac7b7f3e6fd20ed015a2d99e075c3eac09dffe0f10`. |
| Renderer | Chrome 154 (claude-in-chrome, new tab), DPR 1, viewport 1135×1266. Root `div` 400×860 at (0,0). Fonts `loaded`. |
| Board captures | `board-zoomcapture-438x942.png` is the default state, native 1 px = 1 CSS px. The window is x 0–400, y 0–860. sha256 `ad80760b…5447`. `board-working-collapsed-438x942.png` has Working collapsed (sha256 `26924f47…790b`). The capture has no ICC profile. Board colours match the CSS to ±1 level, for example bg 26,26,30 against CSS #1B1B1E. |
| Board DOM | `board-dom-spec.txt` has 184 elements: box, own text box, colour, background, font size and weight, line height, radius, borders, opacity and shadow. It came from one query in the root. |
| Implementation | `desktop/build/lfg.app` was built Oct 16 13:16:01. The binary sha256 is `dee72af3…57e3`. The source is `LFGSessions.swift`, mtime 13:15:09, so the build contains it. The worktree is at HEAD `395f804` with uncommitted desktop edits. macOS 26.6.2. |
| App capture | `lfg --window-shot 400 app-board-400x860.png --height 860 --board` gives a 400×912 image: a 52pt title bar plus 860pt of content, at 1x. sha256 `8d640c78…ca24`. |
| Colour | The embedded profile is **"Mi monitor"**, the main display's profile, not Display P3. It was converted to sRGB from that profile with ImageCms (relative colorimetric): `app-board-400x860-srgb.png`. The converted values match the board CSS: amber 255,159,11 (#FF9F0A), ink 244,244,246, meta 168,168,176, separator 44,44,47. |
| Alignment | Both images are top-aligned in the same coordinates, title bar included. No per-component offsets were used. |
| Exceptions applied | 1x rounding (about 1pt; more where rounded widths add up along a row). Inactive window: grey window controls and a lighter title-bar shade. Text metrics. Icon rasterisation. Tolerance: 1.5pt or less, colours within a few levels. |

## Method

1. One DOM query of the board root gave the expected boxes, colours and type (`board-dom-spec.txt`).
2. For every text node, SVG and dot in the board DOM, `element-compare.tsv` measures the **ink bounding box and core colour in both images in the same region**. It holds 67 elements. Ink is compared to ink, so CSS line boxes are not converted.
3. Pixel scans (`row`/`col`) gave edges of fills, separators, the capsule, the pill and the traffic lights.
4. Glyph column runs (`xruns`) were taken for the time labels and host strip.
5. Paired native-resolution crops are in `crops/` (23 pairs) and `crops-2/` (2 pairs), with `index.json` hashes. Magnified stacks (design on top, app below) are in `zoom/`.

## Findings (deltas)

**F1. Time column: the digits are not tabular. Unit letters misalign by up to 3pt.**
- The board declares `font-variant-numeric: tabular-nums`. All its labels have the same advance: "2m" and "1m" are both 21.92px wide. Every unit letter after a digit starts at x=26.
- In the app, the "1" is narrower. After a "1", the unit letter starts 3pt early.
  - "1m": board "1" at x 17–22, "m" at 26–37. App "1" at 16–21, "m" at **23–35**. That is −3pt at the "m" start and −2pt at the right edge.
  - "1d": board "d" at 26–33. App "d" at **23–30**. That is −3pt.
  - "2m": board right edge 37, app 36 (−1).
  - "4m", "6m", "9m" and "3h" match to 0px.
- Visible result: down the column, "1m"/"1d" units sit 3pt left of "4m"/"9m"/"3h". The board keeps them in one column.
- Measured with pixel column runs on 1x captures. Crops: `crops/20-time-1m-*`, `crops/21-time-1d-*`, `crops-2/24-time-column-*`, `zoom/20-time-1m-zoom8x.png`, `zoom/21-time-1d-zoom8x.png`.
- This is not a text-metrics difference. Both renderers use SF Pro, and the other digits match exactly. Only the digits whose proportional and tabular widths differ ("1", and "2" slightly) move.
- Hypothesis: the time label lacks `.monospacedDigit()`.

**F2. The app draws a 1pt hairline between the title bar and the host strip. The board has none.**
- App: row y=51 is sRGB 35,35,35 across the full 0–400 width. It sits between the title bar (30,30,30) and the host strip (26,28,30).
- Board: y 41–60 is one continuous #1B1B1E surface. No line exists between the title bar and the host strip.
- Measured with a pixel row and column scan. Crops: `crops/23-titlebar-bottom-edge-*`, `zoom/23-titlebar-bottom-edge-zoom4x.png`.
- The off-screen shot draws an inactive window, so this may be part of inactive chrome. It is not covered by the "lighter title-bar shade" exception: it is a separate line, not a shade.
- To clear it, capture an active window: `--onscreen` needs an unlocked screen.
- Hypothesis: the unified toolbar's title-bar separator.

**F3. Window controls: the native buttons do not match the board's size or position.**
- Board: 12pt circles. Centres at x 20 / 40 / 60, y 26. Pitch 20.
- App: 14pt circles (x 19–32, 42–55, 65–78; y 19–32). Centres at x 25.5 / 48.5 / 71.5, y 25.5. Pitch 23.
- Deltas: the first button is +6pt, the last is +12pt, and the diameter is +2pt.
- Measured with pixel scans. Crops: `crops/03-traffic-lights-*`, `zoom/03-traffic-lights-zoom8x.png`.
- These are the macOS 26 system window buttons. The accepted exception covers only their grey inactive colour. No documented exception covers their geometry.
- This needs a decision: accept native placement, or reposition the standard buttons. The switcher's centre is not affected: the capsule is x 122–302 in the app against 121.8–302.2 on the board.

## Observations (within tolerance or an accepted exception)

- O1. In the app, rows of text sit 0–1pt lower: header labels +1, titles and meta +0/+1. The separator below the last Working row is at y 534 against 533. All other separators are identical (82, 195, 270, 383, 458, 646, 722, 797), all from x 62 to 400.
- O2. The right-hand title-bar items are +1pt: capsule right edge 302/301, Tasks badge 273–288 against 272–287, search button 359–388 against 358–387, search glyph 368–379 against 367–378.
- O3. Host strip: the "·" in "· 3 working" is at x 142–143 against the board's 140–142 (+2). "3 working" is +1. "Air offline" ends at 131 in both, so this is not accumulated drift. It comes from the side bearing of the U+00B7 glyph. I classify it under text metrics. It is at the edge of tolerance, so the call is shown here.
- O4. The By status chevron ink is 7×3 against 5×4: the left edge −1 and the right edge +1. This is icon rasterisation. The pill matches to the pixel: x 308–381, y 52–73, fill 44,44,47.
- O5. Offline ring: the app draws an antialiased stroke of about 1.5pt at x 63–69. Chrome snaps the board's CSS `1.5px` border to 1px at x 62–68. The app is closer to the CSS.
- O6. List background: app sRGB 26,28,30, board capture 26,26,30, CSS 27,27,30. That is 2 levels or less.
- O7. The title bar is 30,30,30 against 26,26,30. This is covered by the inactive exception.
- O8. The core colour of "ago" is 135,136,144 against 138,138,147. That is 3 levels, on 11px glyphs.
- O9. The harness window is 912px tall (860 content plus the 52 title bar). The board window is 860 tall. They were compared top-aligned. Below y 798, both are empty background.

## Component × criterion matrix

P = PASS, F = FAIL, PT = PARTIAL, N/A = no board reference for it. Numbers refer to findings and observations.

| Component / state | Internal | Structure / layout | Copy | Typography | Colour | Glyphs | Spacing / shape | States | Chrome |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Window controls | P | F (F3) | N/A | N/A | P (inactive, accepted) | P (native) | F (F3) | PT (active state not shown, G2) | F (F3) |
| Title bar surface | F (F2) | F (F2) | N/A | N/A | P (O7) | N/A | P | PT (G2) | PT (F2, G2) |
| Sessions/Tasks switcher, Sessions selected | P | P (O2) | P | P | P (capsule 47,46,50 vs 46,46,50; segment 85,85,88 both; badges 255,159,11 and 237,148,20 vs 236,149,20) | N/A | P (capsule 32 tall, r16; segment 26 tall; badges 16×16) | P | PT (on-screen glass, G3) |
| Search button | P | P (O2) | N/A | N/A | P (214,215,221 both) | P (12×12 ink both) | P (30pt circle) | P | PT (G3) |
| Host strip: Pro dot, Pro, offline ring, Air offline, working count | P | P (O3) | P | P | P (dot 51,215,76; ring 255,159,11; amber 255,179,63; grey 138,138,147, all exact) | P (O5) | P (O3) | P (offline = hollow amber ring + amber label) | N/A |
| By status button | P | P | P | P | P (201,203,211 both) | P (O4) | P (exact) | N/A (menu open: no board) | N/A |
| List top border | P | P (y 82, full width) | N/A | N/A | P (44,44,47 both) | N/A | P | N/A | N/A |
| Header: Needs input 2 (expanded) | P | P (O1) | P | P | P (255,179,63; count 138,138,147) | P (chevron 7×5 at 20,103 both) | P | P | N/A |
| Header: Working 3, "by last activity" | P | P (O1) | P | P | P | P | P (hint right edge 383 both) | P | N/A |
| Header: Recent 43 | P | P (O1) | P | P | P | P | P | P | N/A |
| Any header, collapsed (board: chevron right, rows and hint hidden) | PT | PT (G1) | PT | PT | PT | PT | PT | PT (G1) | N/A |
| Row: needs input, question (2m) | P | P | P | P ("2m" is 1pt narrower; title, meta and line match to 1pt) | P (amber time and line 255,179,63; title 244,244,246; meta 168,168,176) | P (ask icon 11×11 at 63,171 both) | P (separator y 195, x 62–400) | P | N/A |
| Row: needs input, permission (6m) | P | P | P | P | P | P | P | P | N/A |
| Rows: working ×3, incl. "from a task" | P | P (O1) | P | F (F1 on "1m") | P (green time 90,227,122 both; dot plus glow 13×13 both) | P | P | P | N/A |
| Rows: recent closed ×2 | P | P | P | F (F1 on "1d") | P (grey time 138,138,147) | N/A | P | P | N/A |
| Row: offline host, dimmed (2d) | P | P | P | P | P (50% opacity: title 144,144,147 vs 144,145,147; meta 103,103,108 vs 102,103,108; separator dimmed 35,35,39 vs 35,37,39) | N/A | P | P | N/A |
| Time column (all rows) | P | P | P | **F (F1)** | P (O8) | N/A | F (F1: unit letters misaligned by 3pt) | P | N/A |
| Whole window | P | P (separators and rows align to 1pt, O9) | P | see rows | P (O6) | P | P | PT (G1) | F (F2, F3) |

## Whole-window checks

- Vertical rhythm: rows are 75pt tall and headers 37.5pt. Section starts are at 83 / 271 / 534 on the board and 83 / 271 / 534–535 in the app.
- The list starts at y 82 in both. The last separator is at 797 in both.
- No overlap, clipping or truncation in either capture. No scroll: everything fits in both.
- No shared chrome leaks: the title bar holds only the window controls, the switcher and the search button. There is no "+", no inline search field and no connection bar, as on the board.

## Coverage gaps

- **G1. Collapsed group state not verified in the app.**
  - The board defines it (`board-working-collapsed-438x942.png`): chevron points right, the group's rows and hint disappear, and the next header moves up.
  - The `--window-shot` harness has no collapse option. The screen is locked (`lfg-unlock status`), and the caller asked for off-screen capture, so no on-screen click was tried.
- **G2. Active-window chrome not verified.** The harness draws an inactive window. Without an active capture, F2 and F3's colours cannot be cleared.
- **G3. On-screen Liquid Glass not verified.**
  - The harness's own comment says `cacheDisplay` draws Liquid Glass toolbar items as blank capsules. The switcher and search button are toolbar items with the shared background hidden. They render complete here, so that failure did not occur.
  - How they look on screen is still unproven.
- **G4. Harness window, not the shipping window.** The window is a hand-built `NSWindow` (unified toolbar, hidden title) that mirrors the shipping Window scene. It is not that scene.
- **N/A (no board reference):** the search row (`--search`), the By status menu open, directory grouping, hover and pressed states, live data and DF5 behaviour (the caller said these were not needed).

## Timing (observed)

| Phase | Time |
| --- | --- |
| Preparation (scope, server check, build provenance) | 13:31–13:33 |
| App capture (harness run 1.9 s, sRGB conversion) | 13:32–13:37 |
| Design capture (render, 1x zoom capture, DOM dump, collapsed state) | 13:33–13:45 |
| Comparison (element table, scans, crops, zooms) | 13:37–13:47 |
| Report | 13:47–13:52 |

Tool failures and recoveries:
- The chrome tool truncated long JS results at about 1 KB. A loopback receiver on port 8795 took the DOM dump as a POST.
- The worktree hook rejected compound Bash commands. Plain single commands worked.
- **Incident:** the scratchpad is shared with the parent session. My first helper writes overwrote two existing scratch files, `scratchpad/m.py` and `scratchpad/recv.py`, left by the Phase 2 r3 verifier. I restored both byte-for-byte from that agent's transcript (`agent-a83bfac7cd9ae1c90.jsonl`). All my helpers now live in `scratchpad/verifier-p4r1/`. My receiver writes to `scratchpad/recv/`. No project files were touched.

## Files

- `app-board-400x860.png` (raw), `app-board-400x860-srgb.png` (converted)
- `board-zoomcapture-438x942.png`, `board-working-collapsed-438x942.png`, `reference-dA2-sessions.dc.html`, `board-dom-spec.txt`
- `element-compare.tsv` (67 elements, ink and colour, board against app)
- `pairs.json`, `crops/` (23 pairs, `index.json`, review sheets); `pairs-2.json`, `crops-2/` (2 pairs)
- `zoom/` (magnified stacks for viewing only; measurements come from the native crops)
