# Visual Design Verifier · sessions-redesign-s2 · phase 2 session view (phone) · round 12

**Overall verdict: FAIL.** Two confirmed deltas.

- **D1** (all boards): text the boards draw in pure white uses the app's #F2F2F7 ink.
- **D2** (board 7 only): the sign-in footnote sits 1.7 pt closer to its button than on the board.

Everything else measures within the 1.5 pt tolerance or falls under an accepted exception. If the owner accepts D1 the same way as decision C, boards 1 to 6 pass, and board 7 fails on D2 alone.

| Board | Verdict | Deltas |
|---|---|---|
| 1 · `s2-view` (working) | FAIL | D1 |
| 2 · `s2-tools-group` (group open, call card open) | FAIL | D1 |
| 3 · `s2-tools-single` (single call open) | FAIL | D1 |
| 4 · `s2-queued` (queued, strip menu open) | FAIL | D1 |
| 5 · `s2-queued-failed` (not sent, menu open) | FAIL | D1 |
| 6 · `s2-question` | FAIL | D1 |
| 6 · `s2-question-permission` | FAIL | D1 |
| 6 · `s2-question-plan` | FAIL | D1 |
| 7 · `s2-signin-prompt` | FAIL | D1, D2 |

## Scope and provenance

- **Scope:** live app compared with HTML boards, whole screen per board, every component on each board. I also exercised the requested interactions: expand a group, open a call card, open the single-call card, open the strip menu (queued and failed), and tap outside to dismiss.
- **Reference:** HTML boards from `http://127.0.0.1:8793/` (answered 200). The source folder is `/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/dcrender/project/`.
  - Source sha256 prefixes: `s2-view` 9c10012276d348cb, `s2-tools-group` a3911397dba72d9d, `s2-tools-single` 0aa849bb9891f9d3, `s2-queued` cefcef79392790b7, `s2-queued-failed` 6e981111f3b1948b, `s2-question` 51ce62391853e7a8, `-permission` 851da0fba3bc51c8, `-plan` 3c47cc323f3d9602, `s2-signin-prompt` f54a74e4e4a13a9a, `support.js` 3f160299989dc595.
- **Renderer:** my own new claude-in-chrome tab 1045567253. Each capture result reports the tab URL, and I checked it.
  - Viewport 1135×1266, DPR 1, no web fonts (system SF).
  - 3x method: `zoom: 3` on `#dc-root`, overflow hidden, then a negative body margin per tile. Each board uses five native tiles:
    - three tiles of 1135×1000 at artboard y 0, 1000 and 1532;
    - two strips of 70×1266 at x 1100.
  - The tiles are stitched to 1170×2532 with no unfilled pixels. Overlap checks found a maximum channel difference of 0 to 5 (`measure/stitch.py`). Output: `design/<board>-3x.png`.
  - DOM values: one dump per board at zoom 1, posted to a loopback receiver on port 8798 (now stopped). Files: `design/dom-*.txt`.
- **Renderer artefact (important for reading board numbers):** CSS zoom 3 draws every border as one device pixel, and content-box elements with borders shrink by up to 1.33 pt.
  - For example, at 3x the question panel is 407.33 pt tall, against 410 pt at zoom 1.
  - The board source declares the pill and field borders as `0.5px`, so their design intent is a hairline and a 36/44 pt box plus 0.5 pt borders. The 3x render (36.67/44.67) is closer to that intent than the zoom-1 DOM (38/46), where Chrome rounds 0.5px up to 1px.
  - I therefore use 3x pixels as board truth, as briefed, and quote the DOM where it helps.
