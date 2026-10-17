# Visual design verification, round 2 (scoped iPad + phone re-check)

**Verdict: FAIL.** Most scoped geometry matches the boards to within 1 pt: the A frames, the B/C/D reading column, the composers in B/C/D/H, the bubbles, the F selection and the G keyboard-up behaviour. Confirmed deltas remain in E (host dot colour, search and more glyph x), F (ask bar height) and G (new-session composer height). H has one unverifiable criterion (vertical anchor of the back button).

## Scope

- Live verification of the running app, components A–H only, as named by the caller. These are out of scope and not graded: glass button fills, glyph artwork, the dock surface, row text content and transcript content.
- Reference kind: `html`. Local `.dc.html` boards served by an existing loopback server at `http://127.0.0.1:8795/` (pid 44290, root `…/scratchpad/canvas-ipad/project/`). Rendered fresh in Claude in Chrome (new tab 1045567720, viewport 1800x986, DPR 1, `document.fonts.status = loaded`, no images pending). Root = the fixed div of the device size (834x1210 / 1210x834 / 390x844) at (0,0); 1 CSS px = 1 iOS pt.
- This agent built its own baseline. Four board hashes differ from round 1 (ip-launch, ip-session-portrait, ip-session, ip-task), so nothing was reused from round 1.

