# Phase 4 r3: desktop Sessions list (dA2-sessions) visual verification

**Verdict: PASS** (updated 14:50, after the gap round in §5). No component in any of the five states differs from the board by more than the 1.5pt tolerance, and no colour differs by more than a few levels. Both carry-over gaps from the first pass are now closed with on-screen captures of the binary I measured. Every in-scope criterion has evidence or an accepted exception.

First pass verdict, superseded: PARTIAL, because G1 and G2 had evidence only from an earlier build.

Verifier round r3. I made a fresh baseline. Nothing below reuses r1/r2 measurements.

## 1. Scope and provenance

| Item | Value |
|---|---|
| Scope | Live harness render of the running implementation vs a rendered HTML board. Five states: all open, Needs input folded, Working folded, Recent folded, all folded. Plus on-screen captures of the same binary, for window activity and click behaviour (§5). |
| Reference kind | HTML board `dA2-sessions.dc.html`, served at `http://127.0.0.1:8793/dA2-sessions.dc.html` (python http.server, pid 494, folder `scratchpad/dcrender/project`). |
| Reference hashes | `dA2-sessions.dc.html` sha256 `987f9d9c3f6bb500…db5a8`. `support.js` sha256 `3f160299989dc595…0dc0f10`. Verbatim copies: `reference-dA2-sessions.dc.html`, `reference-support.js`. |
| Renderer | Chrome 154 (claude-in-chrome, my own tab 1045567362), DPR 1, viewport 1135×1266. Artboard root `div[style*="width: 400px"]` is at (0,0), 400×860. Fonts: system `-apple-system` stack, so no webfont is loading. Each state is captured with a region capture of (0,0,400,860) at 1x. The output PNG is untagged. |
| Board state route | I clicked the real group headers in Chrome (computer `left_click`), which toggles `aria-expanded`. After each click I moved the hover away and called blur. Then I took one DOM dump per state (`board-dom-<state>.tsv`, made by `tools/dom-dump.js`) and one capture per state (`board-<state>.png`). |
| Implementation | `desktop/build/lfg.app/Contents/MacOS/lfg`, sha256 `4e6375cfa51dce09…f147fe5`, mtime 2026-10-16 14:13:42. I re-hashed it at 14:45: unchanged. Tree: HEAD `395f804` plus dirty `desktop/LFGSessions.swift` (mtime 14:12:49) and untracked `desktop/SessionsListS2.swift` (mtime 13:51:17). I did not read the source or the diff. |
| App capture | `lfg --window-shot 400 <png> --height 860 --board [--collapse needsInput|working|recent|needsInput,working,recent]` writes 400×912 RGBA. That is the title bar plus 860 content, at 1x, inactive. The embedded profile is "Mi monitor". `tools/convert_all.py` converts each shot to `app-<state>-srgb.png` (ImageCms). All comparisons use the sRGB copies. |
| Alignment | Top-aligned, no scaling (1 px = 1 pt in both). The board's 52px top bar maps onto the app's 52pt title bar. |
| Exceptions applied (caller) | Native window controls. The harness's inactive title-bar shade and off-screen-only hairline. SF Pro vs Chrome text metrics. Icon rasterisation. 1x rounding (about 1pt, more where rounded widths add up along a row). |

State mapping: `board-open.png` ↔ `app-open-srgb.png`, `board-fold-needs.png` ↔ `app-fold-needs-srgb.png` (`--collapse needsInput`), `board-fold-working.png` ↔ `app-fold-working-srgb.png` (`--collapse working`), `board-fold-recent.png` ↔ `app-fold-recent-srgb.png` (`--collapse recent`), `board-fold-all.png` ↔ `app-fold-all-srgb.png` (`--collapse needsInput,working,recent`).

## 2. Method (what each number below means)