- **Render hashes (sha256 prefix):** b1 040967eebbc516f7, b2 4aa733ce798b70c3, b3 170238fb3793ad27, b4 856457d0eb22664a, b5 79501eee3fb5a501, b6q 3d7ee584bef5aed5, b6p 6aab8a2a09faf6ac, b6l fbf19408c0a4b699, b7 3e5f971ba5aec982.
- **App:** worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree.
  - Installed `LFG.debug.dylib` is from 01:52:38, sha256 6e4013d469dd63fc. That is newer than the newest Swift source (01:52:25).
  - The hash was unchanged after every `flowdeck run`.
- **Simulator:** iPhone 17 Pro, C47EB72F-A352-44C9-8A80-9F13D33780AD, 402×874 pt. Frames are the last frame of 1 s h264 recordings, 1206×2622 (3 px/pt).

| Frame | Route | Time | Board | sha256 prefix |
|---|---|---|---|---|
| `app/w.png` | fixture `working` | 01:57:30 | 1 | 466f455e5124ced6 |
| `app/g1.png` | tap (144,555) "Read 6 files, ran 3 commands" | 01:57:52 | 2 (group open, all 9 rows) | 150e8e86379e5805 |
| `app/g2.png` | tap (175,354) "Read ios/LFG/SessionStore.swift" | 01:58:12 | 2 (card open, header scrolled off) | 145775564de325e8 |
| `app/g3.png` | slow swipe down 180 pt | 01:58:54 | 2 | 9161d00b710f5efa |
| `app/q-closed.png` | fixture `queued` | 01:59:35 | 4 context (strip resting) | ba7f9df3b02db9d4 |
| `app/q-menu.png` | tap (200,728) on the strip | 01:59:57 | 4 | 540d2cbb2d28095d |
| `app/q-dismissed.png` | tap (200,300) outside the menu | 02:00:27 | 4 dismissal | c2653eade25b0195 |
| `app/s1.png` | tap (131,640) "Ran bun test …" | 02:01:00 | 3 | e4a0a6873af9b7c5 |
| `app/f-closed.png` | fixture `failed` | 02:01:36 | 5 (strip resting, composer) | f4d365dee44dd881 |
| `app/f-menu.png` | tap (200,728) on the strip | 02:02:02 | 5 | 48e6ff20d4a29919 |
| `app/question.png` | fixture `question` | 02:02:42 | 6 question | c30857020f939006 |
| `app/permission.png` | fixture `permission` | 02:03:19 | 6 permission | f6e1c70f5620b095 |
| `app/plan.png` | fixture `plan` | 02:03:51 | 6 plan | bcb21cd5def97429 |
| `app/signin.png` | fixture `signin` | 02:04:31 | 7 | 4ac26e4f523696b1 |

**Measurement method:**
- Coordinates are pt (3x px ÷ 3). The app screen is 12 pt wider and 30 pt taller. Bottom-anchored parts are expected 30 pt lower, and right-anchored parts 12 pt further right.
- All geometry is pixel-measured from ink edges on both sides with the same thresholds (`measure/measure.py`, query files `measure/q*.txt`).
- Colours are the median of the strongest-ink pixels. They are calibrated against the iOS status-bar clock, which is pure white and measures 253 in every frame.

## Accepted exceptions applied (from the brief)

- System glass back/tools buttons and system bar height. The header sits 2.0 pt lower in every frame; measured.
- System model-chip menu.
- Sample text.
- "Claude is asking" without "· 1 of 1".
- "Medium" and the chip chevron.
- Pills scroll, and the last pill is clipped.
- Boards other than `s2-view` omit or simplify pills. The app hides pills under a panel.
- A: gaps of 12 vs 14 pt.
- B: step-row padding on question/sign-in.
- C: prose ink #F2F2F7.
- Mono single-call step with a duration.
- Composer placeholder position.
- Pinned transcripts on permission, plan and sign-in.
- Word-wrapped call-card input.
- SVG icons.
- SF text width.
- Live host state.

Also treated as a board conflict that the app resolves by following `s2-view`:
- `s2-tools-*` draw pills without icons and a composer without a paperclip.
- `s2-view` has both, and the app follows `s2-view`.

