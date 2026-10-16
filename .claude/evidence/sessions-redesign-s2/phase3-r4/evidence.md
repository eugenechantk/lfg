# Phase 3, round 4: independent visual verification (terminal D, sign-in browser E)

Verdict: **D FAIL (one minor glyph delta) · E PASS · overall FAIL**

The round-3 findings are resolved on this build. D1 (type size and row pitch), D2 (Wide clipping), D3 (blinking dim cursor), D4 (extra "-" key) and E1 (disabled-button fill) no longer reproduce. One new finding remains: G1, the keyboard-toggle glyph.

## Scope

- **Live** verification on the iPhone 17 Pro simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD`, host Eugenes-MacBook-Pro.
- **Build**: the installed Debug-iphonesimulator LFG.app, launched with `--no-build`. Binary mtime 2026-10-16 10:22:37 HKT. `LFG.debug.dylib` sha256 prefix 4aec16120a55. No rebuild and no source edits.
- **Reference kind**: HTML. The boards came from `http://127.0.0.1:8793/`, served from `scratchpad/dcrender/project`. I rendered them in my own Chrome tab (1045567271) at DPR 1 with `body.zoom = 3`. Each render is four 585×1266 tiles taken with the region-zoom capture and stitched to 1170×2532. Alignment was checked by DOM: the root sits at x 0 or −585 and scrollY is 0 or 1266. DOM dumps were taken at zoom 1 and posted to a loopback receiver on port 8798, which is now stopped.

| Board | Source sha256 | Renders (sha256 prefix) | State |
|---|---|---|---|
| D `s2-terminal.dc.html` | 6eba7d38…a3bd62 | `board/board-term-kbc-fit-3x.png` 38d85ce7ffb5, `board-term-kbc-wide-3x.png` 3f49e63ebe03, `board-term-kbc-wide-keysend-3x.png` ef6fd2fb9692, plus `term-kbopen-keysend-t11.png` (keyboard-open toggle) | Keyboard hidden (Fit, Wide, key row scrolled to the end). The keyboard-open toggle tile is the reference for the app's focused state. Toggled with the board's own buttons. |
| E `s2-signin.dc.html` | a5bde99b…c6b147 | `board/board-signin-3x.png` 3ec7a990151f | Default "browse" state. Text unedited. |

- `support.js` sha256 3f160299…f0dc6. My keyboard-hidden Fit render is byte-identical to round 3's (38d85ce7ffb5), so rendering is deterministic.
- **App frames**: the last frame of each h264 recording, 1206×2622 (3x).

| File | sha256 prefix |
|---|---|
| `app/terminal-fit.png` | 52e6a37502fd |
| `app/terminal-wide.png` | 35f6813c7d9d |
| `app/terminal-wide-keysend.png` | a47384e38bc4 |
| `app/signin.png` | 39128939a54e |
| `app/terminal-fit-cursor-3s.mov` | 9ed23d4fc325 |

- **Routes**:
  - D:
    1. `flowdeck run --no-build`.
    2. `open-url lfg://session/1936147b-…`.
    3. Tap `composerPill.terminal`. The terminal opens in Fit.
    4. Tap "Show wide terminal".
    5. Swipe the key row from (380,828) to (20,828) pt. That is the 6 pt band above the keys, so the swipe touched no key. `capture-pane` showed the pane unchanged.
  - Before opening the terminal, I wrote the W ruler from the Mac with the caller's `tmux -L s2fixture send-keys` command.
  - E: `flowdeck run --no-build --launch-env LFG_S2_VIEW_FIXTURE=signin`, then tap "Sign in on iPhone".
  - I did not tap "I'm signed in", any send control, or any terminal key.
- **Coordinates**: I measure relative to the page or sheet top (board 54, app 62). Bottom-anchored items are measured from the screen bottom. Right-anchored items are measured by their right inset. Board values come from the 3x render as px/3 and agree with the DOM dump.
- **Accepted exceptions applied** (from the caller):
  - device size and top inset;
  - SF Pro vs Chrome text widths;
  - SF Mono vs Menlo widths, weights and shapes;
  - live terminal output (including the tmux status line and the partial row above the first row);
  - the key row at the screen bottom with a hardware keyboard, compared in isolation;
  - the mock web page;
  - the app's disabled Back compared with the board's disabled Forward;
  - icon rasterisation;
  - h264 colour levels.