| Board | Source SHA-256 | Capture | Used for |
| --- | --- | --- | --- |
| ip-launch.dc.html | 084eb7ab…150c8f | design/ip-launch.png (stitched top + scrollY 224, overlap diff 0) | A portrait, E portrait Sessions |
| ip-session-portrait.dc.html | e96e48b0…2a63e6 | design/ip-session-portrait.png (stitched, overlap diff 0) | D |
| ip-session.dc.html | c33e9d58…402732 | design/ip-session.png | B; A and E landscape (no landscape launch board, so this board's sidebar is the reference) |
| ip-session-full.dc.html | e8cbb319…0f37e5 | design/ip-session-full.png | C |
| ip-new.dc.html | 34a64d0a…b2ec | design/ip-new.png | G (keyboard hidden only; no keyboard-up board) |
| ip-task.dc.html | 682ec282…332f56 | design/ip-task.png | F, E Tasks |
| s2-view.dc.html | b80f8daa…a3df | design/s2-view.png | H |
| support.js | 3f160299…0ffe0f10 | | runtime |

PNG hashes: `design/hashes.txt`. Full DOM dumps (bounds, computed font, colour, radius, border) and text-node ranges per board: `dom/<board>.txt`, `dom/<board>-text.txt`.

## Implementation

- iPad Pro 11" `A00EE23C-457D-457C-BD19-7B9239D050C0`, iOS 26.3, dark. iPhone 17 Pro `CFAD1C74-25D0-4360-B8EB-AAF335A7A86D`, dark.
- Build: LFG 1.4.0 (1), the same `LFG.debug.dylib` sha256 `d4ee72a360c24ec1…` on both simulators (iPad installed 02:15:43, iPhone 02:17:45). The iPad was relaunched twice with `flowdeck run -S <udid> --no-build`, and the hash was re-checked after each relaunch (unchanged). Nothing was rebuilt.
- Captures: `flowdeck ui simulator screen`, sRGB PNG, lossless. iPad portrait is 834x1210 px (1 px/pt). iPad landscape raw is 1210x1756 portrait-oriented. It is rotated 90° CCW to `*-rot.png` (1756x1210, 1.4512 px/pt horizontally, 1.4508 vertically; all measurements use 1.4512, max error about 0.25 pt at the bottom edge). `*-landscape.png` files are 1 pt views for viewing only. The iPhone capture is 402x874 px (1 px/pt).
- Colour validity: system colours read identically in board and app captures (row dots #30D158 (48,209,88), unread #BF5AF0 (191,90,240), card #1C1C1E). So raw RGB comparisons in the same capture family are valid.
- Units are points. "DOM" means a board computed value. "px" means ink or fill bounds measured with the same script on both images (`measure/meas.py`, `measure/textext.py`; specs `measure/*.json`, outputs `measure/*.txt`).

## Exceptions and exclusions

- No component manifest and no owner exceptions were supplied. The scope list in the request is the manifest.
- Data differences (excluded): session/task titles, transcript text, model names ("Opus · Extra high"), subagent counts, section names ("Working" vs "Needs input"), host name, missing Files/Terminal pills on the phone.
- "Session header row" in A is read as the sidebar header row (hosts · search · more). No session is open on a cold launch.
- The iPadOS window resize grip (bottom-right arc) is system chrome and ignored.

## Matrix

Criteria: 1 internal consistency, 2 structure/layout, 3 copy, 4 typography, 5 colour, 6 glyphs, 7 spacing/shape, 8 states, 9 navigation chrome. Copy, typography and glyph artwork are mostly outside this round's scope (N/A).

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A sidebar card, portrait cold launch | PASS | PASS | N/A | N/A | PASS | N/A | PASS | PASS | N/A |
| A round list button, portrait | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | PASS |
| A header row vertical position, portrait | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| A sidebar card + list button + header row, landscape cold launch | PASS | PASS | N/A | N/A | PASS | N/A | PASS | PASS | PASS |
| B transcript text extents, landscape + list | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| B composer frame | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| B pill row left edge | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| B user bubble width + right edge | PASS | PASS | N/A | N/A | PASS | N/A | PASS | N/A | N/A |
| C same as B, list hidden | PASS | PASS | N/A | N/A | PASS | N/A | PASS | N/A | N/A |
| C top-left controls | PASS | PASS | N/A | N/A | N/A | N/A | PASS | PASS | PASS |
| D composer frame, portrait + list | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| D transcript text extents | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| D top-left controls of detail | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | PASS |
| E header, Sessions, portrait + landscape | PASS | FAIL F2 | PASS | PARTIAL F3 | FAIL F1 | PASS (size) | FAIL F2 | N/A | N/A |
| E header, Tasks, portrait + landscape | PASS | FAIL F2 | PASS | PARTIAL F3 | FAIL F1 | PASS (size) | FAIL F2 | N/A | N/A |
| E Sessions vs Tasks (app) | PASS (identical) | PASS | PASS | PASS | PASS | PASS | PASS | N/A | N/A |
| F sidebar background | PASS | N/A | N/A | N/A | PASS | N/A | N/A | N/A | N/A |
| F selected row | PASS | PASS | N/A | N/A | PASS | N/A | PASS (see O3) | PASS | N/A |
| F row chevrons | PASS (none) | PASS | N/A | N/A | N/A | PASS | N/A | N/A | N/A |
| F task detail column | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| F "Ask to change this task" bar | PASS | PASS (x) | N/A | N/A | N/A (glass fill) | N/A | FAIL F4 | N/A | N/A |
| G composer, keyboard hidden | PASS | PASS (x) | N/A | N/A | N/A (see O4) | N/A | FAIL F5 | N/A | N/A |
| G composer, keyboard up | PASS | PASS | N/A | N/A | N/A | N/A | PARTIAL F6 | PASS | N/A |
| G X button + title vs status bar | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | PASS |
| H phone composer | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| H phone transcript text extents | PASS | PASS | N/A | N/A | N/A | N/A | PASS | N/A | N/A |
| H phone top-left control | PASS | PASS (x) | N/A | N/A | N/A | N/A | PARTIAL F7 | N/A | PARTIAL F7 |

## Measurements (board vs app, pt)

### A. Cold launch (portrait `app/01-launch-portrait.png`; landscape `app/05-launch-landscape-rot.png`)
- Card frame, portrait: board DOM 10,42 320x1158 (x 10–330, y 42–1200, r 26). App px: x 10–330, top 42, bottom 1200. The corner profile matches r≈26 (inset at y+1: 17.6 vs 16.1; y+4: 11.5 vs 11.5; y+6: 8.9 vs 9.1).
- Card frame, landscape: board (ip-session) 10,42 320x782. App: x 10.3–330.1, top 42.0, bottom 823.4–824.1.
- List button: board 350–394 x 42–86 (44x44). App portrait 350–394 x 42–86/87. App landscape 350.0–394.1 x 42.0–86.1.
- Header row vertical position: dot y 60–68 both. Search ink y 57–73 both (landscape 56.5–72.4). More ink y 62–66 both. "2 hosts" ink y 57–70 vs 58–70.

### B. Session, landscape with list (`app/06-session-landscape-rot.png`, bubble `app/07c-bubble-rot.png`)
- Text left edge: board text box 426 (ink 426–427) vs app ink 426.5–427.2.
- Text right edge: board wrap box 1114. The widest app lines end at 1110.1 and 1111.5, inside the box. Tool-row chevrons: 1106–1110 vs 1106.0–1110.1.
- Composer: board DOM 422,724 696x96 (x 422–1118, y 724–820) vs app 421.7–1118.4 x 723.5–820.0.
- Pill left edge: 426 vs 425.8.
- Bubble: board 606–1114 (508 wide), fill (53,92,143) vs app 606.4–1114.2 (≈508), fill (53,92,143). The right edge matches. The app bubble is at max width (multi-line), the same as the board's.

### C. Session, landscape, list hidden (`app/08-full-rot.png`)
- Text left 261 vs 261.8. Widest app lines end at 941.3–942.0, inside the 949 box. Chevrons 941–945 vs 940.6–945.4.
- Composer 257–953 x 724–820 vs 257.0–953.0 x 723.5–820.0.
- Pill left 261 vs 261.2. Bubble 441–949 vs 441.0–949.5.
- Top left: board has only the round list button at 10–54 x 42–86. The app has only the round list button, at 9.6–54.4 x 42.0–86.1. The title is centred.

### D. Session, portrait with list (`app/03-session-portrait.png`)
- Composer: board 342–822 x 1100–1196 vs app 342–822 x 1100–1196 (border rows at 1100 and 1195).
- Text left 346/347 both. Chevrons 810–814 both. Widest app line ends at 814, inside the 818 box.
- Top left of the detail area: board has only the list button at 350–394 x 42–86. The app has only the list button, at 350–394 x 42–86; the title follows at x≈409.

### E. Sidebar header (`measure/E-portrait.txt`, `measure/A-E-landscape-sessions.txt`, `measure/E-landscape-tasks.txt`)

| Item | Board | App (Sessions = Tasks, both orientations) |
| --- | --- | --- |
| Host dot x / y | 26–34 / 60–68 (ink 26–32) | 26–34 / 60–68 (ink 26.0–32.0; landscape 26.2–31.7) |
| Host dot colour | (47/48,209,88) #30D158 | **(61,222,102) ≈ #3DDE66** |
| "2 hosts" ink x | 42.0–98.0 (w 56) | 41.0–95.0 portrait, 41.3–95.1 landscape (w 54) |
| Search glyph ink | 251–267 x 57–73 (16x16), centre x 259, white | **246–262** x 57–73 (16x16), centre x 254, white |
| More glyph ink | 294–310 x 62–66 (16x4), centre x 302, white | **296–312** x 62–66 (16x4), centre x 304 (landscape 296.3–311.5), white |

- Sessions vs Tasks in the app: a pixel diff of the header (10,42 320x54) gives max channel difference 1 in portrait and 1 in landscape. The two tabs are identical. The board's two tabs are also identical (diff bbox None).

### F. Tasks tab, landscape, first task open (`app/10-task-detail-rot.png`)
- Sidebar fill: (28,28,30) both.
- Selected row: fill board (23,44,61) [DOM rgb(24,43,62)] vs app (24,44,62). x 19–321 (DOM 18–322) vs 19.3–321.1. Insets 8 / 8 both. Corner radius ≈12 both (inset 1 pt below the top edge: 6–7 vs 6.0).
- Selected height: board 350–437 = 87 vs app 134.0–220.9 = 86.9.
- Row pitch: board 88 (unselected rows; dividers at 223.5, 349.5, 524.5, 612.5) vs app 87 (dividers at 220.5, 307.3, 394.5, 481.3, 568.2, 655.3, 742.1). Board: selection = pitch − 1 (no divider under it). App: selection = pitch. See O3.
- Row chevrons: none on the board, none in the app (no ink at x 314–330 in any row).
- Detail column: next-run card 430–1110 vs 430.0–1109.4/1110.1. Title ink starts 432 vs 431.4. Runs summary right edge 1109 vs 1108.7.
- Ask bar: see F4.

### G. New session, landscape (`app/11b-new-nokbd-rot.png`, `app/11c-new-kbd-rot.png`)
- Keyboard hidden: see F5.
- Keyboard up: the composer moves to x 257–953, y ≈210.2–405.9. The keyboard top edge is at ≈406. The chips row (ink 219.8–269.4), + / model chip (ink bottom 403.8, including shadow) and send (358.3–403.8) all sit above the keyboard. There is a 0 pt gap between composer and keyboard (F6).
- X button: board 14–52 x 32–70 (38) vs app 13.8–52.4 x 31.7–70.3. Title ink: board y 43–56 vs app 44.1–57.2. The status bar ink ends at y 22.7 (time) and 22.7 (battery), so the X clears it by 9 pt and the title by 21 pt, in both keyboard states.
- Closed with X; nothing was typed or sent.

### H. iPhone session (`app/21-phone-session.png`, board 390x844, app 402x874; edge-anchored)
- Composer: board 12–378 x 720–816 → expected 12–390 x 750–846 (inset 12, bottom inset 28) vs app 12–390 x 750–846.
- Text left: 17 both (ink). Text right: chevrons board 366–370 → expected 378–382 vs app 378–382. The widest app lines end at 376, inside the expected 386 box.
- Top-left control: see F7.

## Findings

**F1. Host status dot is a lighter green than the board (E, all four header states).**
- Board (47–48,209,88), #30D158 (DOM rgb(48,209,88)) vs app (61,222,102) at the dot centre. The brightest app pixel is (62–63,230–231,105).
- Size and position match (26–34 x 60–68).
- The row status dots in the same capture read (48,209,88) exactly, so this is not a capture or profile shift.
- Crops: `crops/round2/E1…E4-*`.

**F2. Search and more glyphs are placed differently from the board (E, Sessions and Tasks, both orientations).**
- Search ink x: board 251–267 vs app 246–262 (−5 pt).
- More ink x: board 294–310 vs app 296–312 (+2 pt; landscape +2.3).
- The centre-to-centre gap is board 43 vs app 50.
- Glyph sizes (16x16, 16x4), vertical positions and white colour match.
- Crops: `crops/round2/E5-search-more-glyphs-*`, `E1…E4`.

**F3. "2 hosts" text is about 1 pt left of the board and 2 pt narrower (E, minor).**
- Ink x: board 42.0–98.0 vs app 41.0–95.0 portrait and 41.3–95.1 landscape.
- The width difference likely comes from iOS size-specific tracking. The board renders 16 px semibold in Chrome with `letter-spacing: normal`; this is a hypothesis.
- The start offset is −0.7 to −1 pt, at the measurement resolution in portrait. It is marked PARTIAL, not FAIL.

**F4. "Ask to change this task" bar is 2 pt taller than the board (F).**
- Board DOM 426,756 688x50 (x 426–1114, y 756–806, r 25).
- App x 425.8–1114.2 (matches). App y ≈755.6–807.9: border rows at 755.9–756.6 and 806.9–807.6. That is a height of about 52 and a bottom edge 2 pt lower.
- Crop: `crops/round2/F2-ask-bar-*`.

**F5. New-session composer, keyboard hidden, is about 2 pt taller than the board (G).**
- Board DOM 257,619 696x194 (y 619–813).
- App x 257.0–953.0 (matches). App top border at 617.4–618.8 and bottom border at 812.4–813.8. That gives y ≈617.7–813.8, height ≈196.
- The top edge is 1.3 pt higher, and the bottom is 0.8 pt lower (1 px at this scale).
- With the keyboard up, the app height is also ≈196 (210.2–405.9).
- Crop: `crops/round2/G1-new-composer-nokbd-*`.

**F6. Keyboard up: every control is visible, but the composer sits flush on the keyboard (G, PARTIAL).**
- The composer's bottom border (405.2–405.9) touches the keyboard top (≈406). The gap is 0 pt.
- No board defines the keyboard-up state, so the gap is unspecified, not failed.
- Crop: `crops/round2/G3-new-composer-kbd-up-*`.

**F7. Phone back button: x matches; size is about 1 pt smaller; the vertical anchor cannot be proven (H).**
- Board 16–62 x 59–105 (46x46).
- App 16–61 x 62–≈107.5 (≈45x45.5; the bottom edge is partly hidden by transcript text behind the glass).
- The left edge matches. The board has no status bar and does not state its safe area, so the y offset (board 59 on 844 vs app 62 on 874) cannot be edge-anchored. Vertical position is PARTIAL.
- Crop: `crops/round2/H2-phone-topleft-*`.

### Observations outside the graded scope (not graded)

- **O1.** The top-right settings control is a 52-wide capsule in the app: iPad 772–824 (portrait) and 1148–1200 (landscape); phone 334–386. The board shows a 44 (iPad) or 46 (phone) circle at 774–818, 1150–1194 and an edge-anchored 340–386. The right edges are within 0–6 pt.
- **O2.** The board's top fade (black to 72%, then transparent by y 124) is absent or weaker in the app. Transcript lines show directly under the title and the top-left buttons on iPad portrait (y≈86–99) and on the phone (y≈96–110). See `crops/round2/D2-*`, `H2-*`.
- **O3.** In the app, task-row dividers run x 88–330 (to the card edge). On the board they run 88–322. The app also draws a divider at the selected row's bottom edge (y≈220.6), which shows as an 8 pt stub right of the selection (x 322–330). The board has no divider under the selected row.
- **O4.** The new-session composer fill is (15,15,15) in the app vs (28,28,30) on the board, while the session composer matches (27–28). This is possibly a glass material.
- **O5.** The selected Sessions row shows a blue keyboard-focus ring (hardware keyboard connected in Simulator), as in round 1. The Sessions selection is not in this round's scope.

## Interaction checks

- The list toggle hides and restores the sidebar in landscape (raw HID touch). The New session X closes the sheet.
- Transcript scrolling: synthetic swipes moved the transcript until a user bubble was in view. The scrubber was not used.
- Software keyboard: toggled on through the Simulator menu I/O > Keyboard > Toggle Software Keyboard (a hardware keyboard is connected), captured, then toggled back once. `hide-keyboard` was also run.

## Coverage gaps

- There is no landscape cold-launch board. Landscape A and E use the ip-session and ip-task sidebars as the reference.
- There is no keyboard-up board (F6 is PARTIAL).
- The phone's vertical anchor has no stated safe area (F7 is PARTIAL).
- Transcript right extents are limited by the wrapped live text. Lines reach to within 2.5–7 pt of the box edge; chevrons and bubbles prove the right edge exactly.
- Claude in Chrome tab 1045567720 could not be closed. The available tools have no close action, and `window.close()` and Cmd+W were ignored. It still shows s2-view.

## Phase timing (observed, HKT, 2026-10-17)

| Phase | Time |
| --- | --- |
| Preparation (inputs, hashes, unlock, helper) | 02:18–02:20 |
| Design capture (7 boards, DOM dumps, 1:1 captures) | 02:20–02:27 |
| App capture + measurement, iPad portrait | 02:28–02:34 |
| App capture + measurement, iPad landscape (A, B, C, E, F, G) | 02:34–02:45 |
| Phone (H) | 02:46–02:48 |
| Crops, review, report | 02:48–02:55 |

Tool notes:
- The JS tool truncates long output, so a 15-line loopback receiver on 127.0.0.1:8797 saved the DOM dumps; it was stopped afterwards.
- The Mac auto-locked twice; `lfg-unlock unlock` recovered it each time. It was re-locked at the end.
- The caller's "rotate 270°" produced an upside-down view; 90° CCW is correct and matches the touch mapping (lx,ly) → (834−ly, lx).
- `prepare_evidence.py` needs an exact viewport × scale, so the landscape sources use ppu 1756/1210 with viewport [1210, 833.77].
- The iPad finished in portrait, Sessions tab, with the Working session open.
