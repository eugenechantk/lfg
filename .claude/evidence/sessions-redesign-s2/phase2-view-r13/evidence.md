# Visual Design Verifier · sessions-redesign-s2 · phase 2 session view (phone) · round 13

**Overall verdict: FAIL.** One confirmed delta, on board 4 only.

- **D1** (board 4 `s2-queued`): two step rows in a row sit 2 pt too close. The pitch from "Edited 2 files" to "Ran bun test …" is board 36.0 pt / app 34.0 pt.

The two round-12 deltas are fixed in this build. The white-ink roles now measure 253, the same as the white clock. The gap from the sign-in button to the footnote is board 18.0 / app 18.33.

| Board | Verdict | Deltas |
|---|---|---|
| 1 · `s2-view` (working) | PASS | none |
| 2 · `s2-tools-group` (group open, call card open) | PASS | none |
| 3 · `s2-tools-single` (single call open) | PASS | none (the app's fixture also shows the D1 pitch, but board 3 does not picture two step rows in a row) |
| 4 · `s2-queued` (queued, strip menu open) | FAIL | D1 |
| 5 · `s2-queued-failed` (not sent, menu open) | PASS | none |
| 6 · `s2-question` | PASS | none |
| 6 · `s2-question-permission` | PASS | none |
| 6 · `s2-question-plan` | PASS | none |
| 7 · `s2-signin-prompt` | PASS | none |

## Scope and provenance

- **Scope:** the live app compared with HTML boards. Each board is checked whole-screen, component by component, across all nine criteria. These interactions were exercised:
  - expand a group;
  - open a call card;
  - open the single-call card;
  - open the strip menu, queued and failed;
  - tap outside to dismiss the menu.
- **Reference kind:** HTML. Boards come from `http://127.0.0.1:8793/`, which answered 200. Exact values come from `/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/dcrender/project/`.
- **Source sha256 prefixes:**

  | File | sha256 prefix |
  |---|---|
  | `s2-view` | 9c10012276d348cb |
  | `s2-tools-group` | a3911397dba72d9d |
  | `s2-tools-single` | 0aa849bb9891f9d3 |
  | `s2-queued` | cefcef79392790b7 |
  | `s2-queued-failed` | 6e981111f3b1948b |
  | `s2-question` | 51ce62391853e7a8 |
  | `-permission` | 851da0fba3bc51c8 |
  | `-plan` | 3c47cc323f3d9602 |
  | `s2-signin-prompt` | f54a74e4e4a13a9a |
  | `support.js` | 3f160299989dc595 |

- **Renderer:** a new claude-in-chrome tab, 1045567256. Every capture result reported the tab URL, and I checked it before each capture.
  - Viewport 1135×1266, DPR 1, system SF, no web fonts.
  - 3x method: `zoom: 3` on `#dc-root`, then a negative body margin per tile. Each board uses five native tiles: 1135×1000 at artboard y 0, 1000 and 1532, plus 70×1266 strips at x 1100.
  - Tiles are stitched to 1170×2532 by `measure/stitch.py`. The stitch leaves no unfilled pixels, and the maximum channel difference in the overlaps is 0–5.
  - DOM dumps were taken at zoom 1 (`design/dom-*.txt`) and posted to a loopback receiver on port 8798. The receiver is now stopped.
- **Render hashes (sha256 prefix):** b1 040967eebbc516f7, b2 4aa733ce798b70c3, b3 170238fb3793ad27, b4 856457d0eb22664a, b5 79501eee3fb5a501, b6q 3d7ee584bef5aed5, b6p 6aab8a2a09faf6ac, b6l fbf19408c0a4b699, b7 3e5f971ba5aec982.
  - These fresh renders are byte-identical to round 12's renders, which confirms the renderer is deterministic.
  - Baseline: I rendered and measured everything fresh; no round-12 numbers are reused.
- **Renderer artefact:** CSS zoom 3 draws 0.5px borders as one device pixel, and content-box elements with borders shrink by up to 1.33 pt. Example: the question field is 44.67 pt tall at 3x, against a design intent of 45 pt. Per the brief, the 3x pixels are the board truth.
- **App build:** worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree.
  - Installed `LFG.debug.dylib` mtime is 03:04:31, sha256 add338cd3a043399. The newest Swift source mtime is 03:04:19.
  - The dylib mtime was unchanged after every `flowdeck run`.
- **Simulator:** iPhone 17 Pro, C47EB72F-A352-44C9-8A80-9F13D33780AD, 402×874 pt. Frames are the last frame of 1 s h264 recordings, 1206×2622 (3 px/pt).

| Frame | Route | Time | Board | sha256 prefix |
|---|---|---|---|---|
| `app/w.png` | fixture `working` | 03:08:43 | 1 | c06d6688faaae3fd |
| `app/g1.png` | tap (144,555) on "Read 6 files, ran 3 commands" | 03:09:19 | 2 (group open, 9 rows) | 9a9d34673ab67f44 |
| `app/g2.png` | tap (175,354) on "Read ios/LFG/SessionStore.swift" | 03:09:39 | 2 (card open, header scrolled off) | 9cba2dc5146ccc6d |
| `app/g3.png` | swipe from (200,350) to (200,530) over 1.2 s | 03:10:02 | 2 (header and card visible) | c9bbb4f6f648e3a4 |
| `app/q-closed.png` | fixture `queued` | 03:10:33 | 4 (strip at rest) | 64dfe81a39091c21 |
| `app/q-menu.png` | tap (200,728) on the strip | 03:10:54 | 4 | b95c226131dd1a45 |
| `app/q-dismissed.png` | tap (200,300) outside the menu | 03:11:26 | 4 (dismissed) | 6d045a085f7dfee7 |
| `app/s1.png` | tap (131,640) on "Ran bun test …" | 03:11:27 | 3 | d3de43effa14e37f |
| `app/f-closed.png` | fixture `failed` | 03:12:06 | 5 (strip at rest, composer) | 1b2e11660eb5fc10 |
| `app/f-menu.png` | tap (200,728) on the strip | 03:12:34 | 5 | 78d5e96e28b40d33 |
| `app/question.png` | fixture `question` | 03:13:03 | 6 question | 220973aeac30dc41 |
| `app/permission.png` | fixture `permission` | 03:13:43 | 6 permission | 38fa4f3ff3245470 |
| `app/plan.png` | fixture `plan` | 03:14:25 | 6 plan | 98ffa3f4d70c6e79 |
| `app/signin.png` | fixture `signin` | 03:15:10 | 7 | ca7dd1b54a69d96f |

- **Measurement method:**
  - Coordinates are pt (3x px ÷ 3), pixel-measured from ink edges on both sides with the same thresholds. The script is `measure/measure.py`. Queries and outputs are in `measure/q/*.txt` and `*.out`.
  - The app screen is 12 pt wider and 30 pt taller. Bottom-anchored parts are therefore expected 30 pt lower, and right-anchored parts 12 pt further right.
  - Colours are the median of the strongest ink pixels. They are calibrated against the white iOS status-bar clock, which measures 252–253 in every frame.
- **Change locator:** `measure/framediff.py` diffs these frames against round 12's frames. It only located change; it did not decide anything.
  - Title rows changed in every frame (the ink fix).
  - The sign-in panel changed (the footnote fix).
  - The rest is the timer, spinner and h264 noise.

## Accepted exceptions applied (from the brief)

- System glass back and tools buttons, and the system bar height. Measured: the header sits 2.0 pt lower, and the buttons are 44 vs 44.67.
- System model-chip menu.
- Sample text.
- "Claude is asking" without "· 1 of 1".
- "Medium" and the chip chevron.
- The pills row scrolls, and the last pill is clipped.
- Pills appear only where they apply, and are hidden under panels.
- Board conflicts A, B and C.
- Mono single-call step with a duration.
- Composer placeholder position.
- Pinned transcripts on permission, plan and sign-in.
- Word-wrapped card input.
- SVG icons.
- SF text width and line-count consequences.
- Live host state.

`s2-tools-*` draw pills without icons and a composer without the paperclip. The app follows `s2-view`, which is accepted as a board conflict.

## Findings

### D1 · Two adjacent step rows sit 2 pt too close (board 4) — spacing

- **Board 4 DOM:** the "Edited 2 files" row is 606–628 and the "Ran bun test src/sessions.test.ts" row is 642–664. Both rows have `padding:2px 0`, and the container gap is 14, so the pitch is 36.
- **Measured pitch:**

  | Element | Board 4 | App q-closed |
  |---|---|---|
  | Icon tops | 611.33 → 647.33 = 36.0 pt | 600.00 → 634.00 = 34.0 pt |
  | Label tops | 611.00 → 647.67 = 36.67 pt | 599.67 → 634.33 = 34.67 pt |
  | Chevrons | 36 pt (DOM) | 602.00 → 636.00 = 34.0 pt |

- **Same 34 pt pitch elsewhere:** q-menu, q-dismissed and s1 (324.33 → 358.00).
- **Spacing around the pair is correct:**
  - Prose → first step row: board 25.0 / app 25.67.
  - A step row followed by pills (board 1): board 32.0 / app 32.0.
  - The single-call row's icon to its card (board 3): board 22.67 / app 22.67.

  So only the step-to-step spacing is short.
- **Expected value:** decision A sets a 14 pt gap on `s2-queued`, and the app follows `s2-view`, also 14. Expected pitch is 36; the app gives 34.
- **Hypothesis:** the gap between consecutive tool rows is 12 pt, or the single-call row is missing its 2 pt top padding. The first is more likely; I did not inspect the source.
- **Crops:** `crops-extra/b4-step-pair-design.png`, `crops-extra/b4-step-pair-app.png`, `crops-extra/review-01.png`.

## Matrix

Columns: 1 consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 navigation chrome. "Obs n" refers to the observations list below.

| Board / component | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| 1 header + status (working) | PASS | PASS (title centre 201.3 vs screen 201; +2 accepted) | PASS | PASS (title h 13.33 both, status h 13 both) | PASS (title 253 = clock; green #2FD158/#2FCF59; grey #A1A1A6/#A0A0A0) | PASS (dot 7, glow 13/12.67) | PASS | PASS | PASS (system buttons) |
| 1 user bubble | PASS | PASS (right edge 374→386; width 318 both) | PASS | PASS (text inset 14.67 both, pitch 22 both; 2 lines vs 3 = text width) | PASS (#096EE0/#096CDE, text 251–254) | N/A | PASS (top inset 13.33 both) | N/A | N/A |
| 1 prose ×2 | PASS | PASS (x 17.33/16.67 both; +29/+30, Obs 2) | PASS | PASS (pitch 24 both) | PASS (C: 240) | N/A | PASS (bubble→prose 19.33/19.0) | N/A | N/A |
| 1 step rows (group, edit) | PASS | PASS (icon 18.33, label 42.33, chevron +12 exact) | PASS | PASS (label h 14 / 11.67 both) | PASS (#A1A1A6, chevron #636366/#616161) | PASS (13×13, 12.33×12.33, chevron 4.67×7.33 both) | PASS (row→prose 36.33/36.67, row→pills 32/32) | PASS collapsed | N/A |
| 1 pills | PASS | PASS (16→, gap 8 both; pill 2 icon +15.33/+15.0) | PASS | PASS (text rows +30.33) | PASS (#F2F2F7, #30D158, #8E8E93; fill #1C1C1E/#1A1A1C) | PASS (ring 19.33 both, file 9.33×13 both) | PASS (36 vs 36.67, Obs 3) | PASS | PASS (clip accepted) |
| 1 composer, chip, Stop | PASS | PASS (12–378/390 × +30, 96 tall both) | PASS | PASS | PASS (placeholder #8E8E93/#8C8C8F, chip #D1D1D6/#D0D0D2, Stop #F2F2F7/#F0F0F4) | PASS (clip 17×18.33, chevron 5.67×3.67, square 11×11 both) | PASS (chip 28 tall, Stop 34) | PASS (working → Stop) | PASS |
| 2 group header (open) | PASS | PASS (icon 18.33, label 42.33, meta right +11.67, chevron +12) | PASS | PASS (meta h 11 both) | PASS (#8E8E93/#8C8C8C) | PASS (chevron down 7.33×4.67 both) | PASS (header→row 1: 31.0/30.67) | PASS expanded | N/A |
| 2 rail + call rows | PASS | PASS (rail x 24.00 both; icon 41.0/41.33; verb 62.67/63.0; arg Obs 5; duration +11.67; chevron +12) | PASS | PASS (verb h 10.33, row pitch 28.67 both) | PASS (rail 56/54, verb #D1D1D6, arg #A1A1A6, duration #8E8E93, chevron #636366) | PASS (row 2 chevron down 6×4 both) | PASS | PASS (9 rows = sample) | N/A |
| 2 call card | PASS | PASS (x 39.33 both, right +12.33; every internal row ±1 from the card top) | PASS (word wrap accepted) | PASS (label cols identical; value h 11 both, Obs 4; block pitch 16 both) | PASS (fill, labels #8E8E93, value #F2F2F7, last line #636366/#656565, link #419CFF/#3F99FA) | N/A | PASS (block 112 both, card 236/237) | PASS open | N/A |
| 2 bottom (fade, pills, composer) | PASS | PASS (+30) | PASS | PASS | PASS | PASS (follows `s2-view` icons) | PASS | PASS (bottom fade present) | PASS |
| 3 single step row | PASS | PASS (icon 18, verb 42.33, arg 77/76.33, duration +11.67, chevron +12) | PASS | PASS (mono arg h 11.33 both) | PASS | PASS (terminal 13×11.67 both, chevron down) | PASS (row→card 11.0 both) | PASS open | N/A |
| 3 command card | PASS | PASS (x 16/15.67, right +12.33; every row +28…+29) | PASS | PASS | PASS (value #F2F2F7, cwd #8E8E93, "42 pass" #2FD158/#30CD59, link) | PASS (✓ glyph from font fallback, Obs 7) | PASS (block 144 both, card 271.33/272.33) | PASS | N/A |
| 4 header (1 queued) | PASS | PASS | PASS | PASS | PASS (title 253; "1 queued" #A1A1A6/#A1A1A4) | N/A | PASS | PASS | PASS |
| 4 transcript step rows | PASS | PASS (x identical) | PASS | PASS | PASS | PASS | **FAIL D1** (pitch 36.0 vs 34.0) | PASS | N/A |
| 4 strip (menu open) | PASS | PASS (12–378/390 × +30, 32 tall both) | PASS | PASS (text h 12 both) | PASS (fill #212123/#202022, text #A0A0A5/#A0A0A4, more #7E7E83/#818184) | PASS (spinner 11.67, more 13.33 both) | PASS (strip→composer 6/6) | PASS | N/A |
| 4 strip at rest / dismissed | PASS | PASS | PASS | PASS | PASS (#18181A against the board source's α 0.22 ≈ #1A1A1C, Obs 8) | PASS | PASS | PASS (outside tap restores rest) | N/A |
| 4 menu | PASS | PASS (140–390 = +12, width 250 both; inner rows +30; separators +30) | PASS | PASS (17/13 pt, h 13/12 both) | PASS (labels 253; subtitle #A1A1A6/#A0A0A4; Remove #FF453B/#FD433A; fill #2B2B2C/#29292C) | PASS (arrow 12, pencil 12.33, trash 11.67/11.33; +12) | PASS (menu→strip 10/10) | PASS (opens at row) | N/A |
| 4 composer | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 5 header + offline status | PASS | PASS (status w 142.33/142.67) | PASS | PASS | PASS (title 253; #FF9F0B/#FB9E0A; no glow both) | N/A | PASS | PASS | PASS |
| 5 bubble + prose | PASS | PASS (right +12; +29.67) | PASS | PASS | PASS | N/A | PASS | N/A | N/A |
| 5 strip "Not sent" | PASS | PASS (icon 25, text 47.33, "Not sent" +12 exact) | PASS | PASS | PASS (red icon #FF453B/#FD4337, "Not sent" #D95851/#DB5957) | PASS (13/12.67) | PASS | PASS | N/A |
| 5 menu Retry/Edit/Delete | PASS | PASS (160–390, width 230 both; inner rows +30) | PASS | PASS | PASS (labels 250–253, Delete red) | PASS (retry icon 13×13 both) | PASS | PASS | N/A |
| 5 composer (offline) | PASS | PASS | PASS (placeholder) | PASS | PASS (send #3A3A3B/#38383B, arrow #8E8E93/#8F8F91) | PASS (arrow 11.33 both) | PASS | PASS (send disabled) | PASS |
| 6q header + transcript | PASS | PASS (gaps per A/B, Obs 6) | PASS | PASS | PASS (C) | PASS | PASS | N/A | PASS |
| 6q panel head + Dismiss | PASS | PASS (dot ring 14, core 8; label 41/40.67; Dismiss text +13.33) | PASS (accepted) | PASS (label h 9 both) | PASS (#FFB33F/#FBB03E, Dismiss #D1D1D6/#D0D0D2, fill #2C2C2F/#2A2A2D) | N/A | PASS (panel top→head 16.33/16.0) | PASS | N/A |
| 6q title/sub | PASS | PASS (1 title line vs 2 = text width; panel −24.33 vs −25) | PASS | PASS (title h 19 per line; sub pitch 20 both) | PASS (title 253; sub #D1D1D6/#D0D0D2) | N/A | PASS (title line→sub 27.67/28.33) | N/A | N/A |
| 6q options | PASS | PASS (48 tall, gap 8, 24.33–365.67 vs 24–378) | PASS | PASS (number 47.67/47.33, label 75/74.67) | PASS (labels 253, number #D1D1D6/#CDCDD0, fill) | N/A | PASS (sub→option 16.33/17.33) | PASS | N/A |
| 6q free-text field | PASS | PASS (44.67 at 3x vs 46, Obs 3) | PASS | PASS | PASS (placeholder #8E8E93/#8F8F91, send #48484A/#464649) | PASS (arrow 10×10 both) | PASS (field→panel bottom 26.33/26.0) | PASS | PASS (composer and pills hidden) |
| 6p permission panel | PASS | PASS (every row +30…+31; buttons 24–191/199–365.67 vs 24–197.33/205.33–377.67) | PASS | PASS | PASS (title 253, command 239, Deny 240, Allow label 250–253, cwd, link) | N/A | PASS (command box 38 both, buttons 48 both; panel 291/289.67, Obs 3) | PASS | PASS |
| 6l plan panel | PASS | PASS (every row +30…+31) | PASS | PASS (list pitch 25 both) | PASS (title 253, list 240, Keep planning 240, link) | N/A | PASS (list box 91 both, buttons 48 both) | PASS | PASS |
| 7 header + transcript | PASS | PASS (step glyph from data, Obs 9) | PASS (sample) | PASS | PASS | PASS (Obs 9) | PASS (B) | N/A | PASS |
| 7 panel head | PASS | PASS (panel 327.67/328; head +29.33) | PASS | PASS (title h 19 both) | PASS (title 253, label #FFB33F/#FAB03F, sub #D1D1D6/#D0D0D2) | N/A | PASS | PASS (no Dismiss) | N/A |
| 7 host row | PASS | PASS (row 59.67 both; tile 32×32 both; name 83/82.67; sub −1.0, Obs 3) | PASS | PASS (name h 15 both, sub h 12 both) | PASS (name 253, sub #A1A1A6/#A0A0A3, tile #3A3A3C/#38383B, G #F2F2F7/#F0F0F3) | PASS | PASS | N/A | N/A |
| 7 button + footnote | PASS | PASS (button 50 tall both) | PASS | PASS (footnote pitch 18/18.33) | PASS (#096EE0/#066CDE, label 252–253, footnote #8E8E93/#8C8C8F) | PASS (key 13×13 both) | PASS (button→footnote 18.0/18.33; round-12 delta fixed) | N/A | PASS |

## Observations within tolerance, or not deltas

1. **Header sits 2.0 pt lower** in every frame. This is the system bar and is accepted. Status-line centres sit about 2 pt left of the screen centre on both board and app, because of the dot glow.
2. **Board 1, prose line 1** is 1.0 pt higher than the bottom-anchor expectation: 510.33 vs 511.33.
3. **Small size or offset differences, each ≤1.5 pt:**
   - Pill height: 36 / 36.67 at 3x.
   - Call card: +1.0 tall on boards 2 and 3.
   - Question field: 46 vs 44.67 at 3x (+1.33).
   - Question sub → first option: +1.0.
   - Permission and plan panels are 1.33 shorter: top +31.33 vs bottom +30.
   - Sign-in panel: sub → host row 15.67 / 14.67 (−1.0). Footnote → panel bottom 28.33 / 29.33 (+1.0). Measured from the panel top, the host row and button sit 1.33 higher.
4. **Call-card value, line 2** sits 1.0 lower: line pitch 17.33 / 18.0.
5. **Group-row mono argument** starts 1.33 pt left: 96.67 / 95.33. SF Mono advance is about 3% wider; this is text width.
6. **Question and sign-in transcript gaps:**
   - Question: bubble → step 15.0 / 16.33; step → prose 18.33 / 22.67. That is +4.33, close to the accepted A+B of +4.
   - Sign-in: bubble → step-row centre 24.0 / 23.5; step-row centre → prose 27.33 / 29.83 (+2.5, accepted B ≈ +2).
7. **Output ✓ glyph (board 3):** it is the same character (U+2713) in the sample output text, drawn through each platform's font fallback. Board 5.33×5.67, app 7×5.33. Its arms are more symmetric in the app. This is a text glyph inside sample data, not an icon; the difference is ≤1.7 pt. Crop: `crops-extra/b3-check-glyph-*`.
8. **Strip resting fill:** board pixels show only the menu-open state, which matches (#212123/#202022). The resting state matches the board source's α 0.22 (≈ #1A1A1C) with app #18181A.
9. **Sign-in step row:** the board draws a window glyph with "Opened search.google.com in Chrome". The app draws a terminal glyph with `Ran open -a "Google Chrome" https:/… 0.9s`, which follows the fixture's terminal step. This is accepted.
10. **Video colour shifts** are 2–5 levels, for example #1C1C1E vs #1A1A1C, and #A1A1A6 vs #A0A0A0. Hairlines are one device pixel on both sides, and the app's are softened by h264.

## Whole-screen and interaction checks

- **Expand a group:** tapping "Read 6 files, ran 3 commands" opens 9 rows under a rail, and the header chevron turns down (g1). The board shows 6 rows, which is sample data.
- **Open a call:** tapping row 2 opens the card inline, and the row chevron turns down. The transcript stays bottom-anchored, so the group header scrolled under the bar (g2). A slow swipe reveals it (g3). The board does not specify scroll behaviour after expanding, so this is not judged.
- **Single call:** opens straight to its card (s1).
- **Strip menu:**
  - The queued and failed menus open anchored 10 pt above the strip on both board and app, and the strip brightens while the menu is open.
  - A tap outside removes the menu (the menu area returns to black) and restores the resting fill. q-dismissed and q-closed have identical row profiles.
- **Needs-input panels** replace the composer and hide the pills on all four kinds.
- **Bottom scroll-edge fade** is present in the app: prose under the pills fades in g3.
- **Top scroll edge:** in s1, content under the bar is clipped at about 115 pt and fades over 115→128 pt. The board gradient runs black→transparent over 89→124 pt. No board pictures content under the header, so this is not judged; see coverage gaps.

## Coverage gaps

- Motion is not verified: spinner rotation, expand/collapse and menu animations.
- Real-touch gestures are not verified; all taps were synthetic.
- The system model-chip menu is out of scope.
- Top scroll-edge treatment with content under the header is not pictured by any board.
- The single-call **Edited** row on board 3 ("Edited ios/LFG/SessionStore.swift 0.1s", with a mono path) is not produced by any fixture, so its style is unverified. The fixture has a group "Edited 2 files" instead.
- Board 3's card → following step row gap is not exercised.
- Horizontal clipping of long code lines in the card block is not exercised; the sample lines are shorter.
- The strip resting state is checked against board source values only, not board pixels.
- Light mode is out of scope.

## Timing

| Phase | Time (HKT) |
|---|---|
| Preparation (scope, server, build identity, round-12 locator) | 03:07–03:08 |
| App capture (14 frames, all states) | 03:08–03:15 |
| Design capture (9 boards × 5 tiles, DOM dumps, stitching) | 03:15–03:41 |
| Comparison (pixel queries, crops, review sheets) | 03:41–04:05 |
| Report | 04:05–04:12 |

Tool notes:
- One `navigate` call failed with "Browser extension is not connected". That made the next DOM dump read the permission page under the name b6l. I re-navigated and re-dumped; `dom-b6l.txt` now holds the plan page, and its header line confirms it.
- One page-targeting error was retried once and succeeded.
- The worktree hook rejects compound shell commands, so the helpers are `measure/m.sh` and `measure/x.sh`.
- Keep-alive recordings ran at 03:22, 03:29, 03:34, 03:41, 03:58 and 04:04. The gap from 03:41 to 03:58 was longer than the requested 7 minutes, but the simulator stayed booted.

## Files

- Paired native crops, index and review sheets: `crops/` (34 pairs) and `crops-extra/` (D1 and the ✓ glyph).
- Pair manifests: `pairs.json` and `pairs-extra.json`.
- Native glyph side-by-side: `crops-check-glyph.png`.
- Board renders: `design/*-3x.png`, with tiles in `design/tiles/`. DOM dumps: `design/dom-*.txt`.
- App frames and recordings: `app/`.
- Measurement scripts, queries and outputs: `measure/` and `measure/q/`.
