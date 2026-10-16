# Visual verification — session sheet (`s2-menu`), phase 3, round 1

**Verdict: FAIL.** There is one delta, D1, and it depends on the data. Everything the board pictures matches within tolerance. D1 shows up only because the fixture uses a long real host name. With that same text, the board's own CSS wraps the line; the app truncates it to one line.

## Scope and provenance

| Item | Value |
|---|---|
| Scope | Live app, one state: the menu fixture (`LFG_S2_VIEW_FIXTURE=menu`). The board is static, so this is a visual check of the pictured state only. |
| Reference kind | HTML board, rendered in Chrome 154 at CSS zoom 3. Six native 585×844 tiles were stitched into `raw/board-3x.png` (1170×2532). |
| Board source | `s2-menu.dc.html` sha256 `a08fc9fd…dce5a8`; `support.js` sha256 `3f160299…dfe0f10`; served from `http://127.0.0.1:8793/` (own tab 1045567262; URL checked before each capture) |
| Board render | `raw/board-3x.png` sha256 `725eb7d5…facef`; the DOM values were dumped from the same tab at zoom 1 (the root sits at 0,0) |
| App build | `flowdeck run` at 06:55:20–06:55:27 HKT. build.log says `BUILD SUCCEEDED` at 06:55:24. Worktree HEAD is `8b0be91` plus the uncommitted tree. App PID 19987. |
| App capture | h264 recordings via `flowdeck ui simulator record`, last frame via ffmpeg. Frames are 1206×2622 (3x, 402×874pt), yuv420p bt709. Main frame `raw/app1.png` sha256 `b4b16eb4…09285`. The re-captures `app2`, `app4` and `app5` (06:58, 07:12, 07:15) match it inside the sheet: app4 differs from app1 in 5 pixels above level 12. |
| Simulator | iPhone 17 Pro `C47EB72F-A352-44C9-8A80-9F13D33780AD`, iOS 26.3 |
| Coordinate model | Board, relative to the sheet: X = px/3, Y = px/3 − 112. App sheet measured at x 24–1181 px, so 8.0–394.0pt and 386pt visible. Its top is at 392 px (130.67pt). Scale S = 386/402 = 0.9602. App, relative to the sheet: X = (px/3 − 8)/S, Y = (px/3 − 130.67)/S. Right-anchored items are compared by their inset from the sheet's right edge, because the app lays out at 402pt and the board at 390pt. |
| Accepted exceptions | System sheet chrome: grabber, dim, top position, inset and the 0.96 scale. Liquid Glass toolbar buttons behind the sheet. Real host names and session id `s2fx-fork`. The Browser preview tile is dimmed because the fixture has no preview. "Medium" effort, with segments sized to their label. SF Pro is narrower than Chrome's rendering. Icons drawn from the board paths. The board's 3x render draws thin separators (row pitch about 42.7pt; DOM says 43). |

## Matrix (one state: menu fixture)

Criteria: 1 internal consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 nav chrome

| Component | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Sheet container (system) | PASS | N/A (accepted) | N/A | N/A | PASS (O7) | N/A | N/A (accepted) | N/A | PASS |
| Title | PASS | PASS | PASS | PASS (O5) | PASS | N/A | PASS | N/A | N/A |
| Rename button | PASS | PASS | N/A | N/A | PASS | PASS | PASS | N/A | N/A |
| Subtitle | PASS | FAIL (D1a) | PASS (data) | PASS | PASS | N/A | PASS | N/A | N/A |
| Close button | PASS | PASS | N/A | N/A | PASS | PASS | PASS | N/A | N/A |
| Tile Terminal | PASS | PASS | PASS | PASS | PASS | PASS (O4) | PASS (O3) | N/A | N/A |
| Tile Files & links + badge | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| Tile Subagents + badge | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A |
| Tile Sign in | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PARTIAL (G3) | N/A |
| Tile Browser preview | PASS | PASS | PASS | PASS | accepted dim | PASS | PASS | PARTIAL (G3) | N/A |
| Tile iPhone preview | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| Card 1 + separators | PASS | PASS | N/A | N/A | PASS | N/A | PASS (O2, O3) | N/A | N/A |
| Row Model | PASS | PASS | PASS | PASS | PASS | PASS (O1) | PASS | N/A | N/A |
| Row Effort (segmented) | PASS | PASS (O8) | PASS (accepted) | PASS | PASS | N/A | PASS | PARTIAL (G3) | N/A |
| Row Host | PASS | FAIL (D1b) | PASS (data) | PASS | PASS | PASS (O1) | FAIL (D1b) | N/A | N/A |
| Row Fork session | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| Row Mark as unread | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| Card 2 | PASS | PASS | N/A | N/A | PASS | N/A | PASS | N/A | N/A |
| Row Stop current turn | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| Row End session | PASS | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| Footer | PASS | PASS | PASS (data) | PASS (O6) | PASS | N/A | PASS | PARTIAL (G2) | N/A |
| Session view behind the sheet | PASS | N/A (accepted) | N/A | N/A | N/A | N/A | N/A | N/A | PASS (O9) |