- **Tolerance**: ≤1.5 pt is an observation.

## Matrix (component × state × criterion)

Columns: 1 internal consistency · 2 structure/layout · 3 copy · 4 typography · 5 colour · 6 glyphs · 7 spacing/shape · 8 states · 9 nav chrome

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| D header: close, title/subtitle, Fit/Wide (Fit) | PASS | PASS | PASS (N1 data) | PASS | PASS | PASS | PASS | PASS (Fit selected) | PASS |
| D header (Wide) | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (Wide selected) | PASS |
| D terminal text, Fit | PASS | PASS (O1) | N/A (live) | PASS (accepted mono width) | PASS | accepted | PASS | PASS | N/A |
| D terminal text, Wide | PASS | PASS (O1) | N/A (live) | PASS (accepted mono width) | PASS | accepted | PASS | PASS | N/A |
| D cursor (Fit, Wide) | PASS | PASS | N/A | N/A | PASS | N/A | PASS (O2) | PASS (steady) | N/A |
| D bottom gap: last row to key row | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| D key row, start and end (in isolation) | PASS | PASS | PASS | PASS (accepted Menlo Bold vs SF Mono Semibold) | PASS | **FAIL G1** (toggle); arrows accepted | PASS (O3, O4) | PARTIAL (sticky ctrl not exercisable) | N/A |
| E top chrome: close, URL pill, lock, host, subtitle, reload | PASS | PASS | PASS (N1 data) | PASS | PASS | PASS | PASS | N/A | PASS |
| E web area bounds | PASS (O5) | PASS | N/A (mock) | N/A | N/A (mock) | N/A | PASS | N/A | N/A |
| E bottom bar: back, forward, "I'm signed in" | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS (disabled vs disabled); enabled Back not producible (accepted) | PASS |
| E review / sent sheets | – | – | – | – | – | – | – | out of scope (behind the do-not-tap button) | – |

## Findings

**G1. D key row: the keyboard-toggle glyph is a different drawing and 2.7 pt narrower.**
- I compared it with the board's keyboard-open toggle. That is the matching state: the app shows a down chevron because the terminal is focused, with a hardware keyboard.
- Board: the outline keyboard has a single row of 5 dots and a space bar. The glyph is 20.0 × 15.3 pt. The body is 20.0 × 10.7 and the chevron is narrow and deep, 6.0 × 3.7.
- App: SF Symbol style, with a 3-row key grid. The glyph is 17.3 × 15.0. The body is 17.3 × 11.3, −2.7 wide. The chevron is wide and flat, 9.7 × 2.7: +3.7 wide, −1.0 deep.
- The glyph is centred in the 44 × 36 key in both: centre x 360.0 in the button at 338.3–382.3 / 371.7 in the button at 350–394.
- Measured as pixel bboxes in the native crops: `crops/D13b-toggle-board-kbopen.png` and `pairs/D13-key-toggle-app.png`. The side-by-side is `crops/D13-toggle-kbclosed-kbopen-app.png`. Its top row is the board's hidden and open states, and its bottom row is board open beside the app.
- Every other icon on both boards (close X, reload, chevrons, lock) matches the board's size within 0.7 pt. The owner may class this one under "icon rasterisation". I count it, because rasterisation does not change a glyph's drawn width by 2.7 pt or its interior drawing.

## Round-3 findings re-checked (current build)

- **D1 (type size and row pitch): resolved.**
  - Cell pitch is 7.404 pt by autocorrelation on the 50-W row, or 7.417 from 4-glyph runs. SF Mono's advance at 12 pt is 1266/2048 em = 7.418 pt (read from `/System/Library/Fonts/SFNSMono.ttf`, `scripts/fontadv.py`). So the app draws exactly the declared 12 pt.
  - The board's 7.225 is Menlo, at 1233/2048 em. The difference is the accepted family difference.
  - Row pitch: board 17.4 / app 17.33–17.42 ('l' tops on rows 1–4 average 17.42). 39 rows fill the 679 pt text area.
- **D2 (Wide): resolved.**
  - Wide uses 10.5 pt type: pitch 6.485 pt, where SF Mono at 10.5 pt is 6.491. Rows are 15.25–15.33 / board 15.225.
  - 58 columns fit in 12.0–388.3 pt, and the full tmux status line is visible (12.0–390.0 pt). The board fits 57 columns in 366 pt; the wider screen is accepted.
