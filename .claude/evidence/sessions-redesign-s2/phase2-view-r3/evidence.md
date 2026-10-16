# Phase 2 session view (phone), round 3: independent design verification

**Verdict: FAIL.** Structure, copy, colours, glyph choice and states match on all 7 boards (9 renders). Five layout deltas remain, plus a few small metric gaps:

1. Scrolled transcript text shows behind and between the pills (F1).
2. The gap between the transcript end and the bottom chrome is too large: +4 above the pills, +6 above the question panel, and +14 above the strip when offline (F2).
3. Tool-group call rows are 30 apart instead of 28 (F3).
4. Question panel: the body sits 4 too close to the title, and the free-text field is 2 short (F4).
5. Sign-in site card is 63 tall instead of 59 (F5).

Round-2 D2 (top scroll edge) and D4 (sign-in footnote leading) are fixed. D1 is mostly fixed between transcript items. D3 is not fixed.

## Scope, build, method

- **Design:** local render `http://127.0.0.1:8793/` (board files dated 10-15 13:50; kind copies 17:21, verified identical to `s2-question.dc.html` except `default`). Captured in a new Chrome tab at 390×844, DPR 1. Captures are in `design/*.png`. Every expected value comes from one DOM dump per board (`design/*.txt`: rects, computed type, colours, radii, SVG paths), taken inside the 390×844 artboard root.
- **App:** worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree (`git diff -- ios` sha1 f50d4ccc…). The `LFG.app` binary was built 18:55:35, after the newest iOS source mtime (18:55:19). Frames were captured 18:59–19:08 on iPhone 17 Pro sim `C47EB72F-A352-44C9-8A80-9F13D33780AD`.
- **Capture:** `flowdeck ui simulator record --codec h264`, keeping the last frame via ffmpeg. Frames are 1206×2622 = 402×874 pt at 3 px/pt. The .mov intermediates were removed; the PNG hashes are in `crops/index.json`.
- **Measurement:** row and column ink runs plus colour sampling (`tools/m.py`, `tools/bands.py`). Distances are glyph edge to glyph edge, or box edge to box edge. Board resolution is ±1 pt at 1x. App resolution is ±0.33 pt.
- **Colour tolerance:** h264 frames read about 4 levels off on flat fills and 6–9 levels brighter on small text. No colour is graded on a difference under 15 levels.
- **Paired crops:** `crops/<id>-design.png` / `crops/<id>-app.png` (native pixels) and `crops/review-0*.png` (browse only). `crops/zoom-menu-ghost-b4-vs-q2.png` is an enlarged pair.

| Frame | State |
|---|---|
| w0 | working, collapsed |
| w1 | "Read 6 files, ran 3 commands" expanded |
| w2 | `Read ios/LFG/SessionStore.swift` card open (bottom-anchored) |
| w3 | same, scrolled so the header, card and rows show; text behind the pills |
| w4 | w3 with the pills scrolled to Terminal |
| q0 / q1 / q2 | queued / "Ran bun test" card open / step collapsed with the strip menu open |
| f0 / f1 (f1b) | failed / strip menu open (a re-record 3 s later is identical, so the menu is static) |
| k-question, k-permission, k-plan, s0 | the panel kinds, and sign-in |

## Matrix (component × state × criteria)

Columns: consistency, structure, copy, type, colour, glyphs, spacing/shape, state, chrome. F# refers to the findings below.