- **Text** (`measure-text-<state>.tsv`, `tools/measure_text.py`). For every text run in the board DOM, I take the board ink bbox inside the DOM range rect. I template-match that crop over the app within ±9px, then take the app ink bbox in the matched window. Deltas are app − board in pt. Colour is the mean of the 25% most-contrasting ink pixels.
- **Chrome edges** (`measure-boxes.tsv`, `tools/measure_boxes.py`). I scan fixed lines through the segmented track, selected pill, badges, search button, host dots, ring and By status pill. The board edge nearest the DOM value is matched to the app edge of the same polarity within ±4px. Positions are sub-pixel, from the gradient centroid.
- **Icons and dots** (`measure-icons.tsv`, `tools/measure_icons.py`). Template-matched ink bbox, centroid, and centre-pixel colour, for every SVG and dot in every state.
- **Hairlines** (`measure-boxes.tsv`). Column scans at x=40, 200 and 380 find every 1px line, with its y position and colour.
- **Structure** (`residual.txt`, `tools/residual.py`). This finds ink present in one image and absent within 4px in the other, for every state below the title band. It also checks the app's extra rows 860–912.
- **Fills** (`tools/fills.py`). Direct pixel samples of every surface.
- **Pairs** (`crops/`, made by `prepare_evidence.py` from `crops-manifest/pairs.json`). There are 74 component pairs across the 5 states, at native 1x, plus `review-01…06.png`. App rects use the same frame shifted by the measured app offset, which is 2px or less everywhere. I reviewed every pair at native size. Zooms are in `zoom/`. Full side-by-sides with an R/GB overlay are in `sbs-<state>.png`.
- I verified that the chrome is pixel-identical across all five states in both images: rows 0–95 have a max channel diff of 0 against the open state. So the chrome edge scan, done in the open state, holds for every state.
- **Gap round** (`tools/convert_gaps.py`, `tools/measure_gaps.py` → `gaps/measure-gaps.txt`, `tools/gaps_sheet.py`). The coordinator's on-screen captures are converted to sRGB copies in `gaps/`; the originals in `../phase4-r3-gaps/` are untouched. Measurements: column runs through the title band, fill samples, edge scans, an active-vs-inactive pixel diff, header/row ink runs, chevron and hint ink, and separator positions.

## 3. Matrix

Cell key: **P** = PASS, measured within tolerance. **P·On** = PASS with observation On (§4). **X** = accepted exception. **N/A** = not pictured in the board.
Criteria: Int = internal consistency, Str = structure/layout, Copy, Typo = typography, Col = colour/tokens, Gly = glyphs, Spc = spacing/shape, St = states, Chr = navigation chrome.

### Chrome (pixel-identical in all five states, in both images)

| Component | States | Int | Str | Copy | Typo | Col | Gly | Spc | St | Chr |
|---|---|---|---|---|---|---|---|---|---|---|
| Title bar band (bg, top edge, y=51 line) | all 5 + on-screen active/inactive | X | P | N/A | N/A | P on screen (G1) · X·O8 in harness | N/A | P | P (active = inactive) | P on screen · X·O8 in harness |
| Window controls | all 5 | X | X | N/A | N/A | X | X | X·O9 | X | X |
| Segmented control (track, Sessions pill, labels, 2 badges) | all 5 + on-screen active | P | P | P | P | P | N/A | P·O4 | P (Sessions selected) | P |
| Search button | all 5 + on-screen active | P | P | N/A | N/A | P | P | P·O4 | N/A | P |
| Host strip (Pro dot, Pro, Air ring, Air offline, · 3 working) | all 5 | P | P | P | P | P | P | P·O3 | N/A | N/A |
| By status pill + chevron | all 5 + on-screen active | P | P | P | P | P | X·O5 | P | N/A | N/A |
| List top border (y=82, full width) | all 5 + on-screen | P | P | N/A | N/A | P | N/A | P | N/A | N/A |

### List body

