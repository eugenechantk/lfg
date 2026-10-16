# Phase 3, round 5: independent visual verification (terminal D, sign-in browser E)

Verdict: **D PASS · E PASS · overall PASS** for the declared scope.

I found no delta above the 1.5 pt tolerance. The largest geometric difference is 1.33 pt: with the keyboard hidden, the key row's keys sit higher than the board's (O3). Everything else listed below is data, an accepted exception, or an observation.

**Process incident (not a visual finding):** one stray "|" key press reached the fixture shell. See [Incident](#incident). I removed the character, and the pane matched its earlier content before any further capture.

## Scope

- **Live** verification on the iPhone 17 Pro simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD` (cc-68284ba9), host Eugenes-MacBook-Pro.
- **Build**: the installed Debug LFG.app, launched with `--no-build`.
  - `LFG.debug.dylib`: mtime 2026-10-16 11:00:52 HKT, sha256 prefix `01849daf78a7`.
  - The DerivedData copy and the copy installed in the simulator are identical, and the hash was unchanged after the last launch.
  - No rebuild. No source edits.
- **Reference kind**: HTML, from `http://127.0.0.1:8793/`.

  | Board | sha256 | State |
  |---|---|---|
  | `s2-terminal.dc.html` | 6eba7d38…a3bd62 | Default `{kb: true, fit: 'Fit'}`. Toggled with the board's own buttons. |
  | `s2-signin.dc.html` | a5bde99b…c6b147 | Default `step: 'browse'`. |

  `support.js` sha256 is 3f160299…3dfe0f10.
- **Renderer**: my own new Chrome tab (1045567274), DPR 1, viewport 1135×1266, `body.zoom = 3`.
  - I captured four 585×1266 tiles per state with the region-zoom capture at scale 1. The root was shifted with `transform: translate(-195px|0, -422px|0)`.
  - `scripts/stitch.py` joins the tiles into 1170×2532 renders.
  - The DOM dumps (rects plus computed styles) were taken at zoom 1 and posted to a loopback receiver on 127.0.0.1:8799, which is now stopped. They are in `board/dom-*.json`.
  - My Fit keyboard-hidden and sign-in renders are byte-identical to round 4's (`38d85ce7ffb5`, `3ec7a990151f`), so the renders are reproducible.
- **Board renders** (sha256 prefix):
  - `board-kbo-fit-3x` e58bf81d4ab8
  - `board-kbo-wide-3x` 9810552f89a3
  - `board-kbc-fit-3x` 38d85ce7ffb5
  - `board-kbc-wide-3x` 3f49e63ebe03
  - `board-kbc-fit-keysend-3x` ceb1b8670584
  - `kbo-wide-keysend-t11` 442333fdbb70 (the keyboard-open key-row end; one tile)
  - `board-signin-3x` 3ec7a990151f

  Here kbo means keyboard open (keys bottom 270) and kbc means keyboard closed (keys bottom 34).
- **App frames**: the last frame of each h264 recording, 1206×2622 (3x). Hashes, sha256 prefix:
  - `term-fit-kbup` 776fcd39c481
  - `term-fit-kbup-keysend` aa1790e7d7dc
  - `term-wide-kbup` 8d5cbec6b5a8 (key row scrolled to the end)
  - `term-wide-kbhidden` 074398b521bd (row at the end)
  - `term-fit-kbhidden` 5452b465e25e
  - `term-fit-kbhidden-keystart` e74918524a49 (row at the start; last frame of a 3 s recording)
  - `signin` a0addd18e456

  AX dumps: `app/ax-term-wide-kbhidden.json`, `app/ax-signin.json`.
- **Route D**:
  1. `flowdeck run --no-build`.
  2. `open-url lfg://session/1936147b-…`.
  3. Tap `composerPill.terminal`. The terminal opens in Fit with the keyboard up.
  4. Write the W ruler from the Mac with the caller's `tmux -L s2fixture send-keys` command. I rewrote it after each Fit/Wide change so it wraps at the current width.
  5. Swipe the key row from (380,828) to (20,828) pt, in the 7 pt band above the keys.
  6. Tap "Show wide terminal".
  7. Tap "Hide keyboard". It was on screen at 350–394 pt.
  8. Tap "Fit terminal to screen".
  9. Swipe the row back with (20,792) → (380,792).
  10. Swipe the row to the end again, then tap "Show keyboard" at its visible centre (372,814). The row returned to the screen bottom with the label "Hide keyboard".
- **Route E**: `flowdeck run --no-build --launch-env LFG_S2_VIEW_FIXTURE=signin`, then tap "Sign in on iPhone". I did not tap "I'm signed in" or any send control.
- **Coordinates**:
  - pt = px / 3.
  - y is measured from the page or sheet top: board 54, app 62.
  - Bottom-anchored items are measured from the screen bottom (844 / 874).
  - Right-anchored items are measured by their right inset (390 / 402).
  - Board values come from the render and agree with the DOM dump.
- **Accepted exceptions applied** (from the caller):
  - device size and top inset;
  - the hardware keyboard: no soft keyboard is drawn, the keyboard-up row sits at the screen bottom, and the iOS backdrop sits under the hidden row;
  - SF Pro vs Chrome text widths;
  - SF Mono vs Menlo widths, weights and shapes;
  - live terminal output, including the tmux status line and the partial row above the first row;
  - the mock web page (the app loads example.com);
  - the app's disabled Back compared with the board's disabled Forward;
  - the AXe `enabled` field is not used as evidence;
  - icon rasterisation;
  - h264 colour levels (about 2 levels darker).
- **Tolerance**: ≤1.5 pt is an observation.

## Matrix (component × state × criterion)

Columns: 1 internal consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour/tokens · 6 glyphs · 7 spacing/shape · 8 states · 9 navigation chrome. Numbered O items are observations, not deltas.

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| D close button (all 4 states) | PASS | PASS | N/A | N/A | PASS | PASS | PASS (O6) | N/A | PASS |
| D title + subtitle (all 4) | PASS | PASS | PASS (O1 data) | PASS | PASS | N/A | PASS | N/A | PASS |
| D Fit/Wide control, Fit selected | PASS | PASS | PASS | PASS | PASS | N/A | PASS (O6) | PASS | PASS |
| D Fit/Wide control, Wide selected | PASS | PASS | PASS | PASS | PASS | N/A | PASS | PASS | PASS |
| D terminal text, Fit (kb up / hidden) | PASS (O5) | PASS | N/A (live) | PASS (O2) | PASS (O7) | accepted (O2) | PASS | PASS | N/A |
| D terminal text, Wide (kb up / hidden) | PASS (O5) | PASS | N/A (live) | PASS (O2) | PASS (O7) | accepted (O2) | PASS | PASS | N/A |
| D cursor, Fit / Wide | PASS | PASS | N/A | N/A | PASS | PASS | PASS | PASS (steady) | N/A |
| D key row, keyboard up, start | PASS | PASS (O2) | PASS | accepted (O2) | PASS | accepted (O2) | PASS (O6) | PASS | N/A |
| D key row, keyboard up, end | PASS | PASS | PASS | accepted (O2) | PASS | PASS | PASS | PASS | N/A |
| D key row, keyboard hidden, start | PASS | PASS (O3) | PASS | accepted (O2) | PASS | accepted (O2) | PASS | PASS | N/A |
| D key row, keyboard hidden, end | PASS | PASS (O3) | PASS | accepted (O2) | PASS | PASS | PASS | PASS | N/A |
| D keyboard key (up ↔ hidden) | PASS | PASS | PASS (AX labels) | N/A | PASS | PASS | PASS | PASS (both directions) | N/A |
| D whole screen (4 states) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (no leaked chrome) |
| E sheet (top edge, corner, fill) | PASS | PASS | N/A | N/A | PASS | N/A | PASS (O6) | N/A | PASS |
| E close button | PASS | PASS | N/A | N/A | PASS | PASS | PASS | N/A | PASS |
| E address pill (lock, host, subtitle) | PASS | PASS | PASS (O1 data) | PASS | PASS | PASS | PASS (O6) | N/A | PASS |
| E reload button | PASS | PASS | N/A | N/A | PASS | PASS | PASS | N/A | PASS |
| E web content region | PASS (O9) | PASS | N/A (mock) | N/A | N/A (mock) | N/A | PASS | N/A | N/A |
| E Back / Forward | PASS | PASS | N/A | N/A | PASS | PASS | PASS | PASS (accepted Back) | PASS |
| E "I'm signed in" | PASS | PASS | PASS | PASS (O4) | PASS | N/A | PASS (O6) | N/A (not tapped) | PASS |
| E whole screen | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

## Measurements (board / app, pt)

### D header (the same in all four states)

| Item | Board | App |
|---|---|---|
| Close circle (x, y, w, h) | 12, 4, 44×44 | 12, 4, 44×44 |
| Close fill | #313132 | #2F2F31 |
| Close X glyph | 29.67, 21.67, 9×9 | 29.67, 21.67, 9×9 |
| Title ink | y 11.67, h 12.33, centre −24.33 from screen centre, #F2F2F7 | y 11.67, h 12.33, centre −24.0, #F2F2F4 |
| Title ink width | 65.33 | 63.33 (accepted SF Pro width) |
| Subtitle ink | y 31.33, centre −24.0, #A1A1A6 | y 31.33, centre −24.17, #A1A1A4 |
| Segmented outer | 92×32, y 10, right inset 12, track #313132 | 92×32, y 10, right inset 12, track #2F2F31 |
| Segmented thumb | 44×28, insets 2/2/2 | 44×28, insets 2/2/2 |
| Fit label (selected / unselected) | 13.33×9.33, y 21.0, centred | 13.33×9.0, y 21.33, centred |
| Wide label (selected / unselected) | 28.0–28.67 × 9.33 | 28.0–28.33 × 9.0 |

### D terminal text

| Item | Board (DOM / render) | App (pixels) |
|---|---|---|
| Row pitch, Fit | 17.4 (12 px × 1.45) | 17.41 from the grid fit; adjacent rows 17.33–17.67 (px-snapped) |
| Row pitch, Wide | 15.225 | 15.0–15.33 |
| Ascender / digit ink height ("0 fail" vs "line2"), Fit | 9.67 | 9.67 |
| Ascender / digit ink height, Wide | 8.33 | 8.33 |
| Text ink colour | #D1D1D6 | #D0D0D2–#D2D2D4 |
| Left inset | 12 (padding) | 12.0 (ruler and status bar) |
| Gap, last row bottom to key-row top | 10 (padding) | 10.33 in all four states |
| Cursor, Fit | 7.0×13.67, #D1D1D6. Top 2.0 above the ascender, bottom 2.67 below the baseline. | 7.33×14.33, #D0D0D2. Top 2.67 above, bottom 2.67 below. |
| Cursor, Wide | 6.33×12. Top 1.67 above, bottom 2.33 below. | 6.0–6.33×12. Top 2.0 above, bottom 2.33 below. |
| Cursor blink | none | none: four frames over 2.3 s (`frames3s/`) differ in at most 29 px, all compression noise |
| Cell advance | Menlo 7.225 (Fit), 6.328 (Wide) | 7.41 Fit (50 W across 12.0–382.67); 6.49 Wide (58 W across 12.0–388.33). These equal SF Mono's advance on macOS (7.418 / 6.491; `scripts/fontadv.swift`), so O2 applies. |

### D key row

| Item | Board | App |
|---|---|---|
| Row height | 50 | 50 |
| Border | 1 px #2C2C2F | 1 px #272729–#29292C |
| Row fill | #1C1C1E | #1A1A1C |
| Keys | 36 tall, 7.33 below the row top, gap 6 | 36 tall, 7.0 below the row top, gap 6 |
| Key fill | #3A3A3B | #38383B |
| Key corner contour (esc) | — | max normal distance 0.67 pt from the board |
| Key-row end, right insets of the last four keys (keyboard up and hidden) | 150 / 104 / 58 / 8 | 150 / 104 / 58 / 8 |
| Keyboard icon | 20.0×15.33 at (12.0, 10.33) in its key | 20.0×15.33 at (12.0, 10.33) |

- The keyboard icon's per-row ink profiles match for each state: a down chevron when the keyboard is up, an up chevron when it is hidden. See the crops `D-kbkey-icon__kbup` and `D-kbkey-icon__kbhidden`.
- Keyboard up: the board's row sits at 320 from the bottom because it draws a soft keyboard. The app's row sits at 50 from the bottom, which is the accepted hardware-keyboard exception.
- Keyboard hidden: row top 84.0 / 85.0 from the bottom. Row bottom 34 / 35. Key bottom 40.67 / 42.0. See O3.

### E sign-in browser

| Item | Board | App |
|---|---|---|
| Sheet top | page-relative 0, #1C1C1E | page-relative 0, #1A1A1C |
| Sheet corner contour | — | max 0.94 pt from the board |
| Close | 10, 13, 40×40, #2C2C2F; glyph 8.67×8.67 at 25.67, 28.67, #D1D1D6 | the same position, #2A2A2D; glyph the same, #D0D0D2 |
| Reload | right inset 10, 40×40; glyph 12.33 at +14, +18 in its box | right inset 10, 40×40; glyph 12.0 at +14, +18 |
| Pill | 58, 13, h 40, right inset 58, #2C2C2F | 58, 13, h 40, right inset 58, #2A2A2D |
| Pill corner contour | — | max 1.05 pt from the board |
| Lock icon | 7.67×9.0 at y 22.33, #A1A1A6 | 7.67×9.0 at y 22.33, #A0A0A2 |
| Lock-to-host gap | 7.33 | 7.33 |
| Host ink | y 21.33, h 12.67, #F2F2F7 | y 21.0, h 13.0, #F3F3F5 |
| Pill line 1 centre offset | 0.33 | 0.5 |
| Subtitle ink | y 37.0, h 10.33, #FFB33F, centred (+0.33) | y 36.67, h 10.0, #FCB041, centred (+0.33) |
| Web content | top 64, bottom 92 from the screen | top 64, bottom 92 |
| Back / Forward | 44×44 at x 10 / 62, bottom 34, #2C2C2F | the same, #2A2A2D |
| Back / Forward glyphs | 7.33×12.67 at (18, 15.67); disabled ink #636366 | 7×12 at (18, 16); disabled ink #646466 (both) |
| Done button | x 114, right inset 10, bottom 31.0, h 49 (antialiased edge), #096EE0 | x 114, right inset 10, bottom 30.67, h 49.33, #056DDE |
| Done corner contour | — | max 1.05 pt from the board |
| Done label | ink h 16.0, centre offset (0.17, 0.83) | ink h 16.0, centre offset (0.17, 0.67) |

## Findings

No delta exceeds 1.5 pt. Observations:

- **O1 (data):** the copy differs only where the fixture data differs.
  - D subtitle: "Shell on Pro" / "Shell on Eugenes-MacBook-Pro". It fits on one line, centred (centre −24.0 / −24.17), and is not truncated.
  - E host: "accounts.google.com" / "example.com".
  - E pill: "… · goes to Air" / "… · goes to Mac", from the fixture's host label.
  - The format strings match.
- **O2 (accepted mono metrics):**
  - Cell advance: board 7.225 / app 7.41 (Fit) and 6.33 / 6.49 (Wide), which is SF Mono's advance. So the app fits 50 / 58 columns on its 378 pt grid. The text grid ends at 382.9 pt in Fit.
  - Key widths: esc and tab 43.33 / 44, ctrl 51.67 / 53. Keys after ctrl therefore sit up to 2.67 pt further right when the row is at its start. At the row's end the right insets are identical.
  - SF Mono's arrow and ⌥ glyphs are larger than Menlo Bold's (ink sizes):

    | Glyph | Board | App |
    |---|---|---|
    | ↑ / ↓ | 4.67×7.67 | 8×10 |
    | ← / → | 7.33×5 | 8×8.33 |
    | ⌥ | 7.67×7.33 | 8×8.67 |
    | ~ | 8.33×4 | 6.67×3 |

  - Label weight looks lighter than Chrome's Menlo Bold. The ink coverage of "ctrl" is 108 pt² on the board and 97 pt² in the app. Unsmoothed SF Mono references (`board/fontref-sfmono-*.png`, made by `scripts/fontref.swift`) give 93 for Medium and 105 for Semibold. The app's stem coverage (9.48) matches Semibold's (9.62).
  - All of this falls under the caller's SF Mono vs Menlo exception.
- **O3:** with the keyboard hidden, the key row sits 1.0 pt higher. Row top from the bottom: 84.0 / 85.0. Row bottom: 34 / 35. The keys sit 1.33 pt higher (key bottom 40.67 / 42.0), because the board's keys are 7.33 below the row top and the app's are 7.0. Both differences are within tolerance.
- **O4:** the "I'm signed in" label ink is 103.67 wide on the board and 97.67 in the app. This is SF Pro 17 pt tracking vs Chrome's, so the accepted text-width exception applies. The height and centring match.
- **O5:** the tmux status line's green fill (#22BA20) runs from 12 to 390 pt. That is 7.1 pt past the grid's last cell (382.9). This is live output with no board equivalent.
- **O6:** corner shapes all lie within 1.05 pt (maximum normal distance) of the board's circular corners:

  | Shape | Max normal distance |
  |---|---|
  | E sheet | 0.94 |
  | E pill | 1.05 |
  | E done | 1.05 |
  | E close | 0.33 |
  | E back | 0.33 |
  | D close | 0.33 |
  | D segmented track | 0.75 |
  | D key | 0.67 |

  The app's corners start a few px further in on their first row, which is consistent with continuous corners. Script: `scripts/measure_corners.py`.
- **O7:** the board's ANSI colours (prompt green #30D158, blue #409CFF, orange #FF9F5A, grey #8E8E93) belong to mock output. The live shell exercised only the default foreground (#D1D1D6, which matches) and tmux's ANSI-green status background (#22BA20, from SwiftTerm's palette). If the board's palette is meant to be a requirement, it has not been verified.
- **O8:** flat fills in the app run 1–3 levels darker than the board's. This is the h264 exception.
- **O9:** example.com renders its content with a grid of tofu "?" boxes in the web view. This is web content (a mock in the board) and out of scope.

## Incident

At 11:23 I called `flowdeck ui simulator tap "Show keyboard"` by label while the key row was scrolled to its start, so that key was off screen at x 581–625 pt. FlowDeck reported "Tapped", but the touch landed on the "|" key, which was the last key on screen at x 397–437. One "|" was typed into the fixture shell's input line, without Enter. `capture-pane` showed `sh-3.2$ |`.

To repair it, I sent one `tmux -L s2fixture send-keys -t lfg-term-phone BSpace` from the Mac. `capture-pane` then showed `sh-3.2$` and the earlier content. I then scrolled the row to its end and tapped the keyboard key by its visible AX centre.

No other terminal key was pressed. Every pane check before and after the swipes and the keyboard-key taps showed the content unchanged. The incident does not affect any measurement:
- every terminal frame had been captured before it;
- the later frames were taken only after the repair;
- E is a separate launch.

## Coverage gaps and exclusions

- These states lie outside the declared scope, so I did not exercise them:
  - D's ctrl-latched state (blue #0A84FF): pressing ctrl is forbidden;
  - E's review sheet and "Signed in" result: "I'm signed in" is forbidden.
- D's keyboard-up soft keyboard is not drawn, because the simulator has a hardware keyboard (accepted). Real software-keyboard layout was not verified.
- The terminal output is live. The board's lines and ANSI palette are mock (O7).

## Whole-screen checks

- D: the header, terminal and key row stack without overlap. No session-view chrome leaks into the page (no composer and no pills).
- D: Fit/Wide changes the type size and the column count (50 → 58), and the grid stays bottom-anchored.
- D: hiding the keyboard moves the row to 85 pt from the bottom and shortens the grid by 2 rows. Showing the keyboard restores the row to the screen bottom. The labels switch between "Hide keyboard" and "Show keyboard".
- E: the sheet's top edge, the header and the bottom bar are in place, and the web view fills 64 pt from the sheet top to 92 pt above the screen bottom.

## Evidence paths

- Board renders, tiles, DOM dumps and font references: `board/`.
- App frames, recordings and AX dumps: `app/`. Frames of the 3 s cursor check: `app/frames3s/`.
- Component crop pairs (42) and review sheets: `crops/pairs/` (`index.json` holds the source and crop hashes and the pixel boxes). Manifest: `pairs.json`.
- Measurement output:
  - `term-measures.json`
  - `text-measures.json`
  - `signin-measures.json`
- Scripts:
  - `scripts/measure_term.py`
  - `measure_text.py`
  - `measure_seg.py`
  - `measure_seg_label.py`
  - `measure_seg_keys.py`
  - `measure_row_bottom.py`
  - `measure_cursor_rel.py`
  - `measure_corners.py`
  - `measure_signin.py`
  - `measure_stem.py`
  - `sample_status.py`
  - `stitch.py`
  - `make_pairs.py`
  - `px.py`

## Timing (observed, HKT)

| Phase | Time |
|---|---|
| Preparation: scope, board sources, hashes, receiver | 11:04–11:06 |
| Design capture: 7 DOM dumps, 30 tiles, stitching | 11:06–11:17 |
| App capture: launches, 7 recordings, AX, sign-in | 11:17–11:27 (includes the incident repair at 11:23) |
| Comparison: measurement scripts, font references, crops, review | 11:27–11:42 |
| Report | 11:42–11:50 |

**Tool failures and recoveries:**
- A zoom capture at `scale: 0.3` saved the downscaled image, so I took it again at scale 1.
- `ffmpeg -sseof` gave no frame for 0.3 s recordings, so I used `-fps_mode passthrough -update 1` instead.
- The worktree guard rejected compound commands and shell variables, so I moved the work into script files.
- The label tap on an off-screen key caused the incident above.
- Chrome tab 1045567274 may still be open: no tab-close tool was available, and `window.close()` was ignored.