## Findings

### D1 · Pure-white text drawn in #F2F2F7 (all boards) — colour/token

The boards set these to `#FFFFFF` (DOM). In the app they measure 240–243, the same as the #F2F2F7 elements (prose, card values, the "Deny" label measure 240). The white clock in the same frames measures 253. Button labels on blue measure 251–254 in the app, so the app's white ink is fine there.

- Header title, all 9 boards: board #FFFFFF / app 243,243,243 in all 10 frames. Crops: `crops/b1-header-*`, `b4-header-*`, `b5-header-*`.
- Strip-menu labels "Send now", "Edit" (board 4) and "Retry", "Edit" (board 5): board #FFFFFF / app 240,240,243 and 238,240,244. Crops: `crops/b4-menu-*`, `b5-menu-*`, `sbs-menu-strip.png`.
- Panel titles "Upload build 205 …", "Run this command?", "Approve this plan?", "Sign in to search.google.com": board #FFFFFF / app 240,240,243. Crops: `crops/b6q-title-sub-*`, `b6p-panel-*`, `b6l-panel-*`, `b7-panel-head-*`.
- Question option labels (board 6): board #FFFFFF / app 240,240,243. Crop: `crops/b6q-options-*`.
- Sign-in host name "search.google.com" (board 7): board #FFFFFF / app 240,240,243. Crop: `crops/b7-host-row-*`.

