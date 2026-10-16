# Claude Design Verifier · sessions-redesign-s2 · phase 2 view · round 7

**Verdict: FAIL on both boards, for one shared 1 pt delta (D1, the composer).** The two parts that changed this round, the strip row's ⋯ mark and the menu card, match both boards on every measured value. The strip and card shadow now match the boards within video tolerance. Round 6's D1 (shadow too dark) is fixed.

- Board 4 (`s2-queued`): **FAIL** (D1 only).
- Board 5 (`s2-queued-failed`): **FAIL** (D1 only).
- If the owner accepts a 1 pt composer height tolerance (round 6 recorded the same "95 vs 96" and passed it), both boards pass.

## Scope and provenance

- Boards: `s2-queued.dc.html` (board 4) and `s2-queued-failed.dc.html` (board 5) only. Whole screen judged for each.
- Design source: `http://127.0.0.1:8793/` (python static server, pid 494). Source sha256 prefixes: `s2-queued` cefcef79392790b7, `s2-queued-failed` 6e981111f3b1948b, `support.js` 3f160299989dc595.
- Design render: my own new claude-in-chrome tab (id 1045567100). Viewport 1135×1266, DPR 1, `document.fonts.status = loaded`, system fonts. 1x zoom capture [0,0,390,844] → `design/b4-full-1x.png`, `design/b5-full-1x.png`. 3x render: `zoom: 3` on the root element, captured in 1:1 tiles (6 per board, named by their 3x origin) and stitched → `design/b4-full-3x.png`, `design/b5-full-3x.png` (1170×2532, no unfilled pixels). DOM values came from one rendered-root query per board (plus a follow-up for truncated output).
- App: worktree `sessions-redesign-s2`, HEAD 8b0be91 plus the dirty tree. App binary `LFG.debug.dylib` built 21:49:11, after the newest Swift source (21:49:03). sha256 prefix bbdbfe372bc23567. The same binary was used for both launches.
- Simulator: iPhone 17 Pro, C47EB72F-A352-44C9-8A80-9F13D33780AD, 402×874 pt at 3x.
- Routes: `flowdeck run … --launch-env LFG_S2_VIEW_FIXTURE=queued|failed`, wait for the session, then one tap at (200, 728) pt on the strip.
- Capture: `flowdeck ui simulator record --codec h264` and the last frame through ffmpeg, 1206×2622 (3 px/pt). The known screenshot failure was not retried. One HEVC recording (`app/f-menu-hevc.*`) was made as an independent second encoding for the ⋯ dots.

| Frame | State |
|---|---|
| `app/q-closed.png` | queued, strip closed |
| `app/q-menu.png` | queued, strip menu open (board 4) |
| `app/f-closed.png` | failed, strip closed |
| `app/f-menu.png`, `f-menu-2/3/4.png`, `f-menu-hevc.png` | failed, strip menu open (board 5); repeats taken as simulator keep-alives |
| `app/f-dismissed.png` | failed, after one tap on empty transcript at (200, 300) |

Coordinates below are pt (3x px ÷ 3). App y values sit +30 pt lower than the boards because the app screen is 30 pt taller and the bottom stack is bottom-anchored. App x values for right-anchored parts sit +12 pt right because the screen is 12 pt wider.

## Accepted exceptions applied

System glass back/tools buttons (size, material, chevron glyph). Fixture text, timers, extra transcript turns on board 4, and the untruncated strip message on board 5. "Medium" not "Med". Model chip with a chevron (board `s2-view`). Single-call step in mono with "1.8s" (board `s2-tools-single`). Files/Terminal pills on board 4, none on board 5 (offline). The card's faint translucency. Colour within a few levels. SF Pro text width.

One more board disagreement applies: boards 4, 5 and `s2-view` use a 14 pt transcript gap, but `s2-tools-single` uses 12 pt. The app uses 12 pt (measured: Edited→Ran icon pitch 34.0 = 22 + 12; bubble→prose box gap 12.0). Under the "either board passes" rule this is not a delta. It explains round 6's O1 and O2.

## Matrix