## Finding

### D1 — A long host name overflows differently. Depends on data; low severity; one cause.

The board's subtitle span and Host value span have no `nowrap`. The title is the only element with `nowrap` plus ellipsis. I put the fixture's real host string into the board's DOM in my own tab; the source file was not touched. The board's rules then wrap both lines. The app keeps both on one line and truncates.

- **D1a, header subtitle.** Board: wraps to two lines (span 308×32pt, from y 53). App: one line, with the host cut to "Eugenes-M…". The ink ends at x 337.4pt laid-out, which fills the space up to the close button. Probe evidence: `sbs/probe-board-real-host-header-1x.png`. App evidence: `crops/02-title-rename-app.png`.
- **D1b, Host row.** Board: the value wraps to two lines and starts 10pt after the "Host" text (value box x 79.7, text right 69.7). The row grows from 43 to 63pt. App: one line, head-truncated to "…es-MacBook-Pro · move to Mac". The value ink starts at x 96.85pt laid-out, 29.5pt after the "Host" ink (ends at 67.3). The row stays 43pt. The value's right inset matches (app 53.8 / board 53.3). So in the truncated state, the app leaves about 17–19pt more space before the value than the board's 10pt flex gap, which hides about 4–5 more characters of the host name. Evidence: `sbs/probe-board-real-host-row-1x.png`, `crops/22-row-host-{design,app}.png`, `sbs/22-row-host.png`.
- Note: truncating instead of wrapping may be an acceptable product choice, since rows stay 43pt. That is the owner's call. The extra gap in the Host row applies whichever way it goes. Part of it may come from how truncation drops whole characters (up to one glyph, about 10pt); that cause is a guess.

## Observations within tolerance (no action)

- **O1, chevrons (Model, Host).** Board ink is 5.0×7.7pt; app is 4.2×6.6–6.9pt (0.8–1.1pt smaller). Inset from the card's right edge: board 18.7, app 19.4. Colour: board 72,72,74; app 69,69,72.
- **O2, separators.** Board DOM is 0.5pt. In the app, the line spreads across 3 device pixels (peak 56 on 45), roughly 0.7–1pt in the video. Card-1 positions: app 316.25/365.2/408.25/451.3 vs board DOM 316.75/365.75/408.75/451.75 (−0.5). Card 2: 550.2 vs 550.75. Both run the full card width (inset 0).
- **O3, corner radii** (same cut-area method on both). Tiles: app 17.2–17.7 vs board 16.8 (board true value 18), so the app is about 0.6pt larger. Cards: app 18.1–19.6 vs board 18.6 (true value 20).
- **O4, tile icons.** Offset from the tile's left edge: Terminal 15.3 vs 14.7, Files 17.0 vs 16.7, Subagents 15.3 vs 14.7, iPhone 17.4 vs 17.7. Size within 0.7pt.
- **O5, title ink width.** App 205.2 vs board 222.3 (−7.7%), which is SF text width. Gap from title to rename button: 9.03 vs 9.0. Ink height 17.0 vs 17.3.
- **O6, footer.** App character advance is 7.42pt vs the board's 7.2pt. Glyph heights are equal (letter l 9.03 vs 9.33; m 6.6 vs 6.67). Cause, confirmed: Chrome renders the board footer in Menlo, the third font in its stack. Canvas measures `ui-monospace` and `"SF Mono"` the same as the proportional fallback (209.29). Menlo measures 310.66, which plus 12pt button padding equals the DOM width 322.67. The app uses SF Mono, the board's first choice. Centred in both (insets 38.5 / 40.3).
- **O7, colours** (solid-core medians, board vs app). Sheet 28→26. Tile and card 44→42. Button, badge and track 58→56. Selected segment 99→97. Title 255→253. Row text 255→251. Tile label 242→238. Subtitle and value grey 161→158/159. Footer 161→155. Blue 65,156,255→63,151–153,245–251. Purple 191,90,240→189,88,237. Red 255,69,59→247,67,58. Chip 181,86,47→180,84,45. Stop square 242,242,248→240,240,246. The status-bar clock reads 253 (pure white), so the app runs about 2 levels low because of video.
- **O8, widths set by device or data.** Tiles are 118 vs 114 and cards 370 vs 358 because the screen is 402pt, not 390pt. Gaps (8, 14) and insets (16) are identical. The Effort track is 212.8 vs 200 ("Medium", accepted). The High segment is 48.95×27.77 vs 49×28. Right insets: track 31.94 vs 32, segment 82.97 vs 83.
- **O9, behind the sheet.** The app shows the real session-view nav (status line "Working · 3m 35s · Eugenes-MacBook…" and glass buttons). The board draws only a dimmed title. That is accepted chrome. The empty space below the footer is 144 vs 109pt because the system sheet is taller (accepted).
- **Positions that match** (app laid-out vs board DOM, pt). Close button r 15.97/16, y 19.8/20, size 36.1/36. Rename button 30.2/30. Subtitle x 21.2/21.3, y 55.5/56. Tile rows y 95.8/96 and 181.9/182. Tile labels y 150.7/150.7, two-line labels y 220.4/220.3. Badges 10.0–10.1 from the top-right / 10. Card 1 y 273.9/274, card 2 y 507.9/508. Row labels x 33.67/33.67. Icon column x 34.0/34.0. Label column x 61.8/61.3. Footer y 609.6/610 (DOM-corrected). Text weights by ink coverage, app/board: title 0.975, tile labels 1.01, row labels 0.99, segment labels 1.01–1.014.