- **D3 (cursor): resolved.** The cursor is a solid block, (208,208,211) / board (209,209,214).
  - Fit: 7.33 × 14.33 at 1.27 below the row top / board 7.0 × 13.67 at 1.72.
  - Wide: 6.33 × 13.0 at 1.11 / board 6.33 × 12.0 at 1.22.
  - A 3 s recording held only 2 frames (h264 writes frames only on change), and both read 208. The cursor does not blink.
- **D4 (extra key): resolved.**
  - App keys, in order: esc, tab, ctrl, ⌥, ↑, ↓, ←, →, |, /, ~, ⌘V, then the keyboard toggle. That is 12 keys plus the toggle, the same as the board.
- **E1 (disabled arrows): resolved.**
  - Button fill: board 44 / app 42–44.
  - Disabled chevron p98: board Forward 102 / app Back 102, app Forward 101.

## Matches verified (board / app, pt relative to the page or sheet top)

- **D header**:
  - Close: x 12–56, rel 4–48 in both. The X glyph is 9 × 9 at rel 15.67 in both. Fill 49/47.
  - Title ink: rel 11.67–24.33 in both. Centred on its column: 170.8 in the 64–278 column / 177.0 in the 64–290 column.
  - Subtitle top: rel 31.33 in both.
  - Fit/Wide track: 92 wide at rel 10–42, right inset 12 in both. Fill 49/47–48.
  - Selected segment at rel 12–40:
    - Fit: chord at rel 15.67 lies 52–84 from the track's right edge in both.
    - Wide: 8–40 from the right edge in both.
  - "Fit" label: right offset 74.67 / 74.67. "Wide" label: right inset 9.67 / 9.67. Both labels sit at rel 21.0–30.33.
- **D terminal**:
  - Text colour p90/p98: board 200/214, app 201/211. Page background 11/10.
  - First glyph at x 13.33 / 13.0.
  - 'l' top below the row top: Fit 3.19 / 3.33–3.40, Wide 2.97 / 2.89.
  - The last row ends 10.0 / 10.33 above the key row (Fit and Wide).
  - A low-threshold scan (≥2 levels) found no seam or band in the terminal area.
- **D key row**:
  - Row: 50 tall, fill 28/27.
  - Keys: 36 tall, starting 7.33 / 7.0 below the row top. Radius matches by eye at 3× (`crops/D08-D13-keys-sbs.png`). Fill 58/55–56. The first key is at x 8 in both and the gap is 6 in both.
  - Widths: arrows and ⌘V 40/40, toggle 44/44. esc 43.3/44, tab 43.3/44 and ctrl 51.7/53 follow the mono label widths (accepted). The resulting +2.7 offset at ⌘V and the toggle follows from that.
  - Scrolled to the end: right inset 8.0 / 8.0.
  - The label stem is 1.59 pt in the app vs 1.01 pt for 12 pt Regular, so the app is at the declared semibold. The board's Menlo Bold is 2.02 pt (accepted).
- **E top chrome**:
  - Sheet top: 54/62 (accepted device offset). Sheet fill 28/26.
  - Close: x 10–50, rel 13–53, X glyph 8.67 in both.
  - URL pill: rel 13–53, from x 58 to a right inset of 58 in both. Fill 44/42.
  - Host row: lock 7.67 wide at rel 22.33–31.33 in both. The lock-to-text gap is 7.33 in both. The group is centred at 195.33 in a pill centred at 195 / 201.67 in a pill centred at 201. Text baseline rel 32.0 / 31.33.
  - Subtitle: rel 37.0–47.33 / 36.33–46.67, centred 195.5 / 201.2. Orange mean (85,70,50) / (83,69,50).
  - Reload: 40 pt button with a right inset of 10 in both. Glyph 12.33 / 12.67×12.0, at the same offset.
- **E web area**: rel 64 to 92 above the screen bottom in both. The app's page content ends at 782.0 (see O5).
- **E bottom bar**:
  - Back and Forward: x 10–54 and 62–106, 34–78 above the bottom in both. Chevrons 7.33×12.67 / 7.0×12.0, at rel 17.33–26.67 inside the button in both.
  - "I'm signed in": from x 114 to a right inset of 10, 31–81 above the bottom in both (30.67 in the app). Label at 18.33–34.67 / 18.33–35.0 inside the button, centred. Fill (9,110,224) / (9,108,222).

