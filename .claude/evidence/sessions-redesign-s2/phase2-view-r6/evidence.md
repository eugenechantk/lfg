# Phase 2 session view (phone), round 6: boards 4 and 5, independent design verification

**Verdict: FAIL on both boards, for one shared delta (D1).** The strip menu now casts a shadow, but the shadow is about twice as dark as the boards'. Round 5's D2 is fixed: the ⋯ dots now match the board at 3x.

- Board 4 (`s2-queued`): **FAIL** (D1).
- Board 5 (`s2-queued-failed`): **FAIL** (D1).
- Every other component on both screens passes, or is excluded by an owner decision. Two items are not verifiable from h264 frames (see "Not verified").

## Scope, build, method

- **Scope:** boards 4 and 5 only, judged as whole screens. The change under test is the strip row's ⋯ mark and the menu card that opens from it.
- **Design (ground truth):** local render at `http://127.0.0.1:8793/`. Board files are dated 10-15 13:50.
  - Rendered fresh in a new claude-in-chrome tab: viewport 1136×1288, DPR 1, system fonts (no web fonts). Zoom region [0,0,390,844] → `design/b4-queued.png`, `design/b5-failed.png`.
  - Board 4's closed strip was rendered from the board itself: one click on the strip → `design/b4-queued-closed.png`.
  - One DOM dump per board, limited to the 390×844 artboard → `design/*.txt`. The first line of each dump records the page URL, so a dump of the wrong page cannot pass unnoticed.
  - Baseline check: both renders match round 5's within 3 levels, in antialiased text only (`tools/diffdesign.py`).
  - 3x glyphs: the board's own SVGs were cloned at 3× size into an overlay beside the artboard and captured → `design/glyphs3x-b4.png`, `design/glyphs3x-b5.png`.
- **App:** worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree. Build label: `git diff -- ios | shasum` = `ee28f034…`.
  - `LFG.app` was built at 21:20:33. The newest iOS source file is `Components.swift` at 21:20:23, so the installed build includes it.
  - Launched with the supplied `flowdeck run … --launch-env LFG_S2_VIEW_FIXTURE=queued|failed`. The strip row was opened with one tap at (200, 728) pt.
  - Simulator: iPhone 17 Pro, `C47EB72F-A352-44C9-8A80-9F13D33780AD`.
- **Capture:** `flowdeck ui simulator record --codec h264`, keeping the last frame (`tools/cap.sh`). Frames are 1206×2622, which is 402×874 pt at 3 px/pt. No AX frames (known screen/session failure), so all app geometry comes from pixels.
- **Measurement:** `tools/m.py`, `samp.py`, `bands.py`, `shadowprof.py`, `dotsglyph.py`, `stretch.py`; batch scripts `tools/probe1..6.sh`.
  - Board ±1 pt (1x raster). App ±0.33 pt. Deltas of 1.7 pt or less are within the combined limit and are not counted.
  - App positions map to the board as follows. Bottom-anchored items: +31 pt in y (strip top 713 vs 682). Right-anchored items: +11 or +12 pt in x (screen 402 vs 390).
- **Colour:** h264 frames read 2–4 levels off on flat fills. Peaks of small antialiased text overshoot by 10–15 levels, so text ink is not graded by its peak.
- **Borders:** the boards declare 0.5px borders, which Chrome draws 1 px wide.

| Frame | State |
|---|---|
| q0 | queued, strip closed |
| q1, q2 | queued, strip menu open (two frames 15 s apart; only the timer and spinner differ) |
| f0 | offline, "Not sent" strip closed |
| f1 | offline, strip menu open |
| keepalive1 | idle frame, only to keep the simulator active |

## Matrix (component × state × criteria)

Criteria columns: consistency, structure, copy, type, colour, glyphs, spacing/shape, state, chrome. "data" means the difference is fixture sample text, which is accepted.

