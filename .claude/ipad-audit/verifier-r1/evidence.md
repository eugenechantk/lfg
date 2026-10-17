# Visual design verification, round 1 (iPad layout pass)

Verdict: **FAIL** (confirmed in-scope mismatches in every board state; the centered reading column, composer widths and user-bubble width pass).

## Scope

- Live verification of the running lfg iOS app against 8 HTML boards. Text content, counts, titles and times are live data and are excluded; their layout consequences are checked.
- Reference kind: `html` (local `.dc.html` boards, rendered with Claude in Chrome, viewport 1800x986, DPR 1, fonts `loaded`). Root element is the 834/1210/390-px fixed div at (0,0). Boards captured 1:1 with the zoom capture (portrait boards are two captures stitched at scrollY 224).
- Board server: `http://127.0.0.1:8795/` (python http.server, pid 44290), serving `…/scratchpad/canvas-ipad/project/`.

| Board | Source SHA-256 (html) | Captured PNG | State |
| --- | --- | --- | --- |
| ip-launch | 990cbef9…8c4ebd | design/ip-launch.png | 1 |
| ip-session-portrait | 3bacbde5…2cf8 | design/ip-session-portrait.png | 2 |
| ip-session | fdb25841…4ece | design/ip-session.png | 3 |
| ip-session-full | e8cbb319…37e5 | design/ip-session-full.png | 4 |
| ip-new | 34a64d0a…b2ec | design/ip-new.png | 5 |
| ip-task | 113d9277…80b52f | design/ip-task.png | 6 |
| s2-list / s2-view | 8183c3c7…55e83 / b80f8daa…a3df | design/s2-list.png, design/s2-view.png | 7 |
| support.js | 3f160299…0ffe0f10 | | |

PNG hashes: `design/hashes.txt`. DOM values were read per state (bounds, font size/weight, colours, radii) and are quoted in findings as "DOM".

## Implementation

