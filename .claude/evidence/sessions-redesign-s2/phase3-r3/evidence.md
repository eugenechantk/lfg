# Phase 3, round 3: independent visual verification (sheets, terminal, sign-in browser)

Verdict: **A PASS · B PASS · C PASS · D FAIL · E FAIL · overall FAIL**

## Scope

- Live verification on the iPhone 17 Pro simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD`. The installed build was launched with `--no-build`. The build is LFG.app Debug-iphonesimulator, binary mtime 2026-10-16 09:25:10 HKT. FlowDeck reported "Running build from 6 minutes ago" at 09:31.
- App routes:
  - A: `LFG_S2_VIEW_FIXTURE=menu`.
  - B: `LFG_S2_VIEW_FIXTURE=subagents`.
  - C: `LFG_S2_VIEW_FIXTURE=files`, then one tap at (288,312) pt on "Links 2".
  - E: `LFG_S2_VIEW_FIXTURE=signin`, then a tap on "Sign in on iPhone".
  - D: launch with no fixture, open `lfg://session/1936147b-…`, then tap "Terminal". I then tapped "Show wide terminal", swiped the key row from 346 to 30 pt in the gap between two keys, and tapped "Fit terminal to screen".
  - I did not type, press a terminal key, or tap any control on the do-not-tap list.
- Reference kind: HTML. The boards came from `http://127.0.0.1:8793/`, served from `scratchpad/dcrender/project`. I rendered them in my own Chrome tab (1045567268) at DPR 1 with CSS zoom 3. Each render is four 585×1266 tiles stitched to 1170×2532. DOM dumps were taken at zoom 1 and posted to a loopback receiver on port 8797, which is now stopped.

