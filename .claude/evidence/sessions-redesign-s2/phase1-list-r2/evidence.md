# S2 Sessions list: design vs app, round 2

**Verdict: PARTIAL.** Layout, vertical rhythm, header and row typography, colors, status dots, the dock geometry, the Sessions badge and the folded-group ending now match the board. Six differences remain: four glyph shapes, a 4 pt top-bar inset, and an extra "Load more" row when Closed is expanded. The board's Tasks badge is also missing in the app, but I could not tell whether that is data or a missing feature.

## Scope and method

- **Design:** `http://127.0.0.1:8793/s2-list.dc.html`, a 390×844 dark board. I rendered it in Claude in Chrome (DPR 1) and captured it 1:1 with `zoom [0,0,390,844]`. I read rects, fonts and colors from the live DOM. The board's list does not scroll. To see the lower groups I used its own header toggles:
  - Unread folded, Idle and Closed folded: `design-folded-end.png`. This is the board's "end of list" state.
  - Top three groups folded, Idle and Closed expanded: `design-idle-closed-expanded.png`.
- **App:** simulator `C47EB72F-A352-44C9-8A80-9F13D33780AD` (iPhone 17 Pro, dark, S2 fixture). Captures are FlowDeck 402×874 at 1 px = 1 pt. Frames come from the FlowDeck accessibility tree. I swiped to the end, expanded and folded Idle and Closed, and folded and unfolded Unread. I never tapped "Mark all read". The final capture (`app-restored-top.png`) matches the first one (`app-top.png`) with no pixel difference above 30 below the status bar.
- **Measurement:** ink extents come from row and column scans, and colors from per-pixel samples. The 1x capture is downsampled, so thin text reads 5–15% dimmer than its true color. Text colors are judged by hue. Solid fills are exact.
- **Accepted and not counted:** screen size and status bar, the taller top safe area (+4 pt on the list), group counts and row order, model names, native Liquid Glass fills, capsule height and glyph spacing, no host on Closed rows, and the edge fade under the top bar.
- **Not a delta, platform text rendering:** app titles are about 4% narrower ("Ship lfg 1.3.1 to TestFlight" is 200 px vs 212 px). iOS applies SF tracking at 17 pt (about −0.4 pt per character) and Chrome does not. Glyph heights, weights (ink-density ratio 4.4 semibold vs 3.4 regular on both sides) and baselines match.

## Per-component results

