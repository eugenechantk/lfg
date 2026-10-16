# Phase 2 session view (phone), round 5: independent design verification

**Verdict: FAIL (two minor deltas, both on the strip menu boards).** Every round-4 finding (F1 transcript→strip gap, F2 sign-in panel, F3 paperclip and pencil glyphs) is fixed. What remains:

- **D1.** Boards 4 and 5: the strip menu casts no visible shadow on the strip below it. The boards darken the strip under the menu.
- **D2.** Boards 4 and 5: the dots inside the strip's ⋯ glyph are about half the board's size.

Per board: 1 PASS, 2 PASS, 3 PASS, 4 FAIL (D1, D2), 5 FAIL (D1, D2), 6 PASS in all three kinds, 7 PASS.

## Scope, build, method

- **Design.** Local render at `http://127.0.0.1:8793/`. Board files are dated 10-15 13:50. The kind copies are dated 17:21 and differ from `s2-question.dc.html` only in `"default"` (checked with `diff`).
  - Rendered fresh in a new Chrome tab (claude-in-chrome): viewport 700×857, DPR 1, fonts loaded. Zoom region [0,0,390,844] → `design/*.png`.
  - One DOM dump per board, limited to the 390×844 artboard → `design/*.txt` (rects, computed type, colours, radii, padding, SVG attributes). The dumps were posted to a temporary receiver on 127.0.0.1:8798, which is now stopped.
  - All nine PNGs are byte-identical to the round-4 renders. Board, CSS and renderer are unchanged.
  - The coordinator reported that the board server restarted around 20:46. Every load in this round completed: the PNGs are identical, and the DOM dumps have the same element counts as round 4.
  - **Glyphs at 3x:** for boards 1, 4 and 5, each artboard SVG was cloned at 3× size into an overlay and captured → `design/glyphs3x-b*.png`. These are compared against the app's native 3x pixels. This tests shape, not 1x rasterisation.
- **App.** Worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree (`git diff -- ios` sha1 `92ae3b85…`).
  - `LFG.app` was built at 20:29:08. The newest iOS source change is 20:28:55 (MessageComposer, Components, SessionDetailView).
  - Installed and launched with the supplied `flowdeck run … --launch-env LFG_S2_VIEW_FIXTURE=<mode>` commands. The first run built nothing new.
  - Simulator: iPhone 17 Pro, `C47EB72F-A352-44C9-8A80-9F13D33780AD`.
- **Capture.** `flowdeck ui simulator record --codec h264`, keeping the last frame (`tools/cap.sh`).
  - Frames are 1206×2622, which is 402×874 pt at 3 px/pt.
  - No AX frames were available (known screen/session failure). All app geometry is measured from pixels.
  - Source SHA-256 hashes are in `crops/pairs/index.json`.
- **Measurement.** Tools are copied from round 4 and repointed: `tools/m.py`, `rowprof.py`, `bands.py`, `samp.py`, `zoompair.py`. `tools/glyphsheet.py` is new.
  - Distances run glyph edge to glyph edge, or box edge to box edge.
  - Board ±1 pt (1x raster; ink rows over-read by up to 1). App ±0.33 pt.
  - Deltas of 1.7 pt or less are within the combined limit and are not counted.
- **Colour.** The h264 frames read 2–4 levels off on flat fills. No colour is graded on a difference under 10 levels.
- **Borders.** The boards declare 0.5px borders, which Chrome draws 1 px wide. Board boxes therefore measure 1 pt over the intended size (pill 37 intended, 38 drawn; composer 96 border-box).
- **Paired crops.** `crops/pairs/<id>-design.png` and `-app.png` are native pixels. Browse them in `crops/pairs/review-01..05.png`. Enlarged and glyph pairs are in `crops/zoom-*.png`.

| Frame | State |
|---|---|
| w0 | working, steps collapsed |
| w1 | "Read 6 files, ran 3 commands" expanded |
| w2 | `Read ios/LFG/SessionStore.swift` card open (bottom-anchored) |
| w3 | w2 swiped down: header, open row, card and rows visible; prose reaches the pills |
| w4 | w3 with the pills scrolled to Terminal |
| q0, q1, q2 | queued; "Ran bun test" card open; step collapsed with the strip menu open |
| f0, f1 | offline; strip menu open |
| k-question, k-permission, k-plan, s0 | the three panel kinds, and sign-in |
| keepalive1 | idle sign-in screen, used only to keep the simulator active |

## Matrix (component × state × criteria)

The nine columns are the criteria: consistency, structure, copy, type, colour, glyphs, spacing/shape, state, chrome. "data" means the difference is fixture sample text, which is accepted.