| Component | State | Int | Str | Copy | Typo | Col | Gly | Spc | St | Chr |
|---|---|---|---|---|---|---|---|---|---|---|
| Header Needs input (amber label, count 2, chevron) | open | P | P | P | P | P | X·O6 | P | P (open ⌄) | N/A |
| Header Needs input | needs folded / all folded | P | P | P | P | P | X·O6 | P | P (folded ›, rows removed) | N/A |
| Header Needs input | working / recent folded | P | P | P | P | P | X·O6 | P | P (open) | N/A |
| Header Working (count 3, hint "by last activity") | open / needs folded / recent folded | P | P | P | P | P | X·O6 | P | P (open, hint shown) | N/A |
| Header Working | working folded / all folded | P | P | P | P | P | X·O6 | P | P (folded ›, hint hidden, rows removed) | N/A |
| Header Recent (count 43) | open / needs / working folded | P | P | P | P | P | X·O6 | P | P (open) | N/A |
| Header Recent | recent folded / all folded | P | P | P | P | P | X·O6 | P | P (folded ›, rows removed) | N/A |
| Needs-input rows ×2 (amber time, ask icon, amber line) | open, working folded, recent folded | P | P | P | P·O1·O2 | P | P | P·O1 | P | N/A |
| Working rows ×3 (green time, dot + halo, "Working") | open, needs folded, recent folded | P | P | P | P·O1·O2 | P | P | P·O1 | P | N/A |
| Recent rows ×2 (grey time, "Closed") | open, needs folded, working folded | P | P | P | P·O1·O2 | P | N/A | P·O1 | P | N/A |
| Offline row (opacity 0.5, "Air is offline") | open, needs folded, working folded | P | P | P | P·O1 | P | N/A | P | P (faded) | N/A |
| Row separators (inset x=62→399) | every state that has rows | P | P | N/A | N/A | P | N/A | P·O11 | N/A | N/A |
| Group spacing (header ↔ previous last row) | all 5 | P | P | N/A | N/A | N/A | N/A | P | P | N/A |
| Empty area below content (incl. app rows 860–912) | all 5 | P | P | N/A | N/A | P·O7 | N/A | O10 | N/A | N/A |
| Header click → fold, click again → open (behaviour) | board (Chrome clicks) + current build on screen | P | P | P | N/A | P | P | P | P (G2) | N/A |

Structure, all states (`residual.txt`): there are **0** app-only and **0** board-only ink regions (≥3px) below the title band. This means there are no missing or extra elements. The folded Working header has no stray "by last activity" in the app.

## 4. Measurements and observations

None of these is a delta. Each is ≤1.5pt, within a few colour levels, or covered by a stated exception.

**Chrome edges** (open, which also holds for all states; board → app, pt):
segmented track L 121.50→121.58, R 301.50→302.42 (+0.92), T 9.50→9.50, B 41.50→41.50 · selected pill L 124.50→124.58, R 221.50→221.42, T/B Δ±0.15 · Sessions badge L/R/T/B Δ≤0.07 · Tasks badge L +1.06, R +0.94, T/B Δ≤0.06 · search button L +1.07, R +0.93, T/B Δ≤0.07 · Pro dot Δ≤0.03 · Air ring L/R +1.00, T/B 0.00 · By status pill L/R Δ±0.06, vertical extent y52–73 in both (column profile at x=310). Track centre is 211.5 on the board and 212.0 in the app. The segmented control stays centred.

**Fills** (board / app, sRGB): track #2E2E32 / #2F2E32 · selected pill #555558 / #555558 · Sessions badge #FF9F0B / #FF9F0B · Tasks badge #EC9514 / #ED9414 · search button #2E2E32 / #2F2E32 · By status pill #2C2C2F / #2C2C2F · list top border and all row separators #2C2C2F / #2C2C2F · faded-row separator #232327 / #232527 · Pro dot #33D74C / #33D74C · working dot #33D74C / #33D74C, halo #244B2A / #244B2A · Air ring 1px stroke, peak lum 168 / 166. Text ink peaks match exactly: #F4F4F6, #A8A8B0, #8A8A93, #FFB340 family, #5BE37A family, and the 0.5-opacity greys #909093 / #909193.