| # | Component | Result | Design vs app (measured) |
|---|---|---|---|
| 0 | Internal consistency (all crops) | PASS | List background #000000, with an edge-fade ramp to #030303 and no seam. Bar #131313, pill #242424, plus #131313 and capsule #1A1A1A are each one flat fill. Separators run from x=40 to the right edge on every row. Header and row pitch are the same in every group. |
| 1 | Top bar left, host dots (`crops/01`) | PARTIAL | Dot 8 pt #30D158, "Pro" 25 px and "Air" 21–22 px wide, dot-to-label gap 7, Pro-to-dot gap 13 vs 12: all match. **Left inset 16 vs 20.** On the board the host dot sits 4 pt left of the row dots (16 vs 20). In the app the two line up. |
| 2 | Top bar right, Search/••• capsule (`crops/02`) | PASS (accepted native) | Right inset 16 on both sides. The capsule height, fill and glyph spacing are accepted. Note: the magnifier ink is **16×16 vs 22×21**. |
| 3 | Header: Needs input (`crops/03`) | PASS | Label #FF9F0A semibold at x=42, count #8E8E93 at x 139 vs 136. Header 38 pt in both. Text top is 16 vs 17 below the header top. Header-to-title 37 vs 36. Gap from the capsule to the header matches once the +4 pt safe area is removed. |
| 4 | Header: Working (`crops/04`) | PASS | Label #A1A1A6 semibold. Previous meta line to header text: 44 vs 43. Header to title: 37 vs 37. |
| 5 | Header: Unread + Mark all read (`crops/05`) | PASS | "Mark all read" #409CFF hue, 89 vs 87 px wide, right inset 17 on both. When Unread is folded, "Mark all read" hides in both (`app-unread-folded.png`). |
| 6 | Folded headers: Idle, Closed (`crops/06`, `crops/22`) | PASS | Pitch 38 vs 38. Folded chevron 5×9 vs 6×10 at x=24. Label at x=42, text top 17 below the header top in both. |
| 7 | Row: question (`crops/07`) | PARTIAL | Dot #FF9F0A, 8 pt at x=20. Title semibold at x=41. Line 2 amber, meta #8E8E93. Title → line 2 → meta: 23 / 22 vs 24 / 22. **Glyph: square bubble with a tail at lower left (12×11) vs rounded bubble (14×13).** Text starts at x 59 vs 62. |
| 8 | Row: sign-in (`crops/08`) | PARTIAL | Structure, copy and colors match. **Key glyph is reversed: the board's ring is at lower left and the shaft points up-right. The app's bow is at upper right and the shaft points down-left.** Ink is 12×11 vs 13×13. Text starts at x 60 vs 64. |
| 9 | Row: working (`crops/09`) | PASS | Live indicator x 37–50 in both, with a #0C34–#0C36 halo. "Working · 3m" #30D158 at x 52 vs 53. Regular-weight title. |
| 10 | Row: working + task (`crops/10`) | PASS | Repeat glyph 11×11 vs 13×10, same shape. Meta text at x 59 vs 61. |
| 11 | Row: unread (`crops/11`) | PASS* | Dot #BF5AF0, semibold title, "New reply" #D1D1D6. *Monitor glyph, see row 16.* |
| 12 | Row: unread + task (`crops/12`) | PASS* | The same as row 11 plus the repeat glyph. The time text differs ("9:00 AM" vs "5h"), which is data. |
| 13 | Row: idle (`crops/13`) | PASS* | Dot #0A84FF, "Ready for your next message" #A1A1A6, meta matches. |
| 14 | Row: closed (`crops/14`) | PASS | Dot **#636366 in both** (fixed since round 1). Line 2 and meta match. The missing host is accepted. |
| 15 | Line-2 icons (`crops/15`) | PARTIAL | The live dot matches. The question and key glyphs differ (rows 7 and 8). |
| 16 | Meta-line icons (`crops/15`) | PARTIAL | Repeat: OK. **Monitor: an outline with a black screen (stroke 1.8, 11×10 ink) vs a filled screen. The app's screen interior is #1F–#23 inside a #8E-level frame, 13×11 ink.** It shows on every row that has a host. |
| 17 | Tab bar + badges (`crops/20`, `crops/19`) | PARTIAL | Bar at left 20 / bottom 28 in both, pill 88×48. Selected tint **#409CFF in both** (fixed). The Sessions glyph is a filled double bubble in both, 24×20 vs 27×22. Sessions badge 18×18 #FF9F0A at pill offset (+50, +4) in both. **Tasks glyph: an outline calendar with two rings and a clock (stroke) vs a solid calendar with a dot grid and a clock badge.** **Tasks badge: "2" on the board, none in the app** (see C1). The fills are accepted native glass. |
| 18 | Plus button (`crops/21`) | PASS | 56 pt circle at right 20 / bottom 28 in both. Glyph 16×16 vs 15×14. The fill is accepted. |
| 19 | Expanded chevron (`crops/23`) | PASS | 9×5 vs 9–10×6 (fixed since round 1). |
| 20 | Below the folded groups, end of list (`crops/16`) | PASS | Nothing below "Closed" on either side. The app list ends with the Closed header, then the dock. There is no "Load more" or spinner. |
| 21 | Below an expanded Closed group (`crops/17`) | FAIL (extra element) | Board: nothing under the Closed row. App: a 50 pt "Load more" row with a circled-chevron glyph, colored about #0088EF (system blue). In the same capture, "Mark all read" (#409CFF) reads #3B8FEA. |
| 22 | Whole screen: scroll under the top bar (`crops/18`) | PASS (accepted) | Rows fade under the top bar. This is the accepted edge fade. |
| 23 | Whole screen: list end against the dock | NOTE | When scrolled to the end, the last header ("Closed") sits 8 pt above the dock. The bottom fade dims it to a #959599 peak, where "Idle" peaks at #B4B4BA. The board's list never reaches the dock, so this has no design reference. |

