# Phase 3 sheets, round 2: independent visual verification

Verdict: **A FAIL (one data-dependent delta) · B PASS · C PASS · overall FAIL**

## Scope

- Live verification. iPhone 17 Pro simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD`. The installed build was launched with `--no-build` (LFG.app Debug-iphonesimulator, binary built 2026-10-16 07:24 HKT). Fixtures: `LFG_S2_VIEW_FIXTURE=menu|subagents|files`. Links tab: one tap on "Links 2" at (288,312) pt.
- Reference kind: HTML. The boards were rendered from `http://127.0.0.1:8793/` in my own Chrome tab (1045567265), with DPR 1, CSS zoom 3 on `<html>`, and four 585×1266 tiles stitched to 1170×2532. A DOM dump was taken at zoom 1 and at zoom 3.
  - `s2-menu.dc.html` sha256 `a08fc9fd…dcce5a8`. Rendered with the long real values typed into the board's DOM in my tab: subtitle "Eugenes-MacBook-Pro · ~/dev/personal/lfg · started 2h ago", Host value "Eugenes-MacBook-Pro · move to Mac", footer id "s2fx-fork". Render `board/board-menu-longhost-3x.png` sha256 `848fe8a1…570d16`.
  - `s2-subagents.dc.html` sha256 `658b43c6…6e47e34`. Render `board/board-subagents-3x.png` sha256 `a507998e…30fc6`.
  - `s2-files.dc.html` sha256 `d8b1eae1…5fafc`. Render `board/board-files-3x.png` sha256 `f6bc5628…420d9`.
  - `support.js` sha256 `3f160299…f0dc6`.
- App frames are the last frame of 1 s h264 recordings at 1206×2622 (3x). Hashes: menu `17103fc6…e7b49914`; repeat menu `4597108c…490ff6` (same geometry); subagents `f2e24e37…4cae0`; files `46dc7697…98df5`; links `718939b2…847d1`.
- Coordinates: every number below is in **sheet-relative laid-out pt**, measured from pixels. Board: px/3, minus the sheet top (112 for A, 200 for B and C). App: the sheet edges were found from the sheet surface colour. Every app sheet is 386.0 pt visible (L = 8.0 pt) and was scaled by s = 0.9602, so app values are (px/3 − edge)/s. Sheet tops in screen pt: A 130.67, B 215.0, C 215.0. In the C frame, a dimmed transcript file card sits behind the sheet at 485–616 px, so the sheet-top search starts below it.
- Accepted exceptions applied: system sheet chrome (grabber, dim, top edge, 0.96 inset scale), Liquid Glass toolbar buttons, sample-data differences, effort segment sizing and "Medium", SF Pro vs Chrome text widths, SF Mono vs Menlo, icon rasterisation, and the board 3x separator pitch (0.33 pt per row).
- Tolerance (from the caller): ≤1.5 pt is an observation. Colours within a few levels are video tolerance; the app is a steady −2 levels against the boards on every flat fill.

## Matrix (component × state × criterion)

Columns: 1 internal consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 nav chrome

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| A header (title, pencil, close, 2-line subtitle) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| A tile grid (6 tiles, badges, dimmed Browser) | PASS | **FAIL D1** | PASS | PASS | PASS | PASS | PASS | PASS (dimmed tile accepted) | N/A |
| A card 1 (Model, Effort, Host 2-line, Fork, Mark) | PASS | **FAIL D1** (offset only) | PASS | PASS | PASS | PASS (O3) | PASS | PASS (High selected) | N/A |
| A card 2 (Stop, End) + footer | PASS | **FAIL D1** (offset only) | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| A sheet chrome / nav behind | PASS | accepted | – | – | – | – | – | – | accepted |
| B header (title, tally, close) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| B rows (running, done ×2, failed) | PASS | PASS (O5) | PASS | PASS | PASS | PASS | PASS | PASS (all 3 kinds) | N/A |
| C header + Files/Links pill | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (Files selected) | N/A |
| C sections + 5 file rows | PASS | PASS | PASS (order accepted) | PASS | PASS | PASS | PASS | N/A | N/A |
| C Links tab (consistency only) | PASS (consistent with Files) | see N1 | data accepted | PASS | PASS | see N1 | PASS | Links selected PASS | N/A |

## Findings

**D1. A (long host): the tile grid and everything below it sits 17 pt lower in the app.**
- Board: tile grid top at sheet y **96.0**. The board places the grid at a fixed `top: 96px`. The 2-line subtitle (ink 56.0–69.0 and 72.7–85.7) therefore eats the header-to-grid gap, which becomes 10.3 pt.
- App: tile grid top at **113.0**. The app flows the grid below the 2-line subtitle (ink 55.5–68.4 and 72.6–85.4) and keeps a 27.6 pt gap.
- The same offset carries down the whole sheet: card 1 top board 274.0 / app 290.7; card 2 top board 527 / app 545.5; footer ink top board 628.7 / app 647.1. The extra ~1.4 pt at the bottom is the accepted DOM row pitch.
- Measurement: pixel scans at x=112 pt (`scripts/vscan.py`). A repeat capture after relaunch gave the same tile top (717 px).
- Crops: `pairs/A-sheet-whole-*.png`, `pairs/A-tiles-*.png`, `crops/sbs-menu.png`.
- Cause: the board's absolute positioning against the app's stacked layout. This is an owner call: keep the board's fixed grid, or accept the app's flow layout as the intended behaviour for a wrapped subtitle.