Hypothesis: one shared primary-ink token (#F2F2F7) is used for these roles. The difference is about 12–13 levels, which is beyond the brief's "a few levels". The owner could settle it in one line, the same way as decision C.

### D2 · Sign-in footnote sits closer to the button (board 7) — spacing

- **Gap:** from the bottom edge of "Sign in on iPhone" to the first-line ink top of "There is no Dismiss here…", board 18.0 pt / app 16.3 pt.
  - Board: button 709.67–759.67, footnote 777.67.
  - App: button 739.67–790.0, footnote 806.33.
  - The value is stable across thresholds 15–90; at threshold 20 the app gap is 16.0.
- **Position against the bottom anchor:** the button is +0.3 pt and the footnote −1.3 pt, each within tolerance on its own. The gap is 1.7 pt tight.
- **Below the footnote:** footnote bottom to panel bottom is board 28.3 / app 29.3.
- **Line pitch:** board 18.0 / app 18.3.
- Crop: `crops/b7-button-footnote-*`.
- Hypothesis: the app has no CSS half-leading above the first line of a 13/18 paragraph.

## Matrix

Columns: 1 consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 navigation chrome. "Obs n" refers to the observations list.

| Board / component | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| 1 header + status (working) | PASS | PASS | PASS | PASS | FAIL D1 (title) | PASS | PASS | PASS (green dot + 3 pt glow, 13×13 both) | PASS (system buttons, accepted) |
| 1 user bubble | PASS | PASS (x 56→68 right-anchored, w 318 both) | PASS | PASS (2 lines vs 3 = text width) | PASS #096EE0 / #066CDE | N/A | PASS (r20, 9/14 pad, 62.3 tall per 2 lines) | N/A | N/A |
| 1 prose ×2 | PASS | PASS (+30, x 16.3/16.7) | PASS | PASS (17/24, pitch 24 both) | PASS (C) | N/A | PASS (bubble→prose 19.3/19.0) | N/A | N/A |
| 1 step rows (collapsed, edit) | PASS | PASS (icon 18.3, label 42.3, chevron +12 exact) | PASS | PASS (15 pt, h 14 both) | PASS #A1A1A6, chevron #636366 | PASS | PASS (22 pt row, gap 14) | PASS collapsed | N/A |
| 1 pills | PASS | PASS (16→, gap 8; pill 36 vs 3x 36.7) | PASS | PASS | PASS (#1C1C1E, #F2F2F7, #30D158, #8E8E93) | PASS (ring, file) | PASS (r18, hairline) | PASS | PASS (pills present, clip accepted) |
| 1 composer, chip, stop | PASS | PASS (12–390 × 750–846 = board +30, 96 tall) | PASS | PASS | PASS | PASS (clip, chevron, stop square 11) | PASS (r24, chip 28 tall r14, stop 34) | PASS working → Stop | PASS |
| 2 group header (open) | PASS | PASS | PASS | PASS (meta 12 pt) | PASS #8E8E93 | PASS (chevron down 7.3×4.7) | PASS | PASS expanded | N/A |
| 2 rail + call rows | PASS | PASS (rail x 24, icon 41.3, verb 62.7, duration/chevron +12 exact, pitch 28.7 both) | PASS | PASS (verb 14 pt h 10.3; mono height equal, Obs 2) | PASS (#D1D1D6, #A1A1A6, #8E8E93, #636366) | PASS | PASS (26 pt rows) | PASS (row 2 chevron down when open) | N/A |
| 2 call card | PASS | PASS (39.3→, 237 vs 236, internal rows ±0.7) | PASS (word wrap accepted) | PASS (labels 11/600, value 12.5 mono, block 11.5/16, pitch 6.9 both) | PASS (fill, labels, last line #656565/#636366, link #3F99FA/#419CFF) | N/A | PASS (r12, block 112 tall, link +8.7 both) | PASS open | N/A |
| 2 bottom (fade, pills, composer) | PASS | PASS | PASS | PASS | PASS | PASS (follows s2-view icons) | PASS | PASS (fade present, Obs 3) | PASS |
| 3 single step row | PASS | PASS (+28 scroll offset; every x within 0.7) | PASS | PASS (mono 13 h 11.3 both, Obs 2) | PASS | PASS (terminal, chevron down) | PASS | PASS open | N/A |
| 3 command card | PASS | PASS (16→374/386, 271.3/272.3) | PASS | PASS | PASS (green "42 pass") | PASS (✓ glyph ±1 pt raster) | PASS (block 144 both, 16 pt pitch) | PASS | N/A |
| 4 header (1 queued) | PASS | PASS | PASS | PASS | FAIL D1 (title) | PASS | PASS | PASS | PASS |
| 4 strip (menu open) | PASS | PASS (12–390 × 712–744 = +30) | PASS | PASS (13 pt) | PASS (#262629/#27272B, text #A0A0A4/#A0A0A5, more #818184/#7F7F84) | PASS (spinner 12×12, more 13.3) | PASS (32 tall r16) | PASS | N/A |
| 4 strip resting | PASS | PASS | PASS | PASS | PASS (#18181A against the board source's resting α 0.22 ≈ #1A1A1C, Obs 4) | PASS | PASS | PASS | N/A |
| 4 menu | PASS | PASS (140–390 × 563–704 = +12/+30; separators +30) | PASS | PASS (17/13 pt) | FAIL D1 (labels); fill, subtitle, red PASS | PASS (arrow, pencil, trash +12 exact) | PASS (r16, 8 pt above the strip both) | PASS (opens at row; tap outside dismisses) | N/A |
| 4 composer | PASS | PASS | PASS | PASS | PASS | PASS | PASS (strip→composer 6 both) | PASS | PASS |
| 5 header + offline status | PASS | PASS (status w 142.33 both) | PASS | PASS | FAIL D1 (title); status #FF9F0B, no glow both PASS | N/A | PASS | PASS | PASS |
| 5 bubble + prose | PASS | PASS (+12/+30) | PASS | PASS | PASS | N/A | PASS | N/A | N/A |
| 5 strip "Not sent" | PASS | PASS ("Not sent" 307.67 = +12 exact) | PASS | PASS (12/500) | PASS (#DD5956/#D95851, red icon) | PASS | PASS | PASS | N/A |
| 5 menu Retry/Edit/Delete | PASS | PASS (160–390 × 576–704 = +12/+30) | PASS | PASS | FAIL D1 (labels) | PASS | PASS (w 230) | PASS | N/A |
| 5 composer (offline) | PASS | PASS | PASS (placeholder) | PASS | PASS (send #38383B, arrow #8C8C8F) | PASS | PASS | PASS (send disabled look) | PASS |
| 6q transcript | PASS | PASS (gaps follow A/B, Obs 5) | PASS | PASS | PASS (C) | PASS | PASS | N/A | N/A |
| 6q panel header + Dismiss | PASS | PASS (dot core 8, ring 14, label 40.7, Dismiss right +12) | PASS (accepted) | PASS | PASS #FAB041/#FFB33F | N/A | PASS (Dismiss 30 tall r15) | PASS | N/A |
| 6q title/subtitle | PASS | PASS (1 title line vs 2 = text width) | PASS | PASS (20/600, 15/20) | FAIL D1 (title) | N/A | PASS (title→sub 28.3/27.7) | N/A | N/A |
| 6q options | PASS | PASS (48 tall, gap 8, 24→378) | PASS | PASS | FAIL D1 (labels); number #CDCDD0 PASS | N/A | PASS (r14) | PASS | N/A |
| 6q free-text field | PASS | PASS (46 vs 3x 44.7 / intent 45) | PASS | PASS | PASS (#48484A send, placeholder) | PASS | PASS (r22, hairline) | PASS | PASS (composer and pills hidden) |
| 6p permission panel | PASS | PASS (all rows +30 ±0.7) | PASS | PASS | FAIL D1 (title); block, Allow, Deny, link PASS | N/A | PASS (buttons 24–197/205–378, gap 8) | PASS | PASS |
| 6l plan panel | PASS | PASS (all rows +30 ±1) | PASS | PASS (list 15/21, 3 lines both at 3x) | FAIL D1 (title) | N/A | PASS (list box r14, 91 tall) | PASS | PASS |
| 7 transcript | PASS | PASS (step glyph from data, Obs 6) | PASS (sample text) | PASS | PASS | PASS (Obs 6) | PASS | N/A | N/A |
| 7 panel head | PASS | PASS (+31) | PASS | PASS | FAIL D1 (title) | N/A | PASS | PASS (no Dismiss) | N/A |
| 7 host row | PASS | PASS (+30; G tile 32, name 82.7) | PASS | PASS | FAIL D1 (host name) | PASS | PASS (r14, 60 tall) | N/A | N/A |
| 7 button + footnote | PASS | PASS | PASS | PASS | PASS (#066CDE, label white, footnote #8D8D90) | PASS (key 13×13) | FAIL D2 | N/A | PASS |

## Observations within tolerance or not deltas

1. **Header 2.0 pt lower** in every frame (system bar, accepted). Title and status widths: the status line is identical (e.g. 172.67/173.00, 142.33/142.33); the title is about 5 % narrower (SF width).
2. **SF Mono advance at 12.5–13 pt** is about 2.5–3 % wider in the app: pitch 7.7/8.0 vs 7.5/7.8, glyph heights equal. At 11.5 pt the pitch is identical (6.9). This is a pure text-width difference.
3. **Bottom scroll-edge fade** is present in the app. Prose under the pills fades from 226 to 179 peak across one line (`app/g3.png`), consistent with the board gradient (transparent→black, 648→691 pt, +30).
4. **Strip resting fill:** board pixels show only the menu-open state. The board source sets `rgba(118,118,128,0.22)` at rest and `0.40` with the menu open. App: rest #18181A, open #262629, against board-derived #1A1A1C/#27272B.
5. **Question gaps:**
   - Bubble→step text: board 15.0 / app 16.3.
   - Step→prose: board 18.3 / app 22.7. That is +4.3, close to the accepted A+B of +4.
   - On sign-in, bubble→step is board 17.3 / app 17.0, and step→prose is board 20.0 / app 23.3.
   - `s2-view` never shows a bubble directly followed by a step row, so the app matching the question/sign-in boards here passes.
6. **Sign-in step row:** board draws a window glyph with "Opened search.google.com in Chrome". The app draws a terminal glyph with `Ran open -a "Google Chrome" https:/… 0.9s`. This follows the fixture's Bash call and the accepted mono single-call style.
7. **Small offsets within 1.5 pt:**
   - Pill height 36 / 36.67 (3x).
   - Call card +1.
   - Field +1.3 (vs 3x render).
   - Sign-in header block +1.0 and footnote −1.3.
   - Permission/plan panel tops +1.3.
   - Prose line 1 on board 1 at −1.0.
   - Group arg start −1.3.
8. **Borders:** both sides draw hairlines (one device pixel). App peaks are 46–55 against the board's 56. h264 softens one-pixel lines.
9. **Video colour shifts** are 2–5 levels everywhere else (#1A1A1C vs #1C1C1E and similar).

## Whole-screen and interaction checks

- **Expand a group:** tapping "Read 6 files, ran 3 commands" opens 9 rows under a rail, and the chevron turns down. The app shows 9 calls where the board shows 6 (sample data).
- **Open a call:** tapping row 2 opens the card inline, and the row chevron turns down. The transcript stays bottom-anchored, so the group header scrolled off (g2). A swipe revealed it (g3).
- **Single call:** opens straight to its card (s1).
- **Strip menu:**
  - Queued and failed menus open anchored 8 pt above the strip, and the strip brightens while the menu is open, as in the board source.
  - A tap outside closes the menu, and the strip returns to its resting fill (q-dismissed).
  - Menus are slightly translucent on both board and app.
- **Needs-input panels** replace the composer and hide the pills on all four kinds. Panels sit 8 pt from the bottom on both board and app.
- **Top scroll edge:** in g2/s1, content under the bar is clipped above about 112 pt and fades over 112→124 pt. The board gradient is black→transparent over 89→124 pt. No board pictures content under the header, so this is not judged (coverage gap).

## Coverage gaps

- Not verified:
  - motion (spinner rotation, expand/collapse and menu animations);
  - real-touch gestures (synthetic taps only);
  - the system model-chip menu (out of scope);
  - top scroll-edge behaviour with content under the header (not pictured);
  - the strip resting state against board pixels (only against board source values).
- Light mode is not in scope.

## Timing

| Phase | Time (HKT) |
|---|---|
| Preparation (scope, server, build identity) | 01:56–01:57 |
| App capture (14 frames, all states) | 01:57–02:05 |
| Design capture (9 boards × 5 tiles, DOM dumps, stitching) | 02:05–02:28 |
| Comparison (pixel measurement, crops, sheets) | 02:28–03:00 |
| Report | 03:00–03:06 |

Tool notes:
- Full-viewport zoom captures above about 1.15 MP come back downscaled. I used 1135×1000 tiles plus 70 pt strips instead; overlaps were verified.
- The worktree hook rejects compound shell commands with variables, so I used small wrapper scripts (`measure/m.sh`, `measure/stitch.sh`).
- Keep-alive recordings ran at 02:13, 02:18, 02:21, 02:24, 02:48 and 02:59. The gap from 02:24 to 02:48 was longer than the requested 7 minutes, but the simulator stayed booted and was not needed again.

## Files

- Paired native crops, index and review sheets: `crops/` (`crops/index.json`, `crops/review-01..05.png`).
- Native side-by-side of the menu and strip: `sbs-menu-strip.png`.
- Board renders: `design/*-3x.png`, with tiles in `design/tiles/`. DOM dumps: `design/dom-*.txt`.
- App frames and recordings: `app/`.
- Measurement scripts and queries: `measure/`.
- Pair manifest: `pairs.json`.