## Deltas, by priority

**P2: visible on the default screen, or an extra element**

1. **Tasks tab glyph.** Board: an outline calendar (stroke 1.8) with two binder rings and an outline clock. App: a solid white calendar with a dot grid and a filled clock badge. It shows on every screen with the dock.
2. **Tasks badge missing.** The board shows an amber "2" on Tasks at the same offset as the Sessions badge. The app shows none. This may be fixture data (C1).
3. **"Load more" under an expanded Closed group.** The board has nothing there. The app adds a system-blue row that is not the board's #409CFF accent, so the screen shows two blues. When Closed is folded, nothing shows, which matches the board. The board shows 1 of 40 closed rows and does not design pagination. Accept it, restyle it to #409CFF, or remove it.

**P3: glyphs and small metrics**

4. **Monitor glyph** on every meta line: an outline with an empty screen vs a filled screen (#1F–#23 interior), 11×10 vs 13×11.
5. **Key glyph reversed:** ring at lower left vs bow at upper right.
6. **Question glyph:** square bubble vs rounded bubble, 12×11 vs 14×13.
7. **Line-2 text offset after an icon:** question text at x 59 vs 62, sign-in at 60 vs 64. The app's icon slot is about 3 pt wider.
8. **Host-status left inset:** 16 vs 20.
9. **Magnifier in the capsule:** 16×16 vs 22×21 ink. This is likely covered by the native-capsule acceptance. It is listed only because glyph size was not named in that acceptance.

## Fixed since round 1 (re-measured)

- Group headers are 38 pt. Header-to-title and meta-to-header gaps match within 1 pt.
- No "Load more" or "Loading more" under the folded Closed group.
- Selected tab tint is #409CFF.
- The Sessions tab glyph is filled.
- The Closed dot is #636366.
- The live indicator and "Working" text are at x 37 / 52–53, as on the board.
- The header chevron is 9×5.
- Dock and plus insets are 20 / 28.

## Carry-overs and unverified

- **C1. Tasks badge.** The fixture holds sessions only. Neither task-started session needs input, so I could not reach a state that should light the Tasks badge. I cannot tell whether the badge is implemented.
- **C2. Overlapping hit areas.** After I folded and unfolded Unread, the accessibility frame of the "Unread, 3" header became [20,556,366×18]. That covers "Mark all read" [297,556,88×18]. Before, it was [20,556,269×18]. I did not test which control takes a tap there, because tapping "Mark all read" would change the fixture.
- **C3. Separator weight.** On the board, the 0.5 px #2C2C2E border renders as 1 px #2C2C2F. In the app it reads #1C1C1D at 1x after downsampling. The geometry matches, but the color cannot be settled at this resolution.
- **C4. Text colors** are attenuated by downsampling. Every hue matches.
- **Side effects:** none on the simulator; the app is back at the top with its starting state. Chrome tab `1045566935` is still open, because no tab-close tool was available to this agent. The board in that tab is left with toggled groups.

## Files

- Full captures: `design-board.png`, `design-folded-end.png`, `design-idle-closed-expanded.png`, `app-top.png`, `app-scrolled-mid.png`, `app-scrolled-bottom.png`, `app-unread-folded.png`, `app-idle-closed-expanded.png`, `app-restored-top.png`
- Side by side: `side-by-side-top.png`, `side-by-side-folded.png`, `side-by-side-idle-closed.png`
- Paired crops (design on top, app below, nearest-neighbour upscale): `crops/01` to `crops/23`
