# Phase 2 session view (phone), round 4: independent design verification

**Verdict: FAIL (minor deltas only).** Every round-3 finding (F1–F6) is fixed or reduced. No structural, copy, colour or state mismatch was found on any board. What remains is small:

1. Board 5: the transcript now ends 2.7 pt too close to the unsent strip. Round 3 had it 14.3 pt too far (F1).
2. Board 7: the site card is 2 pt tall, and the panel's bottom inset is 2.7 pt short. The panel is 4.3 pt short overall (F2).
3. Boards 1, 4, 5: the composer paperclip and the menu Edit pencil are system-style glyphs, not the boards' drawings (F3).

Per board: 1 FAIL (F3 only), 2 PASS, 3 PASS, 4 FAIL (F3 only), 5 FAIL (F1, F3), 6 PASS in all three kinds, 7 FAIL (F2).

## Scope, build, method

- **Design.** Local render at `http://127.0.0.1:8793/`. The board files are dated 10-15 13:50; the kind copies are dated 17:21. The kind copies differ from `s2-question.dc.html` only in `"default"` (verified by `diff`).
  - Captured in a new Chrome tab (claude-in-chrome): viewport 700×857, DPR 1, zoom region [0,0,390,844] → `design/*.png` (390×844).
  - One DOM dump per board, taken inside the 390×844 artboard → `design/*.txt`. It records rects, computed type, colours, radii, padding and SVG paths. The dumps were posted to a temporary receiver on 127.0.0.1:8798, which has since been stopped.
- **App.** Worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree (`git diff -- ios` sha1 `ce2b10ba…`).
  - `LFG.app` was built at 19:41:01, after the newest iOS source mtime (19:40:47). It was installed by the supplied `flowdeck run … --launch-env LFG_S2_VIEW_FIXTURE=<mode>` commands. The first run was an incremental build with no source changes since 19:41.
  - Simulator: iPhone 17 Pro, `C47EB72F-A352-44C9-8A80-9F13D33780AD`.
- **Capture.** `flowdeck ui simulator record --codec h264`, keeping the last frame with ffmpeg (`tools/cap.sh`). Frames are 1206×2622 = 402×874 pt at 3 px/pt. The .mov intermediates were deleted. The PNG SHA-256 hashes are in `crops/index.json`. No AX frames were available (known screen/session failure), so all app geometry is measured from pixels.
- **Measurement.**
  - Ink runs along rows and columns, colour transitions and cell colour samples: `tools/m.py`, `tools/bands.py`, `tools/rowprof.py`, `tools/samp.py`.
  - Distances are glyph edge to glyph edge, or box edge to box edge.
  - Board resolution is ±1 pt (1x raster). App resolution is ±0.33 pt.
  - Deltas of 1.7 pt or less are treated as within the combined measurement limit. Larger deltas are reported.
- **Colour.** The h264 frames read about 2–4 levels low on flat fills and about 6 levels high on small text. No colour was graded on a difference under 15 levels.
- **Borders.** The boards declare `0.5px` borders. Chrome at DPR 1 draws them 1 px wide, so board boxes measure 1 pt taller than intended (pill 38 → 37, composer 96 → 95). The app draws 1–2 device-pixel hairlines, which matches the 0.5 pt intent. This is not a delta.
- **Paired crops.** `crops/<id>-design.png` and `crops/<id>-app.png` (native pixels). Browse with `crops/review-01..05.png`. Enlarged glyph pairs are `crops/zoom-*.png`.

| Frame | State |
|---|---|
| w0 | working, collapsed |
| w1 | "Read 6 files, ran 3 commands" expanded |
| w2 | `Read ios/LFG/SessionStore.swift` card open (bottom-anchored) |
| w3 | w2 swiped down so the header, card and rows show; text reaches the pills |
| w4 | w3 with the pills scrolled to Terminal |
| q0, q1 | queued; "Ran bun test" card open |
| q2, q2b | step collapsed with the strip menu open; q2b is re-recorded 2 s later and is identical |
| f0, f1 | failed (offline); strip menu open |
| k-question, k-permission, k-plan, s0 | the three panel kinds, and sign-in |
| keepalive1–3 | idle sign-in screen, used only to keep the simulator active |

## Matrix (component × state × criteria)