| Board · component | Cons | Struct | Copy | Type | Colour | Glyph | Spacing | State | Chrome |
|---|---|---|---|---|---|---|---|---|---|
| 4 · header + status | PASS | PASS | PASS ("Working · 3m 52s · 1 queued · Pro"; timer is data) | PASS (title ink 13.3 vs 13; relative to button centre: title −15.3 vs −15, status +5.3 vs +5) | PASS (green dot ring 12.3 vs 13) | n/a | PASS (status width 211.7 vs 213; dot→text 3.7 vs 3; green→grey 7.7 vs 7) | PASS | PASS (glass buttons accepted) |
| 4 · transcript | PASS | PASS (pills allowed) | data (more turns above) | PASS (prose pitch 24 = 24) | PASS | PASS | PASS (prose→Edited 38.3 vs 37; Edited→Ran 34.3 vs 36, at the limit, see O1) | PASS | n/a |
| 4 · strip, closed (q0) | PASS | PASS | PASS | PASS (text ink 12 tall, +11 from strip top = 11) | PASS (#18181A vs board closed render #18181C) | PASS (⋯ ring 13.33 = 13.33, stroke 1.33 = 1.33, dot height 2.67 = 2.67; spinner 11 vs 11.8) | PASS (32 = 32; inset 12 = 12; text x 45.7 vs 45; ⋯ right inset 11.3 vs 11.4; 6 = 6 above composer) | PASS | n/a |
| 4 · strip, open (q1) | PASS | PASS | PASS | PASS | PASS beside the menu (#2E2E31 vs #313135); **FAIL D1** under the menu | PASS in shape; dimmed under D1 (peak 113 vs 132) | PASS | PASS (brightens on open as the board specifies) | n/a |
| 4 · strip menu | PASS | PASS (Send now + subtitle / Edit / Remove) | PASS | PASS (title ink 13 = 13; subtitle 12 = 12) | PASS card (#29292C vs #2B2B2C), divider (#464649 vs #48484A), red (#FF4542 vs #FF453A); **FAIL D1** shadow | PASS (arrow-up, pencil, trash at 3x) | PASS (250 × 141.7 vs 250 × 141; rows 56.7/42.7/42.3 vs 56/43/42; right inset 12 = 12; 8 = 8 above strip; text inset 17.3 vs 17; icon inset 18.7 vs 19; text tops +13.7/+33/+71.3/+114.7 vs +13/+32/+70/+114) | PASS | n/a |
| 4 · composer | PASS | PASS (see C2) | PASS ("Add to this turn…") | PASS (placeholder ink 13 = 13) | PASS | PASS (paperclip 17 vs 16) | PASS (95 vs 96; 28 = 28 from bottom; placeholder +16.3 vs +16; chip x 58 vs 59, centre +68 = +68; Stop 34 = 34, right inset 22 vs 23) | PASS (Stop) | PASS |
| 5 · header + status | PASS | PASS | PASS ("Air offline · 2m · inbox") | PASS | PASS (amber dot without ring, 7 = 7) | n/a | PASS (status width 142.3 vs 142, centred) | PASS (offline) | PASS |
| 5 · transcript | PASS | PASS (no pills offline) | data | PASS (prose pitch 24 = 24; bubble 39.3 vs 40) | PASS | n/a | PASS (last prose line→strip 37 = 37; bubble right inset 16 = 16; bubble→prose 17.3 vs 19, at the limit, see O2) | PASS | n/a |
| 5 · strip, closed (f0) | PASS | PASS | data (app fits the whole message; the board truncates it) | PASS | PASS ("Not sent" #FF6665 vs #FF6961; fill #18181A, matching the 0.22 fill in the board source) | PASS (! icon 12.7 vs 12.5; ⋯ matches at 3x) | PASS (text x 47.3 vs 47; "Not sent"→⋯ 10 vs 9.4) | PASS | n/a |
| 5 · strip, open (f1) | PASS | PASS | PASS | PASS | PASS beside the menu (#2E2E31 vs #313135); **FAIL D1** under the menu | PASS in shape | PASS | PASS | n/a |
| 5 · strip menu | PASS | PASS (Retry / Edit / Delete) | PASS | PASS | PASS (card #29292C vs #2B2B2C; tint over the bubble #282A2E vs #2D3035, see "Not verified"); **FAIL D1** shadow | PASS (retry, pencil, trash at 3x) | PASS (230 × 127.8 vs 230 × 128; rows 42.7/42.7/42.3 vs 43/43/42; right inset 12 = 12; 8 = 8 above strip; text inset 17.3 vs 17; text tops +15/+57.3/+100 vs +15/+57/+100; bubble peeks 6 pt above the card vs 8) | PASS | n/a |
| 5 · composer | PASS | PASS (see C2) | PASS ("Message · sends when Air is back"; "Medium" accepted) | PASS (placeholder ink 16 = 16) | PASS (disabled send #39393C vs #3A3A3B; arrow #969698 vs #8E8E93) | PASS (send arrow 11.3 vs 11.3) | PASS (placeholder +16.3 vs +17; send 34 = 34) | PASS (disabled send) | PASS |
| Whole screen, both | PASS. Opening the menu dims nothing else: bubble, header buttons and composer read the same in q0 and q1. The menu shadow does not reach the composer (board: 2 levels; app: 0). The menu sits above the strip in z-order on both. | | | | | | | | |

## Finding

**D1. Boards 4 and 5: the strip menu's shadow is about twice as dark as the board's.** (Round 5: the shadow was missing. Now it exists, but it is too deep.)

The board declares `box-shadow: 0 12px 40px rgba(0,0,0,0.6)`. Measured, board X vs app Y:

- **Strip under the menu centre** (board x 250, app x 261), in the open strip:
  - 1 pt below the strip top: board #202022 vs app #0A0A0A. The board darkens 17 levels; the app darkens 36.
  - 7 pt below: board #232326 vs app #111113.
  - 25 pt below: board #2C2C30 vs app #222225.
  - At the bottom (30 pt): board #2E2E31 vs app #262629.
  - Beside the menu (x 30), with no shadow: board #313135 vs app #2E2E31. That 3-level gap is the h264 limit, so the extra darkening is real.
  - Board 5 reads the same: board #202022 vs app #0A0A0A at the strip top.
- **Bubble beside board 5's card** (4 pt above the bubble bottom), blue channel compared with the unshadowed bubble:
  - 3 pt from the card edge: board −17% (184 of 221) vs app −46% (120 of 222).
  - 8 pt: board −13% vs app −28%.
  - 18 pt: board −6% vs app −13%.
- **Footprint:** about the same on both. Darkening starts about 28 pt left of the card on the strip, and reaches about 38 pt out on the bubble. Only the depth differs.
- **Knock-on:** the ⋯ glyph sits under the shadow. In the open strip it peaks at luminance 132 on the board vs 113 in the app. Closed, it reads 143 vs 147.
- **Evidence:**
  - Pairs: `crops/pairs/b4-strip-open-*`, `b4-menu-shadow-zone-*`, `b5-strip-open-*`, `b5-menu-shadow-zone-*`.
  - Enlarged: `crops/zoom-menu-strip-b4-vs-q1.png`, `crops/zoom-menu-strip-b5-vs-f1.png`.
  - Numbers: `tools/shadowprof.py` output (q1 and q2 give identical numbers).
- **Cause (hypothesis, not proven):** the app's shadow opacity is too high or its blur too small for CSS `40px` (CSS blur = 2σ), or two shadows are stacked.

## Round-5 findings re-checked

| Round 5 | Now |
|---|---|
| D1 boards 4 and 5: no shadow on the strip | Changed: a shadow is present but about 2× too dark (D1 above) |
| D2 boards 4 and 5: ⋯ dots about half size (1.33 pt) | **Fixed.** At 3x, ring 13.33 = 13.33, ring stroke 1.33 = 1.33, dot height 2.67 = 2.67, and the dots merge into one 8.0 pt run at half intensity on both (`crops/glyphs3x-*.png`, `crops/pairs/*ellipsis*`) |

## Observations within the limit (not counted)

- **O1.** Board 4: the pitch from the Edited step to the Ran step is 34.3 vs 36 (−1.7). Same as round 5's O3.
- **O2.** Board 5: the gap from the bubble bottom to the first prose ink is 17.3 vs 19 (−1.7). The prose block itself is exactly placed (last line→strip 37 = 37), so the bubble sits 1.7 pt lower. Same as round 5's O2.

## Board conflicts (not counted; another board specifies the component)

- **C1. Board 4 / app: the single-call row.** Board 4 draws "Ran bun test src/sessions.test.ts" in sans, with no duration. The app draws the command in mono, with "1.8s", following board 3 (`s2-tools-single`, which has the mono command and "1.8s").
- **C2. Boards 4 and 5 / app: the model chip chevron.** These boards draw the chip without a chevron. Board 1 (`s2-view`) draws it with one (`M6 9l6 6 6-6`). The app shows the chevron.
- Round 5 recorded both under an owner rule. This round's handoff does not list them, so the caller should confirm that rule still stands.

## Exclusions applied (owner decisions)

- The glass back and tools buttons.
- Fixture sample text: titles, timers, the extra transcript turns on board 4, and the full untruncated message on board 5.
- "Medium" for "Med".
- The pills: Files and Terminal on board 4; none offline on board 5.
- Icon rasterisation, and text width (SF Pro on iOS is about 6% narrower).
- Colour judged only within video tolerance.

## Not verified

- **Menu card translucency.** The board's 0.97-alpha card lets the transcript show through by about +10 levels on text strokes (`crops/stretch-menu-*.png`).
  - The app shows a faint bubble tint (#282A2E vs the board's #2D3035), and faint text along the card's top edge (+5).
  - Lower down, no text shows through at all.
  - h264 can remove a +6-level, thin-stroke detail, so this cannot be judged without a lossless capture. It is not counted as a delta.
- **Exact colours:** h264 frames only. No lossless screenshot is available (known tooling failure).
- **Menu actions** (Send now, Retry, Edit, Remove, Delete) were not tapped. Dismissal by tapping outside was not tested.
- **The spinner** animates, so its arc angle is not comparable frame to frame.
- **Board 5's closed strip** was not rendered from the board. Its expected fill comes from the board source (`rowBg` 0.22, the same as board 4's rendered closed state).

## Tool failures and recoveries

- **Browser tab interference.** Another agent navigated my first tab (1045567067) to `s2-signin.dc.html` between my zoom capture and my DOM dump. The dump came from the wrong board. The tab group was then removed.
  - Recovery: a new group and tab (1045567074). The dumps were redone with a URL guard written into the dump.
  - The board 4 PNG from the first tab is pixel-identical to the one from the second tab.
- **Worktree guard.** The guard rejected compound shell commands, so all probes run from small script files (`tools/probe*.sh`).

## Timing (observed)

| Phase | Time |
|---|---|
| Preparation (scope, round-5 layout, tool copy, build provenance) | 21:21:45–21:22:29 |
| App capture (2 launches, 2 taps, 5 frames) | 21:22:29–21:23:58 (keepalive 21:43:52) |
| Design capture (renders, guarded DOM dumps, 3x glyphs; tab interference cost about 3 min) | 21:24–21:35:40 (closed-strip render 21:43:41) |
| Comparison (geometry, shadow profiles, glyphs, stretch crops, paired crops) | 21:35:40–21:45 |
| Report | 21:45–21:50 |

## Paths

- Sources: `app/*.png`, `design/*.png`, `design/*.txt`.
- Paired native crops, `index.json` (source and crop SHA-256 hashes) and review sheets: `crops/pairs/`.
- Glyph sheets and enlarged pairs: `crops/glyphs3x-*.png`, `crops/zoom-*.png`, `crops/stretch-*.png`.
- Manifest: `pairs.json`. Tools: `tools/`.