| Board · component | Cons | Struct | Copy | Type | Colour | Glyph | Spacing | State | Chrome |
|---|---|---|---|---|---|---|---|---|---|
| 1 · top bar + status | PASS | PASS | PASS | PASS (title 13.3 vs 14; status 13 vs 14) | PASS (#2ED359 ≈ #30D158; dot ring 12.3 vs 13) | PASS | PASS (relative to button centre: title −15.3 vs −15, status +5.3 vs +5; status width 173 = 173) | PASS | PASS (glass buttons accepted) |
| 1 · bubble | PASS | PASS | data (2 lines vs 3) | PASS (pitch 22 = 22) | PASS (#066CDE ≈ #0A6EE0) | n/a | PASS (318 = 318 wide; right inset 16 = 16; text inset 14.7 vs 15; top 12.7 vs 13; r20 matches) | n/a | n/a |
| 1 · prose + steps | PASS | PASS | data | PASS (prose pitch 24; label 15) | PASS | PASS (search, pencil, chevron match at 3x) | PASS (icon x 18.3 vs 18; label 42.3 vs 42; chevron inset 19.7 vs 20; bubble→prose −1.3; prose→step +1.3; step→prose −0.3) | PASS | n/a |
| 1 · pills | PASS | PASS (Subagents, Files; Terminal on scroll) | PASS | PASS | PASS (#1B1B1E on #1C1C1E; ring arcs at the same angles) | PASS (ring 19.3 vs 20; Files doc matches) | PASS (x 16; 36 vs 37 intended; gap 8 = 8; 10 = 10 above composer; last step ink→pill 17.3 vs 18) | PASS | n/a |
| 1 · composer | PASS | PASS | PASS | PASS (placeholder 13.3 vs 13) | PASS | PASS (paperclip now 17×18.3 vs 18×18 and the board's three-arc shape at 3x; chip chevron; Stop 11 = 11) | PASS (95 vs 96; 28 = 28 from bottom; placeholder top 16.3 vs 16; chip x 58 vs 59, 28 = 28 tall; Stop 34 = 34) | PASS (Stop) | PASS |
| 1 · bottom scroll edge (w3, w4) | PASS | PASS | — | — | PASS | — | PASS. Text is cut 9.7 above the pills (board 8). The line above is unfaded, the cut line about 60% bright. Bands between, beside and below the pills are max 4. | — | — |
| 1 · top scroll edge (w2) | PASS | PASS | — | — | PASS | — | PASS (clip at 115, partly dimmed; board clips at 112 under a 72%→0 fade) | — | — |
| 2 · prose → group header (w1) | — | — | — | — | — | — | PASS (38.3; board 1 gives 37, board 2 gives 35) | — | — |
| 2 · group header + rail | PASS (rail continuous) | PASS | data | PASS | PASS (rail #363636 vs #38383A, 1.67 wide vs 1.5 declared) | PASS | PASS (header→first row 30.7 vs 32; rail starts 9 below header ink = 9; ends 5.7 below last row vs 6; chevron inset 18.3 vs 18) | PASS | n/a |
| 2 · call rows | PASS | PASS | data | PASS | PASS | PASS (open row ⌄, others ›) | PASS (pitch 28 = 28; icon/verb 42.3/62.7 vs 42/62; chevron inset 18 = 18) | PASS | n/a |
| 2 · call card | PASS | PASS | data | PASS (path pitch 17 = 17; code pitch 16 = 16) | PASS | n/a | PASS (236 vs 237; x 39.3 vs 39; card→next row 14.3 vs 14). See O1 for the FILE label. | PASS | n/a |
| 3 · single row + card | PASS | PASS | PASS | PASS | PASS (42 pass green) | PASS | PASS (card 272 = 272; row→card 11 vs 10; inner offsets ≤0.7, COMMAND label +1.3 (O1)); first output line is clipped at the right on both | PASS | n/a |
| 4 · status (queued) | PASS | PASS | PASS ("· 1 queued · Pro") | PASS | PASS | PASS | PASS | PASS | n/a |
| 4 · steps → pills → strip | PASS | PASS (pills allowed) | PASS | PASS | PASS | PASS (terminal icon) | PASS (Edited→Ran pitch 34.3 vs 36 (O3); last step→pill 18 = 18; pill→strip 10 = 10; strip→composer 6 = 6) | PASS | n/a |
| 4 · strip | PASS | PASS | PASS | PASS | PASS (closed #18181A = 0.22 fill; open #2E2E31 ≈ 0.40 fill) except D1 | **FAIL D2** (⋯ dots); spinner matches | PASS (32 = 32; insets 12; text x 45.7 vs 46; text top +11 = 11; ⋯ inset 11.3 vs 11.4) | PASS | n/a |
| 4 · strip menu | PASS | PASS | PASS | PASS | PASS (#29292C vs #2B2B2C; separator #464649 vs #48484A); **FAIL D1** (no shadow on the strip) | PASS (arrow-up, pencil now the board's blunt shape, trash) | PASS (250 × 141.7 vs 250 × 141; rows 56.7/42.7/42.3 vs 56/43/42; 8 = 8 above strip; text inset 16.7 vs 17; icon inset 19 = 19; row tops 13.7/71.3/114 vs 13/70/114) | PASS | n/a |
| 5 · status / transcript / strip / composer | PASS | PASS (no pills offline) | PASS | PASS | PASS (dot without ring; "Not sent" #FF6665 vs #FF6961; send fill #38383B vs #3A3A3B); D1 applies to the strip | PASS (!, send arrow 11.3 vs 12, paperclip); **FAIL D2** (⋯) | PASS (last baseline→strip 24 = 24; bubble→prose −1.5 (O2); placeholder top 16.3 vs 17; send 34 = 34) | PASS (disabled send) | n/a |
| 5 · strip menu | PASS | PASS (Retry/Edit/Delete) | PASS | PASS | PASS (tint over the bubble #272C36 vs #2C2F35); **FAIL D1** | PASS (retry, pencil, trash) | PASS (230 × 127.3 vs 230 × 128; row tops 14.3/57.3/100 vs 15/57/100; 8.3 vs 8 above strip; insets 17.3/18 vs 17/18) | PASS | n/a |
| 6 question · panel | PASS | PASS | accepted header; title wraps on the board only (data) | PASS | PASS (#1A1A1C ≈ #1C1C1E; border #373737 vs #38383A) | PASS (send arrow) | PASS (insets 8; header 24 vs 25; title→body; options 48 = 48, gap 8 = 8; option text x 74.7 vs 75; field 46 = 46, 12 = 12 below options; field→bottom 26 vs 27; panel 383 vs 385 after removing the wrapped line) | PASS (pills and composer hidden) | n/a |
| 6 permission · panel | PASS | PASS | PASS | PASS | PASS | PASS | PASS (289.3 vs 291 intended; code box 38 = 38; title ascender→box 28.3 vs 28.7 from DOM; buttons 48 = 48 at +163.7 vs +165; link +237.7 vs +238) | PASS | n/a |
| 6 plan · panel | PASS | PASS | data (item 2 wraps on the board only) | PASS | PASS | PASS | PASS (item pitch 25 = 25; box 91 = 91 for one-line items; link and buttons ≤1 after the wrapped line; panel 287.7 vs 289/290) | PASS | n/a |
| 7 sign-in · panel | PASS | PASS (no Dismiss, G badge, key) | data (step line) | PASS (footnote pitch 18.3 vs 18) | PASS (badge #38383B vs #3A3A3B) | PASS (key, G) | PASS (panel 326.7 vs 327 intended; card 59.7 vs 59; badge 32 with margins 14/14 vs 14/13; button 50.3 vs 50; footnote→bottom 29.3 vs 29; all offsets ≤1.3) | PASS | n/a |
| Whole screen: fixed chrome | PASS. The pills (705–741) and composer (751–846) are at the same place in w0, w1 and w3. The composer sits 28 from the bottom on every screen with one. Pills leak onto no panel screen. | | | | | | | | |

## Findings (board vs app, both measured)

**D1. Boards 4 and 5: the strip menu's shadow is missing.**
- Board: the menu declares `box-shadow: 0 12px 40px rgba(0,0,0,0.6)`. Under the menu, the strip reads #202022 1 pt below its top and ramps to #2D2D31 at its bottom. Beside the menu (x 100), it reads #303033.
- App (q2, f1): the strip is a flat #2E2E31 at every sampled point: under the menu, beside it, top and bottom. The open strip is not darkened at all.
- The gap at the strip top under the menu is about 16 levels, well above h264 noise.
- Crops: `zoom-menu-shadow-b4-vs-q2.png`, `zoom-menu-shadow-b5-vs-f1.png`, and pair `b4-strip-open`.
- Cause (hypothesis): the menu has no shadow, or the strip is drawn above it.

**D2. Boards 4 and 5: the dots in the strip's ⋯ glyph.**
- Board: the dots are `r=0.9` circles. They inherit the SVG's 1.8 stroke, so each renders about 2.4 pt across in the 16-pt icon. This shows clearly in the 3x board render.
- App: the dots are 1.33 pt across.
- The ring (13.3 tall vs 13.2) and the dot pitch (2.67 = 2.67) match.
- Crops: `zoom-ellipsis-b4-vs-q0.png`, `zoom-glyphs3x-b4-vs-q2.png`, `zoom-glyphs3x-b5-vs-f1.png`.
- The owner's path-data rule may be read to cover this, since the app likely draws the same circles without the inherited stroke. It is listed so the owner can accept it or ask for bolder dots.

**Observations within the measurement limit (not counted):**
- **O1.** The card section labels FILE and COMMAND sit 1.3–2.0 pt lower from the card top: board 13 by ink (13.7 from DOM metrics) vs app 15.0 (board 2) and 14.3 (board 3). The content below them, and the RESULT/OUTPUT labels, are within 1 of the board.
- **O2.** The gap from the bubble bottom to the first prose cap is 1.3–1.5 pt tighter (board 1: 19 vs 17.7; board 5: 19 vs 17.5).
- **O3.** On board 4, the pitch from the collapsed Edited step to the Ran step is 34.3 vs 36.
- **O4 (behaviour, not graded).** The transcript is bottom-anchored. Opening a call card (w2) therefore pushes the tapped row up under the top fade, and a swipe is needed to see the header. The boards are static and cannot show this.

## Round-4 findings re-checked

| Round 4 | Now |
|---|---|
| F1 board 5 transcript→strip −2.7 | Fixed: last baseline→strip 24 = 24 |
| F2 board 7 card 61 vs 59; panel −4.3; bottom inset −2.7 | Fixed: card 59.7 vs 59; panel 326.7 vs 327; footnote→bottom 29.3 vs 29 |
| F3 composer paperclip (two-loop, 18×20) | Fixed: 17×18.3 with the board's three-arc path (3x compare) |
| F3 menu Edit pencil (pointed) | Fixed: blunt parallelogram matching `M4 20h4L19 9l-4-4L4 16z` (3x compare) |
| Card label +1.7 (observation) | Still at the limit (O1) |

## Whole screen, exclusions, gaps

- **Interactions tested (point taps and swipes):**
  - Expanding a step and opening a call card.
  - Opening and collapsing a single-call card.
  - Opening the strip menu in both states.
  - A slow swipe of the transcript, and a sideways swipe of the pills row.
- **Board disagreements resolved by the owner rule:**
  - Board 1 uses 14 between transcript items; boards 2 and 6 use 12.
  - Board 4 draws the single-call row in sans with no duration.
  - The chip chevron, and assistant ink #F2F2F7 vs #FFFFFF.
- **Excluded by owner decisions:**
  - The glass back and tools buttons, and the model-chip system menu.
  - Sample data, title and plan wraps, the "Claude is asking" header, "Medium", and the pills omitted on boards 4–7.
  - The pinned-transcript gaps on the permission, plan and sign-in boards, and text-width differences.
- **Not verified:**
  - Exact colours: h264 frames only.
  - Scroll physics: one slow synthetic swipe; no long-list fixture.
  - Menu and panel actions: not tapped.
  - Board 2's dimmed last code line (#636366) has no fixture counterpart.
  - Board 2's simplified pills were not graded; board 1 specifies the pills.
  - The spinner is animated, so its arc angle is not comparable frame to frame.

## Timing (observed)

| Phase | Time |
|---|---|
| Preparation (scope, round-4 report, build provenance) | 20:30–20:31 |
| App capture, 15 frames (8 `flowdeck run` launches, 6 gestures) | 20:31–20:39 (keepalive 20:46) |
| Design capture, 9 renders + DOM dumps | 20:39–20:46 |
| Comparison (pixel probes, 3x glyph renders 20:52–21:05, crops) | 20:46–21:15 |
| Report | 21:15–21:22 |

**Tool notes:**
- The worktree guard rejects shell variables and loops in commands, so the tools were run with literal paths.
- There was a 20-minute gap between flowdeck commands (20:46–21:06), during design capture and analysis. The idle guard shut the simulator down: `flowdeck simulator list` showed `Shutdown`, and a recording at 21:06 wrote 0 bytes. Every app state had been captured before the gap, so nothing was re-captured and the simulator was not rebooted.
- One `flowdeck simulator list --json` ran without `-S`. It only lists devices and boots nothing.
- The Chrome tab group was gone by the end, so two inert localStorage keys (`__r5dump`, `__r5glyphs`) remain on the 127.0.0.1:8793 origin.