Columns: 1 internal consistency, 2 structure/layout, 3 copy, 4 typography, 5 colour, 6 glyphs, 7 spacing/shape, 8 states, 9 navigation chrome.

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| 4 · header + status | PASS | PASS | PASS | PASS (title cap 13.3 = 13.3; status 13.0 = 13.0) | PASS (green 48,208,88 vs 47,209,88) | PASS (system chevron accepted) | PASS (title centred 201.3 on 201 vs 195.3 on 195; back x 16 = 16) | n/a | PASS (glass accepted) |
| 4 · menu card | PASS (dividers full width; no seams) | PASS (3 items, right inset 12 = 12, width 250 = 250, 8 = 8 above strip) | PASS | PASS (see T1) | PASS (card 41,41,44 vs 43,43,44; divider 70 vs 72; red 254,67,57 vs 255,69,59; subtitle 161,161,164 vs 161,161,166) | PASS (see G1) | PASS (height 141.7 vs 141; items 56/42.3/42.3 vs 55.7/42.3/42.3; corner insets at 8 px and 24 px below the top 21/7 = 21/7) | PASS (opens on tap; closes on outside tap, shown on board 5) | n/a |
| 4 · menu shadow | PASS | PASS | n/a | n/a | PASS within tolerance (see S1) | n/a | PASS | PASS | n/a |
| 4 · strip, open | PASS (vertical shade ramp matches the board's, see S1) | PASS (spinner, text, ⋯ in order) | PASS (truncation is width) | PASS (text ink 12.0 = 12.0, +11.0 = +11.0 from strip top) | PASS (fill 46,46,49 vs 49,49,53; text 154 vs 155) | PASS (⋯ ring 13.3 = 13.3; spinner 11.0 vs 11.3; O1) | PASS (32 = 32; inset 12 = 12; text x 45.7 = 45.7; ⋯ right inset 11.3 = 11.3; 6 = 6 above composer) | PASS (open fill 46 vs closed 23; board 0.40 vs 0.22) | n/a |
| 4 · composer | PASS | **FAIL D1** (95 vs 96 tall) | PASS | PASS (placeholder cap 13.0 = 13.0) | PASS (fill 26,26,28 vs 28,28,30) | PASS (paperclip 17.0×18.3 = 17.0×18.3; stop square 11 = 11) | PASS except D1 (chip x 58.0 vs 58.3, h 28 = 28; Stop 34 = 34, right inset 10.0 vs 10.3; 28 = 28 from bottom) | PASS (Stop shown while working) | PASS |
| 4 · transcript | PASS | PASS (pills and extra turns accepted) | PASS (data) | PASS | PASS | PASS (step icons 12.3 = 12.3, 13.0×11.7 = 13.0×11.7) | PASS (12 pt gap per `s2-tools-single`) | n/a | PASS |
| 5 · header + status | PASS | PASS | PASS ("Air offline · 2m · inbox") | PASS (cap 13.3 = 13.3; status 9.7 = 9.7) | PASS (orange 253,157,10 vs 255,159,11) | PASS | PASS (status width 142.3 = 142.3; centred) | PASS (offline) | PASS (glass accepted) |
| 5 · menu card | PASS | PASS (width 230 = 230, inset 12 = 12, 8 = 8 above strip) | PASS (Retry / Edit / Delete) | PASS (see T1) | PASS (card over bubble 41,44,47 vs 44,47,53) | PASS (see G1) | PASS (height 127.7 = 127.7; items 42.3/42.3/42.3) | PASS | n/a |
| 5 · menu shadow | PASS | PASS | n/a | n/a | PASS within tolerance (see S1) | n/a | PASS | PASS | n/a |
| 5 · strip, open | PASS | PASS (alert, text, tag, ⋯) | PASS ("Not sent"; full text is width) | PASS (text 12.0 = 12.0; tag cap 9.0 = 9.0, weight matches) | PASS (alert fill 247–255,68,60 vs 255,69,59; tag 203–230,84–90 vs 206–217,83–88) | PASS (alert 12.7 vs 13.0; ⋯ 13.3 = 13.3; O1) | PASS (text x 47.3 = 47.3; tag→⋯ gap 10.0 vs 9.6) | PASS (fill 45,45,47 open vs 25 closed) | n/a |
| 5 · composer | PASS | **FAIL D1** | PASS ("Message · sends when Air is back"; "Medium" accepted) | PASS (placeholder ink 16.0 = 16.0) | PASS (disabled send arrow 142,142,145 vs 142,142,147) | PASS (arrow 11.3 = 11.3) | PASS except D1 (placeholder +16.3 vs +17.0, board 4 +15.7) | PASS (disabled send) | PASS |
| 5 · transcript | PASS | PASS | PASS (data; wrap is width) | PASS (prose line tops 246.0/222.0/198.0 vs 246.7/222.7/198.7 from bottom) | PASS (bubble 6,108,222 vs 9,110,223) | n/a | PASS (12 pt gap per `s2-tools-single`) | n/a | PASS |
| Whole screen, both | PASS: the card sits above transcript and pills in z-order; the shadow does not reach the composer; no shared chrome leaks; outside tap closes the menu and restores the closed strip fill. | | | | | | | | |

## Findings

### D1. Composer is 1 pt short, and the strip and card ride 1 pt low (boards 4 and 5)

- **Board 4 / app: composer height.** Board 96.0 pt (3x rows 2160–2447) / app 95.0 pt (rows 2253–2537). Measured at three columns (x = 200, 330/342, 233 pt) and in the closed and open frames. All eight session-view boards draw this composer at 96 pt.
- **Board 5 / app: composer height.** Board 96.0 / app 95.0 (same rows).
- Consequence on both boards: the composer's bottom stays 28 = 28 pt from the screen bottom, so its top moves down 1 pt. The strip (6 = 6 above the composer) and the card (8 = 8 above the strip) follow. Strip bottom from screen bottom: board 130 / app 129. Card bottom: board 170 / app 169.
- Crops: `crops/b4-composer-{design,app}.png`, `crops/b5-composer-{design,app}.png`.
- Not new: round 6 recorded "95 vs 96" and passed it. I count it because the boards agree on 96 and the 3 px difference is far above the measurement limit.

### Checks that pass (summarised)

- **T1. Card type.** "Send now": cap 13.0 = 13.0, x +17.0 = +17.0 from card, top +13.7 = +13.7. Subtitle: 12.0 = 12.0, +33.0 = +33.0. "Edit": +71.4 vs +70.7 (item 1 is 0.3 pt taller). "Remove"/"Delete": +114.7 vs +114.0. "Retry": +15.0 vs +15.4.
- **G1. Card icons.** Arrow 12.0×12.0 = 12.0×12.0, right inset 19.0 = 19.0. Pencil 12.3×12.3 = 12.3×12.3. Trash 11.3×13.3 vs 11.7×13.0. Retry 13.0×13.0 = 13.0×13.0. Shapes match at 4× nearest-neighbour (`glyphs-b4.png`, `glyphs-b5.png`).
- **S1. Menu shadow** (round 6 D1, now fixed).
  - Strip under the card, top→bottom: board 32→46 / app 31→44.
  - Strip row 6.7 pt into the strip, beside the card: board 49→37 / app 48→34. The ramp starts 17 pt farther left in the app.
  - Board 5 bubble beside the card (blue channel, base 224 vs 222): at −2 pt, board 183 / app 179; at −9 pt, 196 / 188; at −15 pt, 204 / 201; at −22 pt, 212 / 210.
  - The app's shadow is 2–8 levels deeper at matched offsets. That is within the accepted video tolerance, not twice as dark as in round 6.

### Observation (not counted)

- **O1. ⋯ dots touch slightly in the app (both boards).**
  - Ring 13.3 = 13.3 and dot span 8.0 = 8.0 pt (24 px each). Dot pitch 2.67 = 2.67.
  - Dot height: board 7.1 px / app 7.6 px (edge pixels 87 vs 107–110).
  - The dip between dots on the centre row: board 87–93 / app 113–124 (h264 and HEVC agree).
  - So the app dots look about 0.15 pt larger, and the 0.27 pt gaps nearly close. This is about half a device pixel on each edge. It fits a gamma difference between CoreGraphics and Skia anti-aliasing at the same 3x scale, and lossy frames cannot separate the two. I did not count it.
  - See `glyphs-b4.png`, row 1.

## Data exclusions

Timers ("4m 19s", "2m"), the extra turns on board 4 (bubble, "I'll trace…", "Read 6 files…"), the untruncated strip text on board 5, transcript wrapping caused by the 12 pt wider screen and narrower SF Pro (board 5 wraps "on /" + "download."), and the strip spinner's arc angle (the app spins; the board is static).

## Coverage gaps

- Board 4's closed strip was not rendered from the board this round. The app's closed fill (23,23,25) was checked against the board source value (`rowBg` 0.22). That gives about 26,26,28 over black; round 6's render measured #18181C.
- Exact colours come from h264/HEVC frames only. A lossless screenshot is a known failure on this simulator.
- No scrolled content sits behind the header or the bottom fade in these states, so the top and bottom gradients were not exercised (N/A for these boards).

## Sources and crops

- Paired crops (native 3x) and review sheets: `crops/` (index with hashes: `crops/index.json`; manifest: `pairs.json`).
- Glyph sheets: `glyphs-b4.png`, `glyphs-b5.png` (4× nearest-neighbour, viewing only).
- Measurement scripts (scratchpad): `verifier_r7_jobs.py` (colour runs), `verifier_r7_bbox.py` (ink boxes), `verifier_r7_bands.py` (text lines), with job files `verifier_r7_*.txt`.

## Timing (observed wall clock)

| Phase | Start–end | Notes |
|---|---|---|
| Preparation | 21:49:50–21:49:57 | dirs, revision, server check |
| App capture | 21:49:57–21:51:45 | 2 launches (no rebuild needed), 2 taps, 4 recordings |
| Design capture | 21:52–22:01:17 | 1x captures, DOM queries, 13 tiles, stitching |
| Comparison | 22:01–22:17 | scans, ink boxes, crops, HEVC cross-check, dismissal tap |
| Report | 22:17– | this file |

Tool issues, recorded once:
1. The worktree hook refused compound commands that named git or ran `uv` with a shell variable. I split them into literal commands.
2. The Chrome zoom capture downsamples regions above about 1.2 MP, and the saved file follows the `scale` argument. I used 1135×1000 tiles at scale 1.
3. With `overflow: hidden`, horizontal scrolling did not move the page. For the right strip I used `body.style.marginLeft = -12px`.
4. My stitch helper overwrote an existing `stitch.py` in the shared scratchpad, and that file's original content is lost.
5. The simulator stayed booted throughout. Recordings were taken at 21:50, 21:51, 21:57, 22:01, 22:11, 22:13 and 22:15.