- iPad Pro 11" sim `A00EE23C-457D-457C-BD19-7B9239D050C0`, iOS 26.3, dark. LFG 1.4.0 (1), binary mtime 2026-10-17 01:21:54, LFG.debug.dylib sha256 a84bb0f202344761…. Relaunched with `flowdeck run -S <udid> --no-build` (no rebuild).
- iPhone 17 Pro sim `CFAD1C74-25D0-4360-B8EB-AAF335A7A86D`: LFG 1.4.0 (1), binary mtime **01:08:31 (an older build than the iPad's 01:21:54)**, sha256 bfed9474599eb269…. Phone results cover that installed build only.
- Captures: `flowdeck ui simulator screen`, sRGB. Portrait 834x1210 px (1 px/pt). Landscape raw 1210x1756 px, rotated (`*-rot.png`, 1.451 px/pt, used for all landscape measurements) and a 1 pt view (`*-landscape.png`, viewing only). iPhone 402x874 px (1 px/pt).
- System colours read identically in app and board (#30D158 green, #BF5AF0 purple), so raw RGB comparisons are valid.
- Units: points. "px-measured" = ink/fill bounds from the capture; "DOM" = board computed value; "AX" = app accessibility frame.

## Exceptions and exclusions

- No component manifest and no documented owner exceptions for native controls. `.claude/feature/ipad-layout.md` was read for scope only. Glass/native deltas are reported as findings; they become exceptions only if the owner accepts them.
- Data exclusions: titles, message text, counts, times, host name ("Eugenes-MacBook-Pro" vs "Pro"), model names, Needs-input section absent (no live session needs input), tab badges absent, subagent ring progress, "Files"/"Terminal" pills absent on the phone (no files in that session; not proven).
- iPadOS 26 window resize grip (bottom-right arc) is system chrome, ignored.

## Matrix

Criteria: 1 internal consistency, 2 structure/layout, 3 copy, 4 typography, 5 colour, 6 glyphs, 7 spacing/shape, 8 states, 9 navigation chrome.

| Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 sidebar panel (frame, fill) | PASS | PASS | N/A | N/A | PASS | N/A | PASS | PASS | N/A |
| S1 sidebar header | FAIL F1 | FAIL F1 | PASS | PASS | PASS | FAIL F1 | FAIL F1 | N/A | N/A |
| S1 section headers | PASS | PASS | PASS | PARTIAL F17 | PASS | PASS | PASS | PASS | N/A |
| S1 Working row | PASS | PASS | data | PASS | PASS | PASS | PASS (row 87 vs 88) | PASS | N/A |
| S1 Unread row | FAIL F2 | FAIL F2 | FAIL F2 | PASS | PASS | PASS | FAIL F2 | FAIL F2 | N/A |
| S1 row dividers | PASS | FAIL F9 | N/A | N/A | PASS | N/A | FAIL F9 | N/A | N/A |
| S1 bottom dock + New | FAIL F4 | FAIL F4 | PASS | PASS | FAIL F4 | PASS | FAIL F4 | PASS | FAIL F4 |
| S1 list toggle button | PASS | PASS | N/A | N/A | FAIL F3 | FAIL F3 | PASS | N/A | FAIL F3 |
| S1 empty state | PASS | FAIL F5 | PASS | FAIL F5 | PASS | FAIL F5 | FAIL F5 | PASS | N/A |
| S1 cold launch position (portrait) | PASS | PASS | N/A | N/A | N/A | N/A | PASS | PASS | PASS |
| S2 top bar (title, buttons) | FAIL F6 | PASS | PASS | PASS | FAIL F3 | FAIL F3 | FAIL F3 | PARTIAL F6 | FAIL F3 |
| S2 selected sidebar row | FAIL F7 | FAIL F7 | data | PASS | PASS | N/A | PASS | FAIL F7 | N/A |
| S2 transcript text + tool rows | PASS | PASS | data | PASS | PASS | PASS | PASS | PASS | N/A |
| S2 subagents pill | PASS | PASS | PASS | PASS | FAIL F8 | data | FAIL F8 | PASS | N/A |
| S2 composer | PASS | PASS | PASS | PASS | PARTIAL F8 | PASS | PASS | PASS | N/A |
| S3 reading column (text, composer) | PASS | PASS | data | PASS | PASS | PASS | PASS | PASS | N/A |
| S3 user bubble | PASS | PASS | data | PASS | PASS | N/A | PASS | PASS | N/A |
| S3 top bar | FAIL F6 | FAIL F10 | PASS | PASS | FAIL F3 | FAIL F3 | FAIL F3 | PARTIAL F6 | FAIL F3 |
| S3 pill / dock / sidebar | as S1/S2 | FAIL F4 | PASS | PASS | FAIL F4 F8 | PASS | FAIL F4 F8 | PASS | FAIL F4 |
| S4 column, bubble, composer | PASS | PASS | data | PASS | PASS | PASS | PASS | PASS | N/A |
| S4 top bar (show-list, title) | FAIL F6 | PASS | PASS | PASS | FAIL F3 | FAIL F3 | PASS | PARTIAL F6 | FAIL F3 |
| S5 header (close, title) | PASS | PASS | PASS | FAIL F11 | FAIL F3 | PASS | PASS | N/A | FAIL F3 |
| S5 empty state | PASS | PASS | PASS | FAIL F11 | FAIL F11 | FAIL F11 | PASS | PASS | N/A |
| S5 composer, keyboard down | PASS | PASS | PASS | FAIL F12 | FAIL F12 | FAIL F12 | FAIL F12 | FAIL F12 (send looks enabled) | N/A |
| S5 composer, keyboard up | PASS (controls visible) | PASS | PASS | as above | as above | as above | PARTIAL F13 | PASS | N/A |
| S6 Tasks sidebar header | FAIL F14 | FAIL F14 | PASS | PASS | PASS | FAIL F14 | FAIL F14 | N/A | N/A |
| S6 Tasks sidebar rows/selection | PASS | FAIL F9 F15 | FAIL F15 | PARTIAL F15 | PASS | PASS | FAIL F15 | PASS | N/A |
| S6 title, schedule, chips | PASS | FAIL F16 | data | PASS | PASS | FAIL F16 | PASS | PASS | N/A |
| S6 next-run card + buttons | PASS | FAIL F16 | PASS | FAIL F16 | PASS | FAIL F16 | FAIL F16 | PASS | N/A |
| S6 instructions + runs | PASS | PASS | data | PASS | PASS | PASS | PASS | PASS | N/A |
| S6 ask bar | PASS | PASS | PASS | PASS | FAIL F8 | PASS | PASS | PASS | N/A |
| S6 top-right capsule | PASS | PASS | N/A | N/A | FAIL F3 | FAIL F3 | PASS | N/A | FAIL F3 |
| S1b landscape cold launch | PASS | PASS | N/A | N/A | N/A | N/A | PASS | PASS | PASS |
| P list header | PASS | FAIL F18 | PARTIAL F18 | PASS | FAIL F3 | PASS | FAIL F18 | N/A | N/A |
| P list rows (Working, Unread) | FAIL F2 | FAIL F2 | FAIL F2 | PASS | PASS | PASS | PASS | FAIL F2 | N/A |
| P dock | PASS | PASS | PASS | PASS | FAIL F4 | PASS | PASS | PASS | FAIL F4 |
| P session top bar | FAIL F6 | PASS | data | PASS | FAIL F3 | FAIL F3 | FAIL F3 | PARTIAL F6 | FAIL F3 |
| P session pill + composer | PASS | PASS | PASS | PASS | FAIL F8 | data | PASS | PASS | N/A |

## Findings (numbered, measured)

**F1. Sessions sidebar header is shifted left; the status dot sits on the panel edge.** All states with the Sessions sidebar (S1-S4, portrait and landscape).
- Dot: design x 26-33 vs app x 12-18 (px-measured; panel starts at x 10, so the dot is ~2pt inside the edge, clipped by the 26pt corner region visually).
- "2 hosts" text: design x 42 vs app x 25 (-17pt).
- Search glyph: design 251-266 vs app 246-261 (-5pt). More glyph: design 294-309 vs app 296-311 (+2pt).
- Crops: `crops/round1/s1-header-*.png`, `crops/_tmp-header.png`.

**F2. Unread rows drop the status line ("New reply").** iPad S1-S3 and phone list.
- Design: 3 lines (title 17/22 semibold, status 15/20 #D1D1D6, meta 13/18) in an 88pt row (DOM).
- App: 2 lines (title, meta), vertically centred in an 87pt row; title ink top 26pt below row top vs 15pt in the design (px-measured), leaving a visibly hollow row next to the 3-line Working rows.
- Crops: `s1-row-unread-*.png`, `p-list-unread-row-*.png`.

**F3. Glass buttons are darker, and their glyphs are larger, than the board's.** List toggle, session-tools button, Close (New), task edit/more capsule, phone back/tools, phone header capsule.
- Fill: design #28282A (DOM #2C2C2E @0.92) vs app #131313 (list toggle), #1A1A1A (tools), #191919 (Close, task capsule) (px-measured).
- List-toggle glyph: design 18x16 vs app 25-26 x 19-20 (px-measured, portrait and landscape).
- Session-tools button: design 44x44 at 774-818 (portrait) / 1150-1194 (landscape) vs app 52x44 at 772-823 / 1148-1200 (+8pt wider, right inset 16 -> 10).
- Phone: back 46x46 vs app 44 wide; tools 46 vs 52 wide (334-385); header search/more capsule 98x50 vs app 97x45.
- Task top-right capsule: geometry matches (1101-1199 x 42-85 vs 1102-1200 x 42-88) but the pencil glyph is larger and diagonal.
- Hypothesis: native iOS 26 glass buttons replacing the board's drawn discs. No owner exception documented.

**F4. Bottom dock (Sessions/Tasks + New) sits 5-6pt higher and has no visible surface.** iPad portrait and landscape; phone (geometry OK, colour only).
- iPad position: selected pill design y 1134-1182 vs app 1128-1176 (AX, -6pt); plus glyph 1150-1163 vs 1145-1158 (-5pt); landscape plus glyph 774-787 vs 769-782 (-5pt). New button 58x58 vs AX 56x56.
- Surface: design fill #252526 with #3F3F40 rim (top and bottom) vs app #1E1E1F-#1F1F20 with no rim (px-measured, iPad); phone #222223/#3E3E3F vs app #131313/#222222.
- List text behind the dock stays legible ("m refinem…", meta line), so the dock reads as floating labels.
- Crops: `s1-dock-*.png`, `s3-dock-*.png`, `p-dock-*.png`, `crops/_tmp-dock.png`.

**F5. Detail empty state ("No session selected") is 36-39pt low and uses different type and glyph.** Portrait launch.
- Icon: design 36x40 at y 537-576 vs app 44x54 at y 575-628.
- Title: design ink 218 wide at y 612 (DOM 22/28 bold) vs app 202 wide at y 651 (+39pt, ~8% narrower).
- Subtitle: design 327 wide at y 644 vs app 316 wide at y 680 (+36pt).
- Icon-to-title gap: 36 vs 23pt. Title-to-subtitle: 32 vs 29pt. Group centre y 597.5 vs 634.
- Crop: `s1-empty-state-*.png`.

**F6. Scrolled transcript stays legible under the top bar.** Session view on iPad (portrait, landscape, list hidden) and phone.
- Transcript lines and the user bubble show through behind the title, subtitle and buttons at y 30-100, e.g. bubble text overlapping "Working · 1h 32m" (`app/03g-bubble.png`, `app/04-session-full.png`, `app/09-iphone-current.png`).
- The boards depict an unscrolled transcript with a clean black bar, so the expected scroll-edge treatment is not specified (criterion 8 PARTIAL). The overlap is still an internal-consistency defect.
- The same bleed appears between the subagents pill and the composer, and below the composer (`app/03f-scroll.png`).

**F7. Selected sidebar row carries an extra 3pt blue square ring.** S2-S3.
- Selection fill matches: design 18-322 x 350-437 #172C3D vs app 18-321 #182C3E.
- App adds a #0095FF ring 3pt thick, square corners, x 10-12 and 327-329, y 221-224 and 306-308, edge-to-edge across the panel. The board has none.
- Hypothesis: the iPadOS keyboard-focus ring, because the Simulator has a hardware keyboard connected. Not tested with the keyboard disconnected.

**F8. Secondary surfaces are darker than the board.**
- Subagents pill: fill design #1C1C1E vs app #0E0E0E; rim #38383A vs #1E1E1E-#1F1F1F. Geometry: design 426-696 x 676-713 vs app 426-688 x 678-713 (36 tall vs 38; the width difference follows the text).
- Ask bar (task): fill #1C1C1E vs #131313; rim #38383A vs #232323.
- Session composer: fill matches (#1C1C1E). Rim #38383A vs #242426-#252527 (PARTIAL: could be a 0.5pt hairline at capture resolution).

**F9. Sidebar hairlines run to the panel edge.**
- Sessions: design x 50-321 vs app 50-327 (+6pt).
- Tasks: design 88-321 vs app 88-329 (+8pt).
- Colour matches (blended hairline).

**F10. Landscape session title is off-centre.** List shown.
- Title and subtitle ink centre x 774.6 vs design 770 (+4.6pt).
- List hidden: 604.4 vs 605 (PASS). Portrait: 582.5 vs 582 (PASS).

**F11. New-session header and empty state type is about 1pt smaller, and the sparkle differs.**
- "New session": 97 wide vs 102.
- "Describe a task to start": 182 vs 193 (DOM 17/22 semibold; app ≈16pt).
- Subtitle: 272 vs 283.
- Sparkle: 46x40 vs 37x34, colour #FF9F45 vs #FF9F0A (px-measured, sRGB).
- Close button fill: #191919 vs #303031.

**F12. New-session composer surface and bottom row differ.** Keyboard down; geometry 257-952 x 618-813 matches the board's 257-952 x 619-812.
- Fills: composer #0F0F0F vs #1C1C1E; chips and + #1B1B1B vs #2C2C2E; rim #292929 (~0.7pt) vs 1px #38383A.
- + control: design 44x44 circle at 274-318 x 756-800 vs app 50x39 capsule at 273-323 x 762-801.
- Model chip: 328-489 x 762-794 vs 337-458 x 766-797 (x +9, y +4).
- Send: design 34x34 at 904-938 x 761-795 with grey arrow #8E8E93 (empty = disabled) vs app 32x32 at 905-937 x 766-798 with a near-white arrow (#E2E2E2), so it reads as enabled while empty.
- Host chip label: regular weight, grey, vs design 15 semibold #F2F2F7.
- Crops: `s5-composer-*.png`, `crops/_tmp-newcomposer.png`, `crops/_tmp-newbottom.png`.

**F13. Keyboard up: every composer control is fully visible.** The composer's bottom edge is flush with the keyboard.
- + (354-394), model chip and send (358-390) all sit above the keyboard top at y ≈405.5.
- The composer's bottom rim coincides with the keyboard top edge (0-1pt gap), so there is no breathing room. No board covers this state (PARTIAL).
- Evidence: `app/05b-new-keyboard-up.png`, `crops/_tmp-kbd.png`.

**F14. Tasks sidebar header differs from both the board and the Sessions header.**
- Dot: x 14-21 vs 26-33. Text: x 29 vs 42.
- Search glyph: 22 wide at 236-257 vs 16 wide at 251-266.
- More dots: 292-311 (8pt pitch) vs 294-309 (6pt pitch).
- So the header changes when the user switches tabs.

**F15. Tasks sidebar selection and section header.**
- Selection fill: 82 tall (137-219) vs 87 (350-437), so it no longer fills the 87-88pt row pitch.
- Time label: 13pt cap vs 14.
- Extra right-aligned "by next run" label in the section header (not on the board).

**F16. Task detail.**
- Chips carry icons (monitor, Codex logo, folder); the board's chips are text only.
- Next-run card: 152 tall vs 158. The gap from the date line to the buttons is 14 vs 18.
- Run now / Pause: y 313-357 vs 318-362 (-5pt).
- Labels narrower: "Run now" 80 vs 87; Pause 61 vs 64 (≈16pt vs 17).
- Title block: 3pt higher (110 vs 113).
- Unchanged and passing: column 430-1110, card 431-1109, ask bar 426-1113 x 756-807.

**F17. "Mark all read" is 86pt wide vs 89.** Minor; the section-header labels match exactly.

**F18. Phone list header.**
- The board shows per-host chips ("● Pro ● Air"); the app shows "● 2 hosts". This may be a data or format difference; owner to confirm.
- The search/more capsule is 45pt tall vs 50.
- Device size differs (board 390x844, sim 402x874), so absolute y offsets are not compared. Right/bottom-anchored items match: composer 12pt insets and 28pt bottom; stop button 23-24pt from the right edge; dock and + exactly 50pt from the bottom.

## Passing measurements (main goals of the pass)

- Reading column, list shown (landscape): composer 421.8-1117.2 x 723.6-820.1 vs 422-1118 x 724-820. Text 426-1112. Tool-row chevrons at 1107.
- List hidden: composer 257.1-953.1 vs 257-953; text 261.9-942.1 vs 262-942.
- **User bubble width:** list shown 606.5-1113.7 (507.2 wide) vs 606-1114 (508). Text inset 620.9 vs 620; line pitch 22.05 vs 22; fill #355C8F matches. List hidden 441.8-949.0 vs 441-949.
- Portrait column 346-818 text and 342-822 composer match the board. Composer interior (attach, model pill, stop) within ±1pt.
- List toggle in two columns: one button only (no back chevron), 350-394 x 42-86. List hidden: 9.6-54.4 x 42-86.
- **Cold launch position:** portrait panel 10-329 x 42-1199, toggle 350-393 x 42-86, header ink 57-72. Landscape panel 9.6-330 x 42-824, toggle 350.1-394.2 x 42-86, header 56.5-71.7. Neither launch starts lower than the board, and a second timed portrait launch matched.

## Whole-screen and interaction checks

- Hide/show list button toggled the sidebar both ways (raw HID touch). The column stayed centred (S3 to S4).
- Synthetic taps on the right-edge user-message scrubber (slider at 1166,96,44,738) did not move the transcript, with either coordinate mapping. A bubble was reached by swiping instead. The scrubber is unverified, not failed.
- New session opened from + and closed with X. Keyboard shown by toggling Simulator's software keyboard (hardware keyboard connected), then toggled back; `hide-keyboard` was run.
- The Tasks tab opened and its first task was selected. No Run now / Pause / composer input was used.
- Tool note: in landscape, `tap --point`, `swipe` and `touch` all take portrait coordinates.

## Coverage gaps

- No board for the landscape cold launch, scrolled transcript, keyboard-up composer or the scrubber. These are judged on internal consistency only.
- The phone was checked on the older 01:08 build. Whether its deltas are regressions needs a pre-change capture; F2, F3, F6 and F8 also appear on iPad, so they are likely shared.
- F7 (focus ring) was not re-tested with the hardware keyboard disconnected.

## Timing (observed wall clock, HKT)

| Phase | Time |
| --- | --- |
| Preparation (inputs, helpers, server check) | 01:25-01:27 |
| Design capture + DOM (all 8 boards) | 01:27-01:31, 01:36-01:43 |
| App capture (iPad portrait, landscape, phone) | 01:29-02:02 (interleaved) |
| Comparison (pixel/DOM measurement, crops) | 01:31-02:05 (interleaved) |
| Report | 02:05-02:10 |

Tool notes, once each: the Chrome JS tool truncates output near 1.3k chars, so DOM was read in slices. The Mac auto-locked once mid-run; it was re-unlocked with `lfg-unlock`, then re-locked at the end. The iPad was rotated back to portrait.

## Files

- Board captures: `design/`. App captures: `app/` (`*-raw.png` original, `*-rot.png` measured, `*.png` 1pt view). Trees: `app/*.tree.json`.
- Pair crops: `crops/round1/` (`index.json` holds source and crop hashes and pixel boxes; `review-0N.png` sheets are for browsing only). Magnified side-by-sides: `crops/_tmp-*.png`. Manifest: `manifest/pairs.json`.