## Coverage gaps (not verified)

- **G1.** No interactions were exercised: tiles, rows, rename, close, tap-to-copy, effort switching, and sheet dismissal. The fixture is not real, and the caller said not to tap. The board is also static.
- **G2.** The footer's id abbreviation (the board's `7f3a…c21` head…tail form) is not exercised, because the fixture id `s2fx-fork` is short.
- **G3.** States not pictured in the app: the Sign in badge (the board data defines an amber variant, but the board does not show it), the enabled Browser preview tile, and other effort selections.
- **G4.** Font identity (SF Pro weights) is inferred from ink coverage and glyph metrics, not read from source.

## Files

- Raw: `raw/app1.png` (main), `raw/app{2,4}.png` (stability), `raw/app{1..5}.mov`, `raw/board-3x.png`, `raw/board-tiles/tile-40{3..8}.png`
- Crops (native pixels, with hashes in `crops/index.json`): `crops/<id>-{design,app}.png`, review sheets `crops/review-0{1,2,3}.png`; manifest `pairs.json`
- Side-by-sides (viewing only; app rescaled by 1/0.96): `sbs/<id>.png`; board probes with the real host name: `sbs/probe-board-real-host-{header,row}-1x.png`
- Measurement scripts (scratchpad, not evidence): `vdv-menu-r1-measure.py`, `vdv-menu-r1-radii.py`, `vdv-menu-r1-weight.py`, `vdv-menu-r1-sbs.py`, `vdv-menu-r1-stitch.py`

## Timing (observed wall clock, HKT)

| Phase | Time | Notes |
|---|---|---|
| Preparation | 06:55:00–06:55:20 | Server answered 200; read board source |
| App capture | 06:55:20–06:55:53 | `flowdeck run` (build succeeded 06:55:24), first recording at 06:55:53; stability re-captures at 06:58, 07:06, 07:12, 07:15 |
| Design capture | 06:55:30–07:03 | DOM dump (chunked; tool output truncates), six native zoom tiles, stitch |
| Comparison | 07:03–07:16 | Numeric bboxes, colours, radii, weights, footer font probe, real-host overflow probe |
| Report | 07:16–07:20 | |

Tool issues, recorded once: (1) The javascript tool truncates output, so the DOM dump was fetched in chunks. (2) Zoom captures larger than about 1M px are downscaled, so I used 585×844 tiles. (3) The worktree guard rejected compound commands with shell variables and one heredoc, so I split them. (4) **Incident:** I used Write on the shared scratchpad `stitch.py` and overwrote an earlier verifier's script. I restored it at once from its transcript (the 2026-10-15T13:57Z version, agent a5c0aa41). My copy now lives at `vdv-menu-r1-stitch.py`.