| Board | source sha256 | render (sha256 prefix) | state / edits typed into my tab's DOM |
|---|---|---|---|
| A `s2-menu.dc.html` | a08fc9fd…dcce5a8 | `board/board-menu-appvalues-3x.png` ad9299ec152e | subtitle "Eugenes-MacBook-Pro · ~/dev/personal/lfg · started 2h ago", Host value "Eugenes-MacBook-Pro", footer "tmux lfg-fork-3 · id s2fx-fork · tap to copy" |
| B `s2-subagents.dc.html` | 658b43c6…6e47e34 | `board/board-subagents-3x.png` a507998eabe2 (identical to round 2's render) | none |
| C `s2-files.dc.html` | d8b1eae1…a5fafc | `board/board-files-3x.png` f6bc5628335c (identical to round 2), `board/board-links-3x.png` a67e1577ed2e | Links state from the board's own pill |
| D `s2-terminal.dc.html` | 6eba7d38…a3bd62 | `board/board-terminal-kb-3x.png` e58bf81d4ab8 (default, keyboard open), `board/board-terminal-kbclosed-fit-3x.png` 38d85ce7ffb5, `board/term-wide-kbc-t01.png` 42ca0091aad2 (Wide, lower-left tile) | toggled with the board's own Wide/Fit and keyboard buttons |
| E `s2-signin.dc.html` | a5bde99b…c6b147 | `board/board-signin-appvalues-3x.png` 56f2b8b6e59c | host "example.com", subtitle "For Search Console audit · goes to Mac" |

- `support.js` sha256 3f160299…f0dc6.
- App frames are the last frame of 1 s h264 recordings at 1206×2622 (3x). Hashes (prefix): menu 5355af4bde0c, subagents 734885137503, files 8c8dcd28c3a4, links 8c8da848749b, signin 24d701207688, terminal-fit 4e073dd4bc91, terminal-wide 706aab916adc, terminal-keys-scrolled 0c7a655dead4. There are also 172 frames from a 3 s terminal recording (`app/cursorframes/`) and two AX dumps (`app/terminal-*-ax.json`).
- Coordinates:
  - Sheets (A/B/C) use laid-out sheet pt. Board values are px/3 minus the sheet top (112 for A, 200 for B/C).
  - App sheets are 386.0 pt visible, so L = 8.0 pt and s = 0.9602. App values are (px/3 − edge)/s. The sheet top is the grabber top − 14 px. In screen pt it is A 130.67 and B/C 215.0. In the C frame a dimmed transcript card sits above the sheet, so I located its top from the grabber, not the surface colour.
  - Full-screen D and the full-height sheet E are measured relative to the page or sheet top (board 54, app 62). Bottom-anchored items are measured from the screen bottom. Right-anchored items are measured by their right inset. Sheet widths are board 390 and app 402.
- Accepted exceptions applied, as given by the caller: system sheet chrome and the 0.9602 inset, device size and inset, Liquid Glass buttons, sample data, the dimmed Browser tile, effort segment sizing and "Medium", SF Pro vs Chrome text widths, SF Mono vs Menlo glyphs, icon rasterisation, 3x separator pitch, live terminal output, the key row at the screen bottom with a hardware keyboard, the mock web page, and h264 colour levels.
- Tolerance: ≤1.5 pt is an observation. For text colours I used the 90th/98th percentile of glyph pixels (max channel), because h264 overshoot inflates single-pixel peaks by 8–15 levels. A white reference in the same frame (the title) matched the board, at 247.7 vs 247.

## Matrix (component × state × criterion)

Columns: 1 internal consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 nav chrome

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| A header (title, pencil, close, 2-line subtitle) | PASS | PASS | PASS (data) | PASS | PASS | PASS | PASS | N/A | N/A |
| A tile grid (6 tiles, badges, dimmed Browser) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (dimmed accepted) | N/A |
| A card 1 (Model, Effort, Host, Fork, Mark) | PASS | PASS | PASS (N2) | PASS | PASS | PASS (O2) | PASS | PASS (High selected) | N/A |
| A card 2 + footer | PASS | PASS | PASS | PASS (O3) | PASS | PASS | PASS | N/A | N/A |
| A/B/C sheet chrome | PASS | accepted | – | – | – | – | – | – | accepted |
| B header (title, tally, close) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| B rows (running, done ×2, failed) | PASS | PASS (O4) | PASS (live timer) | PASS | PASS | PASS (O2) | PASS (O5) | PASS (3 kinds) | N/A |
| C header + Files/Links pill | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (Files and Links selected) | N/A |
| C sections + 5 file rows | PASS | PASS | PASS (order = data) | PASS | PASS | PASS (O2) | PASS (O5) | N/A | N/A |
| C Links rows (letter tile, title, domain, arrow) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| D header (close, title/subtitle, Fit/Wide) | PASS | PASS | PASS (data) | PASS | PASS | PASS | PASS | PASS (Fit and Wide selection) | PASS |
| D terminal text, Fit | PASS | PASS | N/A (live) | **FAIL D1** | PASS | accepted | **FAIL D1** (row pitch) | **FAIL D3** (cursor) | N/A |
| D terminal text, Wide | PASS | **FAIL D2** | N/A (live) | **FAIL D2** | PASS | accepted | **FAIL D2** | **FAIL D2** | N/A |
| D key row (in isolation) | PASS | **FAIL D4** | **FAIL D4** | PASS (mono accepted) | PASS | accepted (arrows) | PASS (O6) | PARTIAL (sticky ctrl not exercisable) | accepted (N3) |
| E top chrome (close, URL pill, reload) | PASS | PASS | PASS (data) | PASS | PASS | PASS | PASS | N/A | PASS |
| E web area bounds | PASS | PASS | N/A (mock) | N/A | N/A | N/A | PASS | N/A | N/A |
| E bottom bar (back, forward, I'm signed in) | PASS | PASS | PASS | PASS | **FAIL E1** | PASS | PASS | **FAIL E1** / PARTIAL (back-enabled state) | PASS |
| E review / sent sheets | unverified | unverified | unverified | unverified | unverified | unverified | unverified | unverified (reaching them needs a forbidden tap) | – |

## Findings

**D1. Terminal text metrics (Fit): the app font is about 1 pt larger and its rows are 1.4 pt tighter.**
- Cell width: board 7.225 pt (DOM, 12 px font, "eugene@Pro" = 72.25 pt) / app 7.875 pt. For the app I measured the tmux status bar, which spans exactly 12.0–390.0 pt = 48 cells. The AX TextArea is 378 pt wide. The glyph left edges of "sh-3.2$" give the same pitch.
- SF Mono and Menlo both advance about 0.60 em, so this is a size difference of about 13.1 pt vs 12 pt, not a font-family difference. The app fits 48 columns in 378 pt, while the board fits 50 in 366 pt. Over a 50-character line the text is 32 pt wider.
- Digit height agrees: board 9.0 pt / app 9.3–9.7 pt.
- Row pitch: board 17.4 pt (line-height 1.45 × 12) / app 16.0 pt. The status bar is 16.0 tall, the cursor is 16.0 tall, and the status row starts at 796.0 = 124 + 42 × 16.0. 43 rows fit in the 690 pt view, where the board's pitch would give 39. Each row is −1.4 pt, and the line-height ratio is 1.22 vs 1.45.
- Measured by pixel scans and AX (`scripts/m_terminal.py`, `m_terminal2.py`, `crops/D1-fit-glyphs-sbs.png`, `pairs/D-text-glyphs-*`).
- Possible cause (hypothesis): the terminal uses its default cell metrics instead of 12 pt with 1.45 line spacing.

**D2. Wide mode: the board shrinks the font, while the app keeps the Fit font and widens the canvas off-screen.**
- Board Wide: font 10.5 pt, line-height 15.225 pt, cell 6.32 pt (DOM "eugene@Pro" = 63.22 pt). The content width stays 366 pt, so more columns fit on screen.
- App Wide: the cell is still 7.875 pt and the rows 16.0 pt. The glyphs look the same as in Fit (`crops/D2-wide-glyphs-sbs.png`). The AX TextArea grows from 378 to 965 pt wide (x 12), so everything past about 390 pt is off-screen.
- The tmux status line shows the clipping. In Fit it reads "[lfg-term-0:zsh* "exec /bin/sh" 09:34 16-Oct-26" across 12–390 pt. In Wide only "[lfg-term-0:zsh*" is visible, and the bar runs on past the right edge (`crops/D2-status-fit-vs-wide.png`).
- Measured by AX frames (`app/terminal-fit-ax.json`, `app/terminal-wide-scrolled-ax.json`) and pixel scans.

**D3. The cursor is about half as bright as the board's and blinks.**
- Board: a solid block of #D1D1D6 (209–214), 7.0 × 13.7 pt.
- App: a block of 8.0 × 16.0 pt (one full cell) that fades between 10 and 126 levels. I measured it over 172 frames in 3 s: brightest frame f108 at 126.6, dimmest f064 at 10.7.
- At its brightest the app cursor is −83 levels from the board. The prompt text right next to it matches the board (p98 216 vs 214), so this is not a capture artefact.
- Evidence: `crops/D3-cursor-board-appbright-appdim.png`, `scripts/m_cursor.py`.
- A blink is behaviour the static board cannot show. The peak colour and the cell-height size are still deltas.

**D4. The key row has an extra key.**
- Board keys, in order: esc, tab, ctrl, ⌥, ↑, ↓, ←, →, |, /, ~, ⌘V, then the keyboard toggle. That is 12 keys plus the toggle.
- App keys, in order: esc, tab, ctrl, ⌥, ↑, ↓, ←, →, |, /, ~, **-**, ⌘V, then the keyboard toggle. The "-" key is a Button labelled "-", 40×36 pt, sitting between "~" and "⌘V".
- Evidence: AX dumps, `crops/D4-app-keys-end.png`, `pairs/D-keyrow-end-*`.
- Everything else in the key row matches:
  - Keys are 36 pt tall, with a 6 pt gap. The first key is at x 8.
  - Widths: esc 43.3/44, tab 43.3/44, ctrl 51.7/53 (mono widths, accepted). Arrow keys are 40 in both.
  - Fill 58/56, row 28/26. The esc label ink is 23.3×8.3 / 23.7×8.0.

**E1. The disabled back/forward buttons are darker than the board's disabled style.**
- Fill (max channel at the button centre): board #2C2C2E = 47 / app 37. That is −10 levels, against a steady −2 video offset everywhere else in this frame (bar 30/28, primary button 224/222).
- Forward chevron (disabled in both): board #636366 at peak 102 / app 74.
- Back chevron: the board shows the enabled state at 214. The app shows it disabled at 76, because the freshly loaded page has no history. That part is a state difference, not counted. The enabled-back appearance could not be produced without navigating the web view (coverage gap).
- Geometry matches: buttons are 44 pt at x 10–54 and 62–106, from 78 to 34 pt above the screen bottom in both. Chevron boxes are 7.3×12.7 / 6.7×12.0.
- Evidence: `crops/E1-nav-buttons-sbs.png`, `scripts/m_signin.py`, `m_signin2.py`.
- Possible cause (hypothesis): the whole button is drawn at reduced opacity when disabled.

## Matches verified (main measurements, board / app, sheet or page pt)

- **A**:
  - Rows and cards:
    - Card 1: top 274.0/273.9, separators 316.3/315.9, 364.7/364.5, 407.3/407.2, 450.0/449.9, bottom 492.7/492.3.
    - Card 2: top 506.7/506.2, separator 549.0/548.2, bottom 591.7/590.5.
    - Effort track: y 324.7–356.7 / 324.6–356.5, right inset 16/16.
  - Tile grid:
    - Top 96 in both. Round 2's D1 (+17 pt) is fixed: the grid no longer flows below the 2-line subtitle.
    - Tile labels 150.7/150.3. Icons sit at the same offsets within each tile (≤0.3). Badges have a right inset of 10.0/10.05.
    - "Browser preview" and "iPhone preview" wrap to 2 lines in both.
  - Header:
    - Title ink top 25.3/26.0.
    - Subtitle lines 56.0–69.0 and 72.7–85.7 / 55.5–68.4 and 72.6–85.4, with the same wrap point.
    - Pencil: 30 pt circle, 10×10 glyph. Its centre sits 23.9 pt after the title ink in both.
    - Close: 36 pt, right inset 16.0/15.97.
  - Row labels: x 33.3 in both, y within ≤0.7. Fork and Mark labels at x 61.3/61.5. "Opus 5.5" right inset 54.0/53.8, with the badge-to-text gap 11.0/10.4.
  - Footer: y 608.3/607.2, centred in both.
  - Colours: sheet 28/26, tile and card 44/42, close 58/56, grey text p90 166/164, blue 65,156,255 / 65,151,255, red 255,69,59 / 255,68,56, C badge 181,86,47 / 180,84,45, effort selected 99/97.
- **B**:
  - Close button 338–374 / 349.9–386.0 (right inset 16), y 20–56 in both.
  - Row 0: icon 23.7–38.7 at y 102.0 in both. Title 103.3/103.5, result 127.0/127.4, meta 149.0/148.9.
  - Separators start at x 54.0/53.8. Thickness is now 0.33–0.69 pt (round 2 measured 1.0 pt): round 2's N2 is resolved for sheet rows.
  - Colours (p98): green 209/210, result grey 214/214, meta 166/166, red 255,69,59 / 255,65,62.
- **C**:
  - Pill: track 16–374 / 16–386, y 84–118 in both. Selected segment 18 to 116. Selected fill 99/97, track 44/42.
  - Separators 219.7/219.4, 278.3/278.4, 366.3/366.6, 454.3/454.4, 513.0/513.4.
  - Section labels 145.0/144.4, 291.0/290.6, 379.7/379.4. Icons at x 22–42 in both. Text at x 56.3/56.2.
  - Links: letter tiles 20–50 × 147.3–177.3 / 20.1–50.0 × 147.5–177.7. Text at x 62.7/62.5. Arrow 11.7 pt, right inset 17.7/17.7. Separators 192.3/192.7 and 253.0/253.4.
  - The app's Links tab now matches the board's Links state, which resolves round 2's N1.
- **D**:
  - Header:
    - Close: x 12–56, rel y 4–48, 9×9 glyph in both.
    - Title ink rel 11.7–24.3 in both, centred at 170.8 / 177.0, which is the centre between the close and Fit/Wide controls on each width.
    - Fit/Wide track: 92×32 at rel 10–42, right inset 12/12. White segment 44×28. The "Wide" label sits at the same offset in both.
  - Page background 11/10. Text left inset 12 (AX) with first ink at 13.3 / board 12.7.
  - Text colour p90/p98: board 214/214, app 211/216.
  - The terminal bottom sits 10 pt above the key row in both.
- **E**:
  - Top chrome:
    - Sheet top 54/62 (accepted device offset).
    - Close button rel 13–53, x 10–50, glyph 8.7 pt. URL pill rel 13–53, fill 44/42.
    - Host text rel 21.3–34.3 / 21.0–34.0, centred at 195.3 / 201.7. Lock icon 7.7×9 with a 7.3 pt gap to the text in both. Subtitle rel 37.0–47.3 / 36.3–46.7, orange p90 255,179,63 / 254,181,83 (h264 chroma).
    - Reload glyph 12.3/12.7 pt, right inset 23.7/23.7.
  - Web area: rel 64 to 92 pt above the bottom in both.
  - "I'm signed in": x 114 to a right inset of 10, height 50, top 81 pt above the bottom in both. Label centred. Fill 9,110,224 / 6,108,222.

## Observations within tolerance (not deltas)

- O1. A title ink width is 222.7 / 205.2 (SF Pro Display vs Chrome, accepted). The pencil keeps the same offset from the title end.
- O2. Chevrons are slightly smaller in the app:
  - A: 5.0×7.7 / 4.2×6.9, right inset 34.7/35.4.
  - B: 5.3×8.7 / 4.5×7.6, inset 19.0/19.8.
  - C: 5.0×8.0 / 4.2×6.9, inset 18.7/19.4.
  - Centres match. Colours: A 74/77, C 102/103.
- O3. The A footer mono text is 317.0 / 325.3 pt wide (SF Mono vs Menlo, accepted) and centred in both.
- O4. B row pitch: board 3x render 87.33, board DOM 88, app 87.9. Row 3 lands +1.8 against the 3x render (the accepted pitch).
- O5. Effort track width 200 / 212.8 (accepted segment sizing).
- O6. The terminal key row top border is 1 device px (0.33 pt) on the board and 3 px (1.0 pt) in the app, both #2C2C2E. The board CSS asks for 0.5 pt.
- O7. Sheet top in screen pt: B/C 200 / 215, A 112 / 130.7. These are system detents with the inset scale, unchanged from round 2 and covered by the sheet-chrome exception.

## Notes (not counted)

- N1. The B running meta reads "1m 12s" on the board and "1m 17s" in the app. That is a live timer. The C image order is swapped in the app, which is fixture data.
- N2. A Host value: the board's copy pattern is "Pro · move to Air". In round 2 the app showed "Eugenes-MacBook-Pro · move to Mac". This round it shows only "Eugenes-MacBook-Pro" plus a chevron. The caller classed the Host value as sample data, but the "move to …" hint has disappeared between rounds. The owner should confirm the suffix is driven by data (for example, no other host in the fixture) and not dropped.
- N3. Key row position. The board's own keyboard-hidden state puts the key row 34 pt above the screen bottom (rows 760–810 on 844). The app's row runs from 824 pt to the screen bottom at 874, so it is flush with the bottom and sits under the home-indicator area. The caller lists this as an exception for a hardware keyboard. I note that the board does define a keyboard-hidden position.

## Coverage gaps

- E review sheet ("Send this sign-in…", domain switches) and the sent state: reaching them needs "I'm signed in", which is on the do-not-tap list. Not verified.
- E back button in its enabled state: needs web-view history. Not verified.
- D sticky-ctrl (blue) key state: needs a key press. Not verified.
- D software-keyboard layout (the board's default state): the simulator uses a hardware keyboard. Only the key row was compared, in isolation.
- No rows, tiles or menu items were tapped beyond the listed taps.

## Evidence

- App frames and recordings: `app/` (including `cursorframes/` and the AX JSON files). Board renders, tiles and DOM dumps: `board/`.
- Paired crops: `pairs/` (helper `index.json`, `review-01..03.png`). Side-by-sides and finding crops: `crops/` (`sbs-*.png`, `D1-*`, `D2-*`, `D3-*`, `D4-*`, `E1-*`, plus the raw measurement logs `m_*.txt`).
- Scripts: `scripts/` (`lib.py`, `sheet.py`, `geom.py`, `m_menu*.py`, `m_sheets*.py`, `m_terminal*.py`, `m_cursor.py`, `m_textcolour.py`, `m_signin*.py`, `extra_crops.py`, `stitch.py`, `receiver.py`). The pair manifest is `pairs.json`.

## Timing (observed, HKT)

| Phase | Time |
|---|---|
| Preparation (prior round, board sources, server check) | 09:27–09:30 |
| App capture (A, B, C, Links, E, D Fit/Wide/keys, 3 s cursor clip, AX) | 09:30–09:38, AX re-dump 09:43 |
| Board render and DOM (D ×3 states, A, B, C, Links, E) | 09:38–10:01 |
| Comparison (scripts, crops) | 09:40–10:07, interleaved with rendering |
| Report | 10:07–10:12 |

Tool failures and recoveries (once each):
- `ffmpeg -sseof` wrote no frame from a 2-frame clip. I decoded all frames with `-update 1` instead.
- The worktree hook rejected shell variables and heredocs. I moved the logic into script files.
- The FlowDeck label "Wide" was not found. I used the AX label "Show wide terminal".
- The C sheet-top search first hit the dimmed transcript card. I switched to the grabber offset.
- A few measurement boxes (chevrons, badge digit) were mis-placed at first and re-run. The logs hold the final values.