Columns are the nine criteria: consistency, structure, copy, type, colour, glyphs, spacing/shape, state, chrome. F# refers to the findings below. "data" means the difference is fixture sample text, which is accepted.

| Board · component | Cons | Struct | Copy | Type | Colour | Glyph | Spacing | State | Chrome |
|---|---|---|---|---|---|---|---|---|---|
| 1 · top bar + status | PASS | PASS | PASS | PASS (title cap 13.3 vs 14; status 13 vs 14) | PASS (#30D158; ring dot 12.3 vs 13) | PASS | PASS (title→status 20.7 vs 20) | PASS | PASS (glass buttons accepted) |
| 1 · bubble | PASS | PASS | data | PASS (line pitch 22 = 22) | PASS (#066CDE ≈ #0A6EE0) | n/a | PASS (318 wide, 16 right inset, text inset 14.7 vs 15, top 12.7 vs 13) | n/a | n/a |
| 1 · prose + steps | PASS | PASS | data | PASS (prose pitch 24; step label 15) | PASS | PASS (icon x18.3, label x42.3, chevron 19.7 inset) | PASS (bubble→prose −1.3; prose→step +1.3; step→prose +0.7; last step→pill 17.3 vs 18) | PASS | n/a |
| 1 · pills | PASS | PASS (Subagents, Files; Terminal on scroll) | PASS | PASS | PASS (#1A1A1A on #1C1C1E; ring arcs) | PASS (ring 19.3 vs 20; doc 9.3×13 vs 10×13) | PASS (x16, 36.3 vs 37 intended, gap 8, 10 above composer) | PASS | n/a |
| 1 · composer | PASS | PASS | PASS | PASS | PASS | **FAIL F3** paperclip; chip chevron and Stop square 11×11 match | PASS (95 tall, 28 from bottom, placeholder top 16.3 vs 16, chip x58 vs 59, 27.3 vs 28 tall) | PASS (Stop) | PASS |
| 1 · bottom scroll edge (w3, w4) | PASS | PASS | — | — | PASS | — | PASS. Text is cut about 9.5 above the pills (board 8). Fade starts about 25 above the pill top (board 24). Bands between, beside and below the pills are max 1. | — | — |
| 1 · top scroll edge (q1) | PASS | PASS | — | — | PASS (66% → 100%) | — | PASS. Clip at 116, full at 127; status bottom +13.7 (board +11 to 124) | — | — |
| 2 · prose → group header (w1) | — | — | — | — | — | — | PASS (25.3; board 1 gives 24, board 2 gives 22) | — | — |
| 2 · group header + rail | PASS (rail continuous) | PASS | data | PASS (meta 11 tall both) | PASS (rail #363636 vs #38383A) | PASS (down chevron) | PASS (header→first row −1; rail starts 9 below header ink, matching the board; chevron right inset 18.3 vs 18) | PASS | n/a |
| 2 · call rows | PASS | PASS | data | PASS (verb cap 10.3 vs 10) | PASS | PASS (open row down, others right) | PASS (pitch 28 = 28; icon/verb/path x 42.3/62.7/103 vs 42/62/103; chevron inset 19) | PASS | n/a |
| 2 · call card | PASS | PASS | data | PASS (input pitch 17 = 17; code pitch 16 = 16) | PASS | n/a | PASS (236 vs 237; x39.3 vs 39; label +1.7, other offsets ≤1) | PASS | n/a |
| 3 · single row + card | PASS | PASS | PASS | PASS | PASS (42 pass green) | PASS | PASS (card 272 = 272; row→card 10.7 vs 10; inner offsets ≤1 apart from the label at +1.7) | PASS | n/a |
| 4 · status (queued) | PASS | PASS | PASS ("· 1 queued · Pro") | PASS | PASS | PASS | PASS | PASS | n/a |
| 4 · steps → pills → strip | PASS | PASS (pills allowed) | PASS | PASS | PASS | PASS | PASS (Edited→Ran pitch 34.7 vs 36; last step→pill 18.3 vs 18; strip 6 above composer) | PASS | n/a |
| 4 · strip | PASS | PASS | PASS | PASS | PASS (closed #18181A = board's 0.22 fill #1A1A1C; open #2E2E31 = 0.40 fill #2F2F33) | PASS (spinner, ⋯) | PASS (32 tall, 12 insets, text x45.7 vs 46, ⋯ 11.3 inset vs 11) | PASS | n/a |
| 4 · strip menu | PASS (transcript shows through faintly on both) | PASS | PASS | PASS | PASS (#29292C vs #2B2B2C; separator #464649) | **FAIL F3** Edit pencil; arrow-up and trash match | PASS (250 × 141.7; rows 56/42/42.3 vs 56/43/42; 8 above strip; insets 17.3/18.7 vs 17/19) | PASS | n/a |
| 5 · status / strip / composer | PASS | PASS (no Terminal pill offline) | PASS | PASS | PASS (dot without ring; "Not sent" #FF6665; send fill #38383B vs #3A3A3B) | PASS (send arrow 11.3 vs 12); **FAIL F3** paperclip | **FAIL F1**; strip and composer otherwise PASS (placeholder 16.3 vs 17) | PASS (disabled send) | n/a |
| 5 · strip menu | PASS | PASS (Retry/Edit/Delete) | PASS | PASS | PASS (bubble tint #272C34 vs #2C2F35) | PASS (retry, trash); **FAIL F3** pencil | PASS (230 × 127.7 vs 230 × 128; rows 42/42/42.3; 8 above strip) | PASS | n/a |
| 6 question · panel | PASS | PASS | accepted header | PASS | PASS | PASS (send arrow 10×10 = 10×10) | PASS (title baseline→body 12.7 vs 12; body→option 17.7 vs 17; options 48/56; field 46 = 46; insets 8) | PASS (pills and composer hidden) | n/a |
| 6 question · prose → panel | — | — | — | — | — | — | PASS (16.3 vs 17) | — | — |
| 6 permission · panel | PASS | PASS | PASS | PASS | PASS | PASS | PASS (box 38 = 38; offsets ≤1.7; panel 289.7 vs 291 intended) | PASS | n/a |
| 6 plan · panel | PASS | PASS | PASS | PASS | PASS | PASS | PASS (item pitch 25 = 25; box 90.3 vs 91 one-line value; offsets ≤1.7) | PASS | n/a |
| 7 sign-in · panel | PASS | PASS (no Dismiss, G badge, key) | data (step line) | PASS (footnote pitch 18.3 vs 18) | PASS | PASS (key, G) | **FAIL F2** | PASS | n/a |
| Whole screen: fixed chrome | PASS. Top bar, pills (705–741) and composer (751–846) are in the same place in w1 and w3. | | | | | | | | |

## Findings (board vs app, both measured)

**F1. Board 5 (f0): transcript end → unsent strip.**
- Board: the last prose baseline is at 658 ("on"), and the strip top is at 682. The gap is 24.
- App: the last prose baseline is at 691.7 ("download."), and the strip top is at 713. The gap is 21.3.
- Δ −2.7. Round 3 measured this gap at +14.3, so the fix overshot.
- The other end-of-transcript gaps match: last step → pill 17.3 vs 18, and prose → question panel 16.3 vs 17.
- Crop: `b5-transcript-strip-*`.

**F2. Board 7 (s0): sign-in panel.**
- **Site card:** board 59 tall vs app 61 (+2). The badge sits 14/13 from the card's top and bottom on the board, and 14.7/14.3 in the app. Round 3 measured 63, so this is partly fixed.
- **Panel height:** board 328 (327 intended) vs app 323.7 (−4.3).
  - Most of it is at the bottom: footnote descender → panel bottom is 29 vs 26.3 (−2.7).
  - Title → body is 9 vs 8 (−1).
  - All other gaps are within 1.3: header, title, card→button 14 = 14, button→footnote 17 vs 16.3, button 50 vs 50.7.
- Crops: `b7-panel-*`, `b7-sitecard-*`.

**F3. Glyphs drawn in system style, not the board's (boards 1, 4, 5).**
- **Composer paperclip:** the board uses a three-loop outline, ink 18×18 at x31. The app uses a two-loop paperclip, ink 18×20 at x29.7: 2 pt taller and a different shape. Crop: `zoom-paperclip-b1-vs-w0.png`.
- **Strip menu "Edit" icon:** the board's pencil is a blunt parallelogram (`M4 20h4L19 9l-4-4L4 16z`). The app's pencil has a pointed tip. Crop: `zoom-menu-icons-b4-vs-q2b.png`.
- The feature plan says only step, call, Files and Terminal icons are drawn from the boards, and none of the owner decisions covers these two. They are listed so the owner can either accept them as a translation or have them redrawn. Every other glyph matches: step and call icons, Files doc, ring, spinner, ⋯, retry, unsent "!", key, trash, arrow-up, chevrons, Stop and send. See `zoom-glyphs-sheet-a.png` and `zoom-glyphs-sheet-b.png`.

**Observation, not counted:** the card section labels ("FILE", "COMMAND") sit 1.7 pt lower than on the board (14.7 vs 13 from the card top). The content below them is at the board's position. This is at the measurement limit.

## Round-3 findings re-checked

| Round 3 | Now |
|---|---|
| F1 text behind the pills | Fixed. The bands around the pills are max 1. A fade matches the board's. |
| F2a last step → pill +3.7 | Fixed (−0.7) |
| F2b prose → strip +14.3 | Overshoots: −2.7 (F1) |
| F2c prose → panel +6.3 | Fixed (−0.7) |
| F3 call-row pitch 30 | Fixed (28) |
| F4 question title→body, body→option, field 44 | Fixed (12.7 vs 12, 17.7 vs 17, 46) |
| F5 sign-in card 63 | Partly fixed: 61 vs 59 (F2) |
| F6a bubble pitch 24 | Fixed (22) |
| F6b card input pitch 18.7 | Fixed (17) |
| F6c single row → card +2 | Fixed (row centre → card 16.5 = 16.5) |
| F6d placeholder | Fixed (16.3 vs 16; 16.3 vs 17 offline) |
| F6e chip x | Fixed (58 vs 59) |
| F6f panel send arrow | Matches (10×10) |
| F6g card x | Fixed (39.3 vs 39) |
| F6h Files icon | Matches in raster (9.3×13 vs 10×13) |

## Whole screen, exclusions, gaps

- **Interactions tested:**
  - Expanding a step, opening a call card, opening and collapsing a single-call card.
  - Opening the strip menu in both states.
  - Swiping the transcript, and swiping the pills row sideways.
  - All taps used point coordinates.
- **Board disagreements resolved by the owner rule:**
  - Board 1 uses 14 between transcript items. Boards 2 and 6 use 12, and board 6 draws an 18-tall step row.
  - Board 4 draws the single-call row in sans with no duration.
  - The chip chevron, and assistant ink #F2F2F7 vs #FFFFFF.
- **Board strip state:** both boards show only the menu-open strip fill (0.40). The closed fill (0.22) comes from the board source's `rowBg` and matches the app.
- **Excluded by owner decisions:**
  - Glass back and tools buttons, and the model-chip system menu.
  - Sample data: "Read 6 files", the board-2 card text, the board-2 and board-6 titles wrapping in Chrome, the plan item wrap, the sign-in step line.
  - The "Claude is asking" header, "Medium", and pills omitted on boards 4–7.
  - The pinned-transcript gaps on the permission, plan and sign-in boards, and text-width differences.
- **Not verified:**
  - Exact colours: h264 frames only.
  - Scroll physics: one slow synthetic swipe; no long-list fixture was supplied.
  - Menu actions (Send now, Edit, Remove, Retry, Delete) and panel buttons were not tapped.
  - Board 2's dimmed last result line (#636366) has no counterpart in the fixture data.
  - Board 2's simplified pills (no icons) were not graded. The pills are specified by board 1.

## Timing (observed)

| Phase | Time |
|---|---|
| Preparation (scope, round-3 report, build check) | 19:43–19:44 |
| App capture, 14 frames (8 `flowdeck run` launches, 7 gestures) | 19:44–19:51 |
| Design capture, 9 renders + DOM dumps | 19:52–19:58 |
| Comparison (pixel probes, crops, glyph zooms) | 19:58–20:24 |
| Report | 20:24–20:30 |

**Tool notes:**
- The worktree guard rejected a shell `for` loop over frames, so `tools/samp.py` takes several images in one call.
- There was a 21-minute gap between flowdeck commands (19:57–20:18), but the simulator stayed booted on the sign-in screen (`keepalive2.png`).
- One `flowdeck simulator list` ran without `-S`. It only listed devices and did not boot a simulator.
- No capture failures.