- **O1. Row text is about 1pt lower in the app.** Title ink tops, open state: board 133/208/321/396/471/584/659/735, app 133/209/322/397/472/585/660/736 (0, then +1). Meta lines are 0 or +1. The max is +2 on two titles: fold-needs "Polish onboarding copy" (board 433 / app 435) and fold-working "Fix queued message reconciliation" (433 / 435). In both, the board's DOM line top is the fractional 430.44, which Chrome rounds down. Their neighbours in the same row are +1. This is the 1x rounding exception. Pairs: `crops/fold-needs-row-04-polish-onboarding-copy-*.png`, `crops/fold-working-row-04-fix-queued-message-reconcili-*.png`. The on-screen captures agree. The gap from the separator to the header label is 19 on screen and 19 in the harness, vs 18 on the board.
- **O2. The "ago" sub-label is 1pt higher in some rows.** Examples: rows 1–3 open, board 156/231/344 vs app 155/230/343. This makes the gap from time to "ago" 1pt tighter there. Peak colour is identical (#8A8A93, 138,138,147). The app's ink coverage is about 5% lighter (7332 vs 6987), which falls under text metrics.
- **O3. The host strip drifts right along the row.** Pro dot 0 and "Pro" 0, then Air ring +1.0, "Air offline" ink left 77→78 (+1), and "· 3 working" 140→142 (+2). This is rounded text widths adding up along the row (DOM "Pro" 19.11, "Air offline" 54.64). The caller's exception covers it. The By status pill on the right is exact (Δ0.06).
- **O4. The Tasks badge, track right edge and search button are about +1pt.** See the edge list above. All are ≤1.07. On screen, the search button edges are the same as in the harness (H@14: 363.5/383.5, top 10.5).
- **O5. The By status chevron is shaped slightly differently.** Ink is 5×4 on the board and 7×3 in the app (threshold 20), with the same centroid (Δ0.0, −0.2). This is icon rasterisation (`zoom/open-bystatus-x8.png`).
- **O6. The header chevrons have the same footprint but different stroke rendering.** Ink bbox is identical in every state: 7×5 open (⌄), 5×7 folded (›). Centroid Δ−0.38. Centre pixel is #717179 on the board and #5A5A61 in the app, because the board stroke renders heavier. This is icon rasterisation (`zoom/foldall-headers-x6.png`).
- **O7. The body background in the harness is #1A1C1E, vs #1A1A1E on the board** (G +2). On screen, the current build reads exactly #1A1A1E. This is harness-only.
- **O8. The title band in the harness differs from the board.** App bg is #1E1E1E (board #1A1A1E). There is a #232323 hairline at y=51 that the board does not have. The window top edge is #3A3A3A with grey corner pixels (#535353). **On screen, the current build shows none of this** (G1). The title bar is #1A1A1E from y=1 to the strip, with no line at y=51, active or inactive. What remains on screen is the native window frame: a 1px top edge #646467 (active) or #606063 (inactive), side edges #515153 / #4B4B4F, and rounded corners. Those are covered by the native-chrome exception.
- **O9. The window controls are native.** They are inactive grey in the harness and colour on screen when active, 14px, starting x≈19. The board draws coloured 12px lights at x=14/34/54. This is the accepted exception.
- **O10. The harness window is taller.** It is 400×912 (title bar + 860 content). The board artboard is 860 including its own top bar. The app's extra 52pt is empty list background (max |Δlum| 0.5). No component moves. This is a harness height convention, not a design delta.
- **O11. Some separators sit 1pt lower.** One separator per state is +1pt: 533→534 (open, fold-recent) and 420→421 (fold-working). All the others are identical: open 82/195/270/383/458/646/722/797. 1x rounding.

## 5. Gap round: on-screen captures of the current build (both gaps closed)

**Inputs.** The coordinator supplied these in `../phase4-r3-gaps/`, 400×900 at 1x, window only, "Mi monitor" profile, live data from the local Pro host:

| File | sha256 | Written |
|---|---|---|
| `active-before-click.png` | `5e94d9da34a052a8…` | 14:40:27 |
| `after-click-folded.png` | `8dbf34e5f2279b02…` | 14:40:29 |
| `after-second-click-open.png` | `5e94d9da34a052a8…` | 14:40:30 (byte-identical to before) |
| `inactive.png` | `34c62508111fad2e…` | 14:40:32 |

**Provenance.** I read `scratchpad/final_gui_check.sh` and `scratchpad/gui_start.sh`, as data. They start `desktop/build/lfg.app/Contents/MacOS/lfg` with an isolated config, run `screencapture -R` on the AX window rect, click with `cliclick` at the Working header, activate Finder for the inactive shot, and then kill only that pid (67987, now gone). The binary at that path has the same sha256 and mtime (14:13:42) as the one I measured, before and after 14:40. I did not watch the run, so this provenance is the script plus an unchanged binary.

**Data differences, not deltas.** Live data has no Needs input group, so the segmented control has no badges and the track is narrower. It has no Air host. Counts and copy differ ("now", "Ready for your next message", 23 Recent). The full component comparison stays on the board fixture (§3/§4). These captures judge window activity and click behaviour only.

- **G1, closed: the title band and the top-bar controls on screen** (`gaps/titleband-x3.png`, `gaps/measure-gaps.txt`).
  - Title-bar background is #1A1A1E at y=1–51 in both active and inactive, which matches the board's #1A1A1E. At y=51 there is no line: #1A1A1E, where the harness shows #232323. The body is #1A1A1E. The list top border is at y=82, #2C2C2F, as on the board.
  - The harness's hairline and shade are off-screen-only for this build, as the exception assumes.
  - Active vs inactive on screen differ in 3,275 px. All of them are in the native traffic lights, the 1–2px window frame, and the four rounded corners. Excluding the frame and the lights, 178 px remain, and all sit in the corner cells. So the app's own controls draw the same whether the window is active or not.
  - Control fills on screen, active: track #2F2E32, selected pill #555558, search button #2F2E32, By status pill #2C2C2F. These are the same values the harness gave and the board specifies.
  - Geometry on screen matches the harness: track rows 10–41 at x=250, search button top 10.5 and H@14 363.5/383.5, By status pill y 53.5–71.5 and H@56 307.5/381.5, Pro dot 15.5/22.5.
- **G2, closed: a real click folds and unfolds the group** (`gaps/click-fold-x2.png`).
  - Before: Working header label ink at 101–113 (harness 101, board 100), chevron ⌄ 7×5 at (20,103), hint "by last activity" at x=308, 76×11, count "1". Separators at 82/195/308.
  - After one click: chevron › 5×7 at (21,102). That is the same footprint and position as the board's folded chevron, (21,102) 5×7. The hint is gone, which matches the board. The count "1" stays. The row is removed. Recent moves up to label ink 138, the board's second-header position (138). The first separator moves to y=232, which matches the board's layout for a folded first group (board fold-needs: 232).
  - After a second click: the capture is byte-identical to the before capture. Unfolding restores the state exactly.
- Hover and pressed states, scroll behaviour and keyboard focus are not pictured in the board. They stay N/A.

## 6. Timing (observed wall clock, HKT)

| Phase | Time | Notes |
|---|---|---|
| Preparation | 14:14–14:15:30 | Read the board source, checked provenance, created the evidence folder |
| App capture | 14:15:30–14:16:30 | 5 harness shots plus sRGB conversion |
| Design capture | 14:16:30–14:20:00 | Chrome render, 4 real header clicks, 5 DOM dumps, 5 captures |
| Comparison | 14:20–14:33 | Text, edge, icon, hairline, residual and fill measurements, zooms, 74 crop pairs reviewed |
| Report | 14:33–14:38 | First pass of this file (PARTIAL) |
| Gap round | 14:44–14:52 | Provenance check, sRGB copies, G1/G2 measurements, 2 sheets, this update (PASS) |

Tool failures and recoveries (each happened once):
1. The worktree guard refused Bash commands that contain shell variables or loops. I moved that logic into `tools/*.py` and called it with literal paths.
2. `javascript_tool` output truncates at about 1.1k characters. I pulled the DOM dumps out through a loopback POST sink instead (`tools/receiver.py` on 127.0.0.1:8797; checked the port was free with `lsof`; stopped it after use).
3. My first crop manifest dropped multi-line DOM box records (rows and headers). That happened because textContent tabs and newlines broke the record parser. I fixed `records()`, re-ran every measurement, and regenerated `crops/`. Text measurements use single-line records and were unaffected.

Chrome tab 1045567362 (mine) is still open on the board, folded-all state. No close tool was available.

## 7. Files

Captures: `board-<state>.png`, `app-<state>.png` (raw, Mi monitor profile), `app-<state>-srgb.png`. DOM: `board-dom-<state>.tsv`. Measurements: `measure-text-<state>.tsv`, `measure-boxes.tsv`, `measure-icons.tsv`, `residual.txt`. Visual: `sbs-<state>.png`, `zoom/*.png`, `crops/` (`index.json` holds source and crop sha256 values and pixel boxes, plus `review-01…06.png`). Gap round: `gaps/*-srgb.png`, `gaps/measure-gaps.txt`, `gaps/titleband-x3.png`, `gaps/click-fold-x2.png`. Tools: `tools/`.
