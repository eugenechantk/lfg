# S2 Sessions list: design vs app verification (phase 1)

**Verdict: PARTIAL.** Rows, header labels, status dots, badges and the dock layout match the board. But one element is extra ("Load more" under the folded Closed group). One element is missing (the host on the Closed row). Every group header is 14 pt taller than on the board. The tab tint, the tab glyphs and three line-2/meta glyphs are different.

## Scope and method

- **Design:** `http://127.0.0.1:8793/s2-list.dc.html`, a 390×844 dark board. I rendered it in Claude in Chrome at DPR 1 and captured it 1:1 with `zoom [0,0,390,844]`. I read element rects and tokens from the live DOM. To see the Idle and Closed rows, I expanded them in the board, scrolled the board, and folded the top three groups.
- **App:** iOS Simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD` (iPhone 17 Pro, dark, S2 debug fixture). I captured it with `flowdeck ui simulator screen`, which gives 402×874 px, so both sides are at 1 px = 1 pt. I read frames from the FlowDeck accessibility tree. I scrolled to the bottom, expanded Idle and Closed, then folded them again and scrolled back to the top (`app-restored-top.png`).
- **How I measured:** I found ink extents by row and column scans (`inkrows`/`inkcols`) and sampled colors per pixel. Text colors on the app side are judged by hue and plateau value. The FlowDeck 1x capture is resampled, so it overshoots on glyph edges (for example, an #FF9F0A fill reads as a #FFB50B edge). Solid fills (dots, badges, surfaces) are exact.
- **Not counted as deltas (caller-approved or data):** the 402×874 vs 390×844 size, the status bar, the group counts, Unread order and the time text ("5h" vs "9:00 AM"), and model names.

## Per-component results

| # | Component (crop) | Result | Measured design vs app |
|---|---|---|---|
| 1 | Top bar left: host dots (`crops/01`) | PARTIAL | Dot 8 px #30D158, "Pro"/"Air" 25×12 and 22×13 vs 21×13, dot-to-label gap 7: same. **Left inset 16 vs 20.** |
| 2 | Top bar right: Search/••• capsule (`crops/02`) | FAIL | Capsule **98×50 (48 + border) vs 102×44**. Magnifier ink **16×16 vs 20×21**. Ellipsis dots **3 px, 5.5 apart vs 4 px, 7.5 apart**. Glyphs sit **20 pt vs 14 pt** from the capsule ends. Fill **#28282A vs #1A1A1A**. Right inset 16 in both. |
| 3 | Header: Needs input (`crops/03`) | FAIL (spacing) | Label #FF9F0A semibold. "Needs"/"input" both 45 and 36 wide. Count #8E8E93. All match. **Header-text top to first title top: 37 vs 43. Capsule bottom to header text: 24 vs 35.** |
| 4 | Header: Working (`crops/04`) | FAIL (spacing) | Label #A1A1A6, count #8E8E93: match. **Previous meta line to header text: 45 vs 50. Header to title: 36 vs 44.** |
| 5 | Header: Unread + Mark all read (`crops/05`) | FAIL (spacing) | "Mark all read" in #409CFF family, right inset 17 in both, 88 vs 85 wide: match. **Header to title: 36 vs 43.** |
| 6 | Folded headers: Idle, Closed (`crops/06`) | FAIL | Folded by default in both: match. **Header pitch 38 vs 52.** **Extra "Load more" row under folded Closed** (see D1). |
| 7 | Row: question (`crops/07`) | PARTIAL | Dot #FF9F0A 8 px at x=20, title semibold at x=41, amber line 2, meta #8E8E93, pitch 88: match. Question glyph different (D10). Monitor glyph different (D8). |
| 8 | Row: sign-in (`crops/08`) | PARTIAL | Structure, copy and colors match. **Key glyph diagonal vs upright** (D9). |
| 9 | Row: working (`crops/09`) | PARTIAL | Green dot and line #30D158, regular-weight title: match. **Live indicator and text start at x 37–50 / 52 vs 41–52 / 59** (D13). |
| 10 | Row: working + task (`crops/10`) | PARTIAL | Repeat glyph 11×11 vs 13×10, same idea: OK. Same live-indicator offset as row 9. |
| 11 | Row: unread (`crops/11`) | PASS* | Purple dot #BF5AF0, semibold title, "New reply" light ink, meta: match. *Monitor glyph (D8).* |
| 12 | Row: unread + task (`crops/12`) | PASS* | Matches apart from the time text (data) and the monitor glyph (D8). |
| 13 | Row: idle (`crops/13`) | PASS* | Dot #0A84FF, line #A1A1A6, copy: match. *Monitor glyph (D8).* |
| 14 | Row: closed (`crops/14`) | FAIL | **Meta "readwise-sync · Codex · 1d · [monitor] Air" vs "readwise-sync · Codex · 1d"**: the trailing dot, monitor and host are missing. **Dot #636366 vs #464649.** |
| 15 | Line-2 icons (`crops/15–17`) | FAIL | See D9, D10, D13. |
| 16 | Meta-line icons (`crops/18–19`) | FAIL | Monitor: **outline 11×9 vs filled display 13×11** on every row. Task glyph: OK. |
| 17 | Tab bar + badges (`crops/20`) | FAIL | Bar 186×56 vs 184×57 and pill 88×48: match. Sessions badge 18×18 #FF9F0A at the same (+50, +4) offset in the pill, dark numeral: match. **Selected tint #409CFF vs about #0091FF.** **Sessions glyph filled vs outline.** **Tasks glyph outline calendar vs filled calendar with dot grid.** **Bar #222223 vs #131313; pill #3A3A3B vs #242424.** No Tasks badge (C1). |
| 18 | Plus button (`crops/21`) | PARTIAL | 56 pt circle: match. **Fill #222223 vs #131313. Glyph 14×14 vs 18×17.** |
| 19 | Chevrons (`crops/22`) | PARTIAL | **Expanded chevron 7×5 vs 11×7.** The folded chevron is larger by the same ratio. |
| 20 | Internal consistency (all crops) | PASS | List background #000000 is uniform. The top band is a soft ramp up to #040404 with no seam, and the bottom ramp is up to #030303. Capsule, bar, pill and plus are each one flat fill. Separators are consistent (x=40 to the right edge). Header spacing is the same for every header. |
| 21 | Whole screen: scroll under the top bar (`crops/23-*`) | FAIL | The board clips the list at y=112. In the app, rows scroll under the top bar with only a soft fade, so a dimmed row title overlaps "● Pro ● Air". |
| 22 | Whole screen: dock placement | PARTIAL | **Dock left inset 16 vs 20, plus right inset 16 vs 20, bottom inset 22 vs 28.** |

## Deltas, by priority

**P1: structure and copy**
- **D1. Extra "Load more" control.** The board shows nothing below the folded "Closed" header. The app shows a full-width row there. At first it was a spinner with "Loading more" in system blue, which still showed after a 20 s wait. After one more scroll it became "Load more" with a circled chevron. The control shows while Closed is folded, so a collapsed group is offering to page. (`app-scrolled-bottom.png`, `app-scrolled-end.png`)
- **D2. The Closed row has no host.** Design meta: "readwise-sync · Codex · 1d · [monitor] Air". App meta: "readwise-sync · Codex · 1d". The accessibility label also has no host. (`crops/14`)
- **D3. Group headers are 14 pt taller.** Board header: 38 pt (14 top, 6 bottom padding). App header frame: 52 pt. Measured: about 7 pt more below each header, about 5 pt more above it, and a folded-header pitch of 38 vs 52. The gap from the top bar to the first header is 24 vs 35. By the Unread header the list has moved 38 pt down (557 vs 595; 8 pt of that is the status bar).

**P2: tokens and glyphs**
- **D4. Selected tab tint.** Board #409CFF on the icon and the "Sessions" label. App about #0091FF. "Mark all read" in the app is still the light blue, so the screen now has two blues.
- **D5. Tab glyphs.** Sessions: the board's double bubble is filled, the app's is outline. Tasks: the board has an outline calendar with a clock, the app has a solid calendar with a dot grid and a clock badge.
- **D6. Floating surfaces are darker.** Tab bar #222223 vs #131313. Selected pill #3A3A3B vs #242424. Plus #222223 vs #131313. Capsule #28282A vs #1A1A1A. The pill now stands 17 levels above the bar instead of 24. This may be native Liquid Glass sitting on black; decide whether to accept it as a native translation.
- **D7. The capsule is shorter and its glyphs larger.** 48 vs 44 pt tall. Magnifier 16 vs 20 px ink. Ellipsis dots 3 vs 4 px and wider apart. The glyphs sit 6 pt closer to the capsule ends.
- **D8. Monitor glyph.** Outline on the board (stroke 1.8, 11×9). Filled display in the app (13×11). It shows on every row.
- **D9. Key glyph.** Board: a diagonal key with the ring at lower left, 12×11. App: an upright key with the bow on top, 9×16.
- **D10. Question glyph.** Board: a square bubble with a tail at lower left, 12×11, text at x=59. App: a rounded bubble, 15×14, text at x=64.
- **D11. Closed dot color.** #636366 vs #464649.
- **D12. Content under the top bar** while scrolling (row 21 above).

**P3: minor metrics**
- **D13.** The live indicator and the "Working · Nm" text start 4 pt and 7 pt further right (indicator 41 vs 37, text 59 vs 52).
- **D14.** Header chevron 7×5 vs 11×7 (the SF chevron is heavier).
- **D15.** Side insets: host status 20 vs 16. Dock left and plus right 16 vs 20. Dock bottom 22 vs 28.
- **D16.** Plus glyph 18×17 vs 14×14.

## Confirmed correct

- Group order: Needs input, Working, Unread, Idle, Closed. Idle and Closed are folded by default, and the header tap expands and folds them.
- Header labels: Needs input in amber, the others #A1A1A6 semibold, counts #8E8E93. "Mark all read" sits right-aligned with the same inset.
- Three-line rows: 88 pt pitch. Title 17 pt, semibold for needs input and unread, regular for the rest. Line 2 is 23 pt below the title and the meta line 22–23 pt below that. Line-2 colors are amber, green, light ink and grey, and the meta is #8E8E93.
- Status dots are 8 pt at x=20, aligned to the title: #FF9F0A, #30D158, #BF5AF0, #0A84FF.
- Row copy matches the board, apart from the Closed host (D2) and data-driven times.
- Separators run from x=40 to the right edge.
- Host dots and labels match in size, color and spacing.
- Sessions badge: size, color, numeral and position match.
- Dock: bar and pill size, label centring, and a 56 pt plus button.

## Carry-overs and unverified items

- **C1. Tasks badge.** The board shows "2", the app shows none. The fixture has no task-started session that needs input (the only two are Working and Unread), so this state was not exercised.
- **C2. Search/••• accessibility.** These buttons are not in the FlowDeck accessibility tree (`find "Search"` returns nothing), and neither is the host status. This is likely a FlowDeck limit on nav-bar items. The ••• menu contents were out of scope.
- **C3. Separator color** cannot be settled at 1x. The design's 0.5 px border renders as 1 px #2C2C2F. The app reads #1C1C1D after downsampling. The geometry matches.
- **C4. Text color plateaus** carry resampling overshoot. Hue matches for every colored text, and the values are within tolerance.
- **C5. Liquid Glass refraction** was only seen, not tested: content shows faintly through the dock and the top fade.
- **Side effects:**
  - Running `flowdeck … --help` without `-S` made the session guard create and boot a separate sim, `cc-68284ba9-a8a32a13` (`82976A66-6D54-490D-A993-C3404F745133`). I did not use or delete it.
  - Chrome tab `1045566928` is still open, because no tab-close tool was available.
  - The app sim is back in its starting state.

## Files

- Full captures: `design-board.png`, `app-top.png`, `side-by-side-top.png`, `design-scrolled-all-expanded.png`, `design-idle-closed-expanded.png`, `app-scrolled-bottom.png` (Loading more), `app-scrolled-end.png` (Load more), `app-idle-closed-expanded.png`, `side-by-side-idle-closed.png`, `app-restored-top.png`
- Paired crops (design on top, app below, nearest-neighbour upscale): `crops/01` to `crops/23`