What matches in the long-host case:
- Subtitle: both wrap after "~/dev/personal/lfg ·", with "started 2h ago" on line 2. Line pitch board 16.7 / app 17.0.
- Host row: both wrap the value after "move", with "to Mac" on line 2. Value ink is 33.3 tall in both. Host label is vertically centred in both (label centre board 396.8 vs value block 396.3; app 414.3 vs 414.2). Row height board 63.0 / app 63.5.

## Observations within tolerance (not deltas)

- O1. A Host value starts board x 80.0 / app 78.1 (−1.9). This follows the label: "Host" ink is 1.3 pt narrower in SF (accepted text width), then the same 10 pt gap.
- O2. A Effort control: right inset board 16.0 / app 16.3, height 32.0 / 31.6. Track and selected-segment colours match (58 vs 56, 99 vs 97).
- O3. Chevrons are slightly smaller in the app on all three sheets. A: board 5.0×7.7 / app 4.2×6.6. B: 4.7×8.0 / 4.5×7.3. C: 5.0×7.7 / 4.2×6.9. Right insets: A 18.7/19.4, B 19.3/19.8, C 18.7/19.4. Vertical centres match. Each difference is ≤1.1 pt.
- O4. A, B and C title, subtitle, row, icon and button positions all agree to ≤1.0 pt relative to the sheet's own left/right/top edges. Examples: close button board 338–374 / app 350.3–386.0, right inset 16.0 in both; pencil sits 9.0 pt after the title ink in both; tile icon offsets within a tile ≤0.3; badge right inset 10.0 in both.
- O5. B row pitch: board 3x 87.33 (zoom-3 DOM) / board DPR1 DOM 88 / app 88.06. By row 4 the app is +2.3 against the 3x render, which is the accepted DOM pitch. Inside a row, offsets agree to ≤0.4 (title → result +23.7/+24.0, title → meta +45.7/+45.5).
- O6. C row pitch board 58.67 (3x) / app 59.0. Separator positions agree to ≤0.6. Pill track 16–374 / 16–386 and 84–118 in both; selected pill 18–195 / 18–201 and 86–116 in both.
- O7. Icon sizes after removing h264 chroma fringe (ink threshold 40) agree to ≤0.6 pt: terminal 16.7×14.7 / 16.7×15.3, files 13.3×19.3 / 13.5×19.4, iPhone 11.3×19.3 / 11.1×19.4, fork 14.0×15.3 / 13.9×16.0. At threshold 10 they looked about 2 pt taller, but that is colour bleed: see `crops/icon-*.png`.
- O8. Colours (peak glyph core, board / app): grey text 159–160 / 156–158; white text 252–254 / 246–250; blue 65,154,252 / 62,150,244; red 252,69,59 / 246,64,55; green 47,207,87 / 50,201,90; chevron 72 / 69–71 (A, B) and 99 / 95 (C); close fill A 58 / 56, B and C 44 / 42; running-dot ring 37,80,47 / 34,71,44.

## Notes that disagree with a premise (not counted in the verdict)

- N1. "No board for the Links tab" is not quite right. `s2-files.dc.html` renders a Links state when "Links 2" is pressed (DOM in `board/dom-links-z3.txt`). Its rows have:
  - a 30×30 #2C2C2E rounded tile holding a letter mark at x 20;
  - the title at x 62;
  - the domain only, with no age;
  - a trailing 15 pt external-link arrow (#636366) at x 359;
  - a row height of 60.67 (3x).

  The app's Links rows instead have a 20.8 pt chain glyph at x 21.5, the title at x 56.6, "domain · age", and a chevron. The rows are 59.0 high. These match the Files rows in the app, so the tab is internally consistent. Judged only for consistency, as instructed. The owner should confirm that the app's treatment replaces the board's Links state.
- N2. Separator thickness. The board CSS is `border-bottom: 0.5px` (0.5 pt). The DPR-1 DOM rounds this to 1 px, and the 3x render draws 1 device px (0.33 pt). The app draws 3 device px at full #38383A contrast (raw column 26, 52, 55, 54, 27), which is 1.0 pt. "The app follows the DOM" therefore makes the app's lines 2× the CSS value. The difference is visible in the side-by-sides (`crops/sbs-subagents.png`, `crops/sbs-files.png`). The accepted pitch decision covers this, so it is not counted.

## Coverage gaps

- The short-host board A layout (one-line subtitle) cannot be produced with this fixture. It passed last round and is not re-proven here.
- No interaction was verified beyond the Links tab switch. As instructed, no rows, tiles or menu items were tapped.

## Evidence

- Captures: `app/*.mov|png`. Board tiles and renders: `board/`. DOM dumps: `board/dom-*.txt`.
- Paired crops: `pairs/` (helper index `pairs/index.json`, review sheets `pairs/review-0*.png`). Side-by-sides and zoomed pairs: `crops/`.
- Scripts: `scripts/` (geometry, inventory, scans, colours, stitch, loopback receiver on port 8797).

## Timing (observed, HKT)

| Phase | Time |
|---|---|
| Preparation (server check, sources read) | 07:34–07:35 |
| App capture (A, B, C, Links) | 07:35–07:37, repeat A at 08:02 |
| Board render and DOM (A long host, B, C) | 07:38–07:56 |
| Comparison (geometry, inventories, colours, crops) | 07:50–08:04 |
| Report | 08:04–08:08 |

Tool failures and recoveries:
- One JS result was blocked by the extension's query-string filter. I changed the output format and the retry worked.
- One zoom tile was saved at scale 0.2. I re-captured it at scale 1.
- The C sheet-top detection first locked onto the transcript card behind the sheet. A vertical scan showed the real edge at 645 px, and the C numbers above use that edge.