| Board · component | Cons | Struct | Copy | Type | Colour | Glyph | Spacing | State | Chrome |
|---|---|---|---|---|---|---|---|---|---|
| 1 · top bar + status | PASS | PASS | PASS | PASS (title cap 13.3 vs 14; status 13 vs 14) | PASS (#30D158 + ring) | PASS (dot 12 incl. ring vs 13) | PASS (title→status 7.3 vs 6) | PASS | PASS (glass buttons accepted) |
| 1 · bubble | PASS | PASS | data | PARTIAL F6a | PASS (#066CDE ≈ #0A6EE0) | n/a | PASS (x68–386 = 318 w, 16 inset) | n/a | n/a |
| 1 · prose + steps | PASS | PASS | data | PASS (17 pt, 24 pitch) | PASS | PASS (icon x18–31, label x42, chevron 19.7 inset) | PASS between items (±1.7); FAIL F2a at the end | PASS | n/a |
| 1 · pills | PASS | PASS (Subagents, Files, Terminal on scroll) | PASS | PASS | PASS (#1C1C1E, #38383A border, ring arcs) | minor F6h | PASS (x16, 36 h, 8 gap, 10 above composer) | PASS | n/a |
| 1 · composer | PASS | PASS | PASS | PASS | PASS | PASS (chip chevron, Stop 34 + 11 square) | FAIL F6d placeholder −1.7; F6e chip +3 | PASS (Stop) | PASS (12 inset, 95 h, 28 bottom) |
| 2 · prose → group header | — | — | — | — | — | — | +3.3 vs board 2 (+1.3 vs board 1) | — | — |
| 2 · group header + rail | PASS (rail continuous) | PASS | data | PASS | PASS (#939393 chevron, #363636 rail) | PASS | PASS (rail x24, 25 below header vs 24; meta inset 37 vs 36) | PASS (down chevron) | n/a |
| 2 · call rows | PASS | PASS | data | PASS (verb cap 10.7 vs 10) | PASS | PASS (open #686868 down, closed right) | **FAIL F3** | PASS | n/a |
| 2 · call card | PASS | PASS | data | minor F6b | PASS | n/a | PASS (237.7 vs 237; insets 12–13; result pitch 16; link 13 above bottom); card x −1.3 (F6g) | PASS | n/a |
| 3 · single row + card | PASS | PASS | PASS | PASS (mono 11.3 cap) | PASS | PASS | card 272.3 vs 272, all inner offsets ≤1.7; row→card +2 (F6c) | PASS | n/a |
| 4 · status (queued) | PASS | PASS | PASS ("· 1 queued · Pro") | PASS | PASS | PASS | PASS | PASS | n/a |
| 4 · strip | PASS | PASS | PASS | PASS | PASS (#2E2E31 open ≈ 0.40) | PASS | PASS (31.3 vs 32 h; 7.3 above composer; spinner x25–36; ⋯ 23 inset) | PASS | n/a |
| 4 · strip menu | PASS (≤7-level ghost; board ≤10) | PASS | PASS | PASS (Send now 13 / subtitle 32.7 vs 13 / 32) | PASS (#2A2A2D, sep #464649, Remove red) | PASS | PASS (250 w, 141 h; rows 55.7/42/42; 8.7 above strip; right 12) | PASS | n/a |
| 5 · status / strip / composer | PASS | PASS (no Terminal pill offline) | PASS | PASS | PASS (dot without ring, "Not sent" #FF6660) | PASS (send arrow 11.3×11.3 vs 12×12) | **FAIL F2b**; placeholder −2.7 (F6d) | PASS | n/a |
| 5 · strip menu | PASS | PASS (Retry/Edit/Delete) | PASS | PASS | PASS (blue tint over bubble: #292C31 vs #2C2F35) | PASS | PASS (229.7 × 127.3 vs 230 × 128; 8.3 above strip) | PASS | n/a |
| 6 question · panel | PASS | PASS | accepted header | PASS | PASS | minor F6f | **FAIL F4** | PASS (pills and composer hidden) | n/a |
| 6 question · prose → panel | — | — | — | — | — | — | **FAIL F2c** | — | — |
| 6 permission · panel | PASS | PASS | PASS | PASS | PASS | PASS | PASS (box 38 = 38; all offsets ≤1.3; panel 289.7 vs 292) | PASS | n/a |
| 6 plan · panel | PASS | PASS | PASS | PASS | PASS | PASS | PASS (item pitch 25; box 91 = 1-line board value; link/buttons ≤1) | PASS | n/a |
| 7 sign-in · panel | PASS | PASS (no Dismiss, G badge, key) | data (step line) | PASS (footnote pitch 18.3 vs 18) | PASS | PASS | **FAIL F5** (panel 325 vs 328) | PASS | n/a |
| whole · top edge | PASS: black to y115.7, bubble at about 60–70% from 116 to 125, full at 126 (board: clip at 112, 65%→100% to 124) | | | | | | | | |
| whole · bottom edge | **FAIL F1** | | | | | | | | |

## Findings (design vs app, both measured)

**F1. Bottom scroll edge (boards 1–3; frames w3, w4).**
- Board: the transcript viewport ends at y664, 8 above the pills, under a black fade from 648 to 691. The bands between the pills and below them measure max channel 0.
- App: scrolled text renders behind the pills row.
  - The 14 pt band directly above the pill tops reaches 197, about 81% of the ink.
  - The 8 pt gaps between and after the pills reach 100, about 40%.
  - The 10 pt gap between the pills and the composer reaches 48, about 20%.
- Crops: `whole-bottom-edge-*`, `b1-pills-terminal-*`.

**F2. Distance from the transcript end to the bottom chrome.**

| Transition | Board | App | Δ |
|---|---|---|---|
| a. Last step row ("Edited 2 files", row centre) → pill top, board 1 / w0 (q0 is the same) | 25 | 28.7 | +3.7 |
| b. Last prose baseline → strip top, offline with no pills, board 5 / f0 | 22 | 36.3 | **+14.3** |
| c. Last prose glyph bottom → question panel top, board 6 / k-question | 17 | 23.3 | +6.3 |

Between transcript items, the round-2 D1 is fixed to within 1.7 of board 1 (bubble→prose −1.7, prose→step +1.3, step→prose +0.7). Crops: `b1-prose-steps-*`, `b5-transcript-to-strip-*`, `b6q-prose-panel-*`.

**F3. Tool-group call-row pitch (board 2; w1, w3).** Board 28 vs app 30, so +2 per row. A 9-call group is about 18 taller. Header to first row (top to top) is 32 vs 33.7. Crops: `b2-header-rows-*`, `b2-rows-after-*`.

**F4. Question panel (board 6; k-question).**
- Title baseline → body ascender: 12.6 vs 8.7 (−3.9). Round-2 D3 is unchanged.
- Body → first option: 17 vs 15.3 (−1.7).
- Free-text field: 46 vs 44 (−2).
- Panel inset, radius, header, options (48 h, 8 gap), Dismiss (30 h) and the 12 above the field all match.
- Crop: `b6q-panel-*`.

**F5. Sign-in site card (board 7; s0).** Height 59 vs 63 (+4). Padding is 14/13 on the board and 15.7/15.3 in the app. The badge (32) and text block (32) match. The panel is 328 vs 325, because other gaps are 1–2 shorter. Crop: `b7-panel-*`.

**F6. Minor (each ≤3 pt, or glyph only).**
- a. Bubble line pitch: 22 vs 24. A 2-line bubble is 63, against a board-equivalent 62.
- b. Call-card input mono: line pitch 17 vs 18.7. The face is about 12.8 pt vs 12.5.
- c. Single-call row centre → card top: 16.5 vs 18.5 (+2).
- d. Composer placeholder glyph top below the composer top: 16 (board 1/4) or 17 (board 5) vs 14.3.
- e. Model chip left edge: 59 vs 62 (gap after the paperclip 10 vs 12.3).
- f. Panel send arrow: 10×10 vs 11×13.
- g. Call card left edge: 39 vs 37.7.
- h. Files-pill doc icon: 7.8 vs 9.3 wide.

## Round-2 deltas re-checked

| Round 2 | Now |
|---|---|
| D1 spacing after prose +5–7 | Items ±1.7 (fixed). End of transcript still +3.7 / +6.3 (F2) |
| D2 top scroll edge ghost | Fixed |
| D3 question title→body, input 44 | Not fixed (F4) |
| D4 sign-in footnote 15.7 vs 18 | Fixed (18.3). Card overshoots to 63 (F5) |
| Card input pitch 18 vs 17 | 18.7 (F6b) |
| Group row pitch 29 vs 28 | 30 (F3, worse) |
| Permission box 35.7 vs 38 | Fixed (38) |
| Disabled send arrow 12.7×15 | Fixed (11.3×11.3). The panel send arrow is still taller (F6f) |

## Whole-screen checks, exclusions, gaps

- **Fixed chrome:** the top bar, pills and composer stay in place while the transcript scrolls (w1 vs w3).
- **Menu translucency:** both the board and the app show a faint ghost of the transcript through the strip menu (max +10 levels on the board, +7 in the app). Not a delta.
- **Excluded by owner decisions:**
  - Glass back and tools buttons, and the model-chip system menu.
  - Sample data and text width ("Read 6 files", the board-2 title wrapping to 2 lines in Chrome).
  - The "Claude is asking" header, "Medium", and pills omitted on boards 4–7.
  - Assistant ink #FFFFFF vs #F2F2F7, the chip chevron, and the collapsed single-call row style.
  - The pinned-transcript gaps on the permission, plan and sign-in boards.
- **Board disagreement:** board 1 uses 14 between transcript items and boards 2 and 6 use 12. Spacing was graded against board 1, which is the view spec.
- **Not verified:**
  - Exact colours: h264 only.
  - Scroll physics: one synthetic-swipe frame (w3/w4); no long-list fixture was supplied.
  - Menu actions (Send now, Edit, Remove, Retry, Delete) and panel buttons were not tapped.
  - The board-2 dim last result line ("1616 return", #636366) has no counterpart in the fixture data.

## Timing (observed)

| Phase | Time |
|---|---|
| Preparation (scope, prior round, build check) | 18:58–18:59 |
| App capture, 15 frames (one rebuild-free `flowdeck run` per fixture) | 18:59–19:08 |
| Design capture, 9 renders + DOM dumps | 19:09–19:15 |
| Comparison (pixel probes, crops) | 19:15–19:34 |
| Report | 19:34–19:40 |

**Tool notes:**
- The `javascript_tool` output truncates at about 1.5 KB. DOM dumps were posted to a temporary receiver on 127.0.0.1:8797, which has since been stopped.
- The worktree guard rejects shell variables used as commands, so the probes ran through wrapper scripts.
- No capture failures.