## Observations within tolerance (not deltas)

- O1. The board bottom-anchors its mock lines. The app's live grid starts with the shell's real rows at the top and keeps the tmux status row at the bottom. Rows are whole cells, bottom-aligned.
  - Fit: 39 rows from 135.07 to 813.67 pt.
  - Wide: 45 rows from 128.54 to 813.67 pt.
  - The remainder sits above the first row (accepted).
- O2. Cursor height is +0.67 (Fit) and +1.0 (Wide). This follows from SF Mono's taller ascent plus descent.
- O3. The key row's top border is 1 device px (0.33 pt) on the board, where the CSS asks for 0.5 pt, and 3 px (1.0 pt) in the app. Both are about #2C2C2E.
- O4. At the scroll end, the leftmost partly visible key shows the "↑" arrow in the app. On the board only the blank right part of "↑" shows. This follows from the wider key labels and the wider screen.
- O5. Below the web page content, a 2 pt strip from 782.0 to 784.0 is neutral (26,26,26), while the sheet is (26,26,28). That is 2 levels in one channel, invisible at normal contrast (`crops/E-web-bottom-stretched.png`, contrast ×6). Taking the content edge at 782.0 gives 92 / 92 above the bottom. Taking 784 gives 90.

## Notes (not counted, non-visual or data)

- N1. Copy that comes from data: the D subtitle reads "Shell on Pro" / "Shell on Eugenes-MacBook-Pro", and the E subtitle "goes to Air" / "goes to Mac". E's host is example.com instead of accounts.google.com.
- N2. Accessibility, not part of the visual criteria:
  - The toggle's AX label is "Keyboard". The board labels it "Hide keyboard" or "Show keyboard".
  - The disabled Back and Forward report `enabled: true` in AX. Per the self-check, they are now blocked with `allowsHitTesting` instead of `.disabled`, so VoiceOver may announce them as active.
  - The D title is a `terminalHostMenu` pop-up button. It shows no visual affordance, which matches the board.

## Coverage gaps

- **D sticky-ctrl (blue) key state**: needs a key press, which is forbidden. Not verified.
- **D software-keyboard layout**: the simulator uses a hardware keyboard. The key row was compared in isolation.
- **E Back in its enabled state**: needs web history. The caller accepted comparing the disabled state instead.
- **E review and sent sheets**: reachable only through "I'm signed in", which is on the do-not-tap list.
- **Fit → Wide → Fit round trip**: not exercised. Fit was captured on open and Wide after the tap. I did not tap back to Fit before relaunching for E.

## Evidence

- `app/`: recordings (`.mov`) and last frames (`.png`).
- `board/`: tiles, stitched 3x renders and DOM dumps (`dom-term-*.txt`, `dom-signin-orig.txt`).
- `pairs/`: the helper output (21 native-resolution pairs, `index.json` with source and crop hashes, `review-01..02.png`). The manifest is `pairs.json`.
- `crops/`: `D08-D13-keys-sbs.png`, `D13b-toggle-board-kbopen.png`, `D13-toggle-kbclosed-kbopen-app.png`, `E-web-bottom-stretched.png`.
- `scripts/`: `probe.py` (rows, cols, bbox, edges, colour), `period.py` (cell pitch), `stem.py` (stroke width), `cursor_frames.py`, `fontadv.py`, `sbs.py`, `stitch.py`, `receiver.py`, `lib.py`.

## Timing (observed, HKT)

| Phase | Time |
|---|---|
| Preparation (scope, prior round, sources, port check) | 10:25–10:27 |
| Board render and DOM (D: 3 states and the toggle; E) | 10:27–10:34, plus the toggle tile at 10:49 |
| App capture (D Fit, 3 s cursor clip, Wide, keys at the end; E) | 10:34–10:45 |
| Comparison (probes, pairs, crops) | 10:36–10:50, interleaved |
| Report | 10:51–10:56 |

Tool failures and recoveries:
- The worktree hook rejected heredocs and shell loops. I moved the logic into script files and ran the commands one by one.
- The full-window Chrome screenshot is downscaled (1036×1156 JPEG). I used region zoom at scale 1 to get native 585×1266 PNG tiles.
- `window.close()` did not close my Chrome tab (1045567271), and no tab-close tool was available. The tab is still open.
