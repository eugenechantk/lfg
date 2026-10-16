# Task view Runs section and model chips: round 3 re-verification (phone and Mac)

**Verdict: PASS** for the declared scope:
- every component in the round-1/round-2 table
- the Mac toggle alignment, judged against the corrected Mac board
- the items newly brought into scope: the phone bottom fade and the strip below the Ask bar, and three Mac items (instruction body colour, the card's "NEXT RUN" label, the page inset)

The Mac is verified at 1x, which is the only scale the sanctioned `mac_shot.sh` harness renders. Section 5 lists observations outside the scope; none were changed this round.

## Contents
1. Scope, references and method
2. Results per component
3. Newly in-scope items
4. Deltas from earlier rounds: status
5. Observations (outside scope, not counted)
6. Interaction checks
7. Coverage limits
8. Files and timing

## 1. Scope, references and method

**References.**
- **`dA2-runs-rail.dc.html` changed.** New SHA-256 d2ace4c9a8a33da9084920378981e63cbe70fcdbd868249227204253c4a3cee1, edited 00:10, +14 bytes. The only change is `min-width: 0` on the toggle's rail column.
  - I re-rendered it fresh in Chrome (DPR 1). Captures are native 1x, plus 3x at zoom 3 for the Runs section and for the top of the page.
  - New DOM values:
    - toggle column 14px wide
    - disc at x 17–33, centred on the rail (24–26)
    - toggle label at x 44, the same as the run text (44)
    - instruction body `#E4E5EA` 14/20
    - "NEXT RUN" label 11px/700 `#8A8A93`, letter-spacing 0.44px
    - card subtitle 13px `#A8A8B0`
    - chips start at x 18
- **The other boards are unchanged.** `tA2d-runs-rail` e4c35646…, `-open` 97aa8b2f…, `tA2d-model-pill` 64e08c47…, `support.js` and both SVGs. Their round-1 renders are reused.

**Implementation.**
- **Phone:** simulator 1D902A87-40EB-40AF-87A6-BBC19508900B, a new build found on "V long history", scrolled down.
- **Mac:** bundle binary dated 00:13:01. Shots for tasks 45 (height 1000), 07 and 03, converted to sRGB.
- **Hosts:** 8932 and 8933 have unchanged PIDs. I made no host changes; dates shifted by a day, which is data.

**Capture:**
- Phone: 3x `flowdeck … record` frames for geometry, and 1x FlowDeck PNGs for colour and for the fade profile (lossless).
- Mac: 1x sRGB, compared with the board's own 1x render as well as its 3x render.
- Phone alignment offsets, the same as round 2: 138.33pt (folded and upcoming opened), 434pt (past opened), 906pt (bottom of the past list).
- Mac: the Runs block sits 2pt higher than the board. The horizontal offset is now 0.

## 2. Results per component

All values below were measured fresh this round.

| # | Component / state | Result | Key measurements (board vs app) |
|---|---|---|---|
| 1 | Phone · Runs header + count | PASS | "Runs" 15/600, ink x 21.33, cap 403.67 = board 541.67 − 138.33. Colour 160–161 vs #A1A1A6 (161). Count right edge 380.67 (content edge) |
| 2 | Phone · upcoming toggle, folded | PASS | "Show more" (65,155,255) vs #409CFF. "8 later" 161. Disc (28,28,30) 18pt. Chevron 7.3×4.7pt. Dash stubs 4pt dashes / 0.67pt gaps with every edge within 0.33pt |
| 3 | Phone · upcoming toggle, opened | PASS | "Show less", no count, no rail above the disc, chevron down. Label x 48.67 and colour as above |
| 4 | Phone · upcoming run rows (2 / 10) | PASS | 37pt pitch. Hollow ring 12pt, ring 96–102 vs #636366, black centre. Heads 161 |
| 5 | Phone · past rows, completed (2 / 12) | PASS | 59pt pitch. Green (47,209,88) vs #30D158. Heads 255, body 209, tails 161 |
| 6 | Phone · past row, failed | PASS | Node and reason (255,69,58) = #FF453A (1x). Retry (65,157,253). Head/body caps 671.33/693 = board 1105.33/1127 |
| 7 | Phone · past toggle, folded and opened once | PASS | "21 earlier" → "11 earlier", 161. Label (67,152,255) at full strength. Ends 76pt above the Ask bar (board 76) |
| 8 | Phone · rail | PASS | 3x 67–70; 1x straddle ≈ 74.5 vs #48484A (72). Upcoming→past join continuous (ring → 25pt line → green), as on the board |
| 9 | Phone · chip, Claude Code | PASS | 26pt, fill (28,28,30) = #1C1C1E. Logo 14×14 at +7 (217,116,87) vs #D97757. Gap 5.67, trailing 9.67, text 209 vs #D1D1D6 |
| 10 | Phone · chip, Codex | PASS | Same geometry, Codex tile 15×15 at +7, trailing 9.67 |
| 11 | Mac · Runs header + count | PASS | "Runs" ink x 19 = board 19; count right edge 381 = board 381. (138,138,147) = #8A8A93 |
| 12 | Mac · upcoming toggle, folded | **PASS (now against the corrected board)** | Disc x 17–33 = board 17–33, centred on the rail. Label "Show more" x 44 = board 44. Stub 9pt, about 3.5/1.5 dashes vs 3.33/1.67. Chevron: the 1x pixel grid matches the board's 1x render |
| 13 | Mac · upcoming run rows | PASS | Ring 11pt, x 20–31 vs 19.67–30.67, (91,90,98) = #5A5A62. Text x 44 = 44. 32.5pt pitch |
| 14 | Mac · past run rows | PASS | Green 11pt (50,214,74) vs #32D74B. Heads 244, body (199,201,209) vs #C9CBD3, tails 138 with ↗. Pitch 52 vs 52.1. Head→body 19 vs 19.67 |
| 15 | Mac · past toggle, folded | PASS | Label x 44 = 44. "21 earlier" right edge 382 = 382. Disc and chevron as row 12 |
| 16 | Mac · rail | PASS | Line x 24–26 = board 24–26, (65,66,69) vs (65,65,69). Top disc → bottom disc 203 vs 203.33 |
| 17 | Mac · chip, Claude Code (`opus` and "Claude default") | PASS | 24pt, fill (46,46,50) = board. Logo 13×13 at +6. Gap 5. Text (201,203,211) = #C9CBD3. Trailing 9–10 vs 8 (1x, ±1) |
| 18 | Mac · chip, Codex | PASS | Tile 14×14 at +6. Trailing 9 vs board 8.67 |

## 3. Newly in-scope items

**Phone bottom fade and the strip below the Ask bar: PASS (fixed since round 2).**

Rail visibility under the fade, by distance from the Ask bar's top (lossless 1x app vs board render vs the board's CSS):

| pt from bar top | −48 | −28 | −24 | −20 | −16 | −12 | −8 | −4 |
|---|---|---|---|---|---|---|---|---|
| Board measured | 0.97 | 0.67 | 0.61 | 0.54 | 0.47 | 0.39 | 0.33 | 0.25 |
| Board CSS | 0.97 | 0.68 | 0.62 | 0.56 | 0.50 | 0.44 | 0.38 | 0.32 |
| App r3 | 0.96 | 0.66 | 0.61 | 0.54 | 0.48 | 0.43 | 0.36 | 0.32 |

- **Fade:** the app tracks the board within 0.04 everywhere. The −44 to −32 samples hit a node and a gap in the rail, so they are omitted.
- **Strip below the bar:** max 13 / p99 9 (3x) and 11 (1x), with a row present underneath. That matches 96% black over white (≈10); the board's strip is black.
  - Round 2 measured 255 here.
- **Row text in the fade:** about 0.84 at 35pt above the bar (board 0.78) and about 0.32 at 5pt (board 0.34).
- Pair: `r3/crops/p17-bottom-fade-and-below-bar-*`.

**Mac instruction body colour: PASS.** The body now reads (228,229,234), which equals the board's #E4E5EA (round 2: 216). The "Instructions" heading is (138,138,147). Pair: `m10-instructions-*`.

**Mac card "NEXT RUN" label: PASS.**
- Colour (138,138,147) = #8A8A93 (round 2: 165).
- Ink x 32 = board 32. Width 60 vs 61 at 1x. Cap height 8 vs 9 (1x, ±1).
- Pair: `m09-next-run-label-*`.

**Mac page inset: PASS.**
- Chips start at x 18 = board 18 (round 2: 20). Card left edge 18 = board.
- Instructions ink x 18–19 = board. Right-aligned counts end at 381–382 = board.
- The title ink starts at 18 vs 19, because the first letters differ ("V" vs "D").
- Pair: `m11-page-inset-*`, `x02`.

## 4. Deltas from earlier rounds: status

- **F1–F10** (round 1): all still fixed. Every value was re-measured; see §2.
- **R2-1** (Mac toggle label): **resolved.** The board was corrected, and the app's label and disc now match it exactly at x 44 and 17–33.
- **R2-2** (fade and below-bar strip): **fixed** (§3).

## 5. Observations (outside scope, not counted)

**1. Corner style is a little rounder on every chip, on both platforms.**
- The app's corner fits the same radius as the board in rows 1–5. On the phone at 3x, the inset is 3.97/2.61/1.75pt vs a circle of r=8 at 3.84/2.53/1.63.
- Its curve then starts and ends more gradually: the first row is 7.67 vs 6.62, plus faint tails.
- Corner area removed: phone 18.6 vs 14.0 pt²; Mac 15.0 vs 9.9 px² (1x).
- This is the signature of SwiftUI's continuous (smoothed) corners at the same nominal radius. CSS cannot draw that curve. It has been present since round 1.
- Treated like font rendering; flagged in case the owner wants circular corners.

**2. Mac status card, unchanged since round 1, outside scope:**
- Title (225,225,226) vs #F4F4F6 (244).
- Subtitle (165,165,167) vs #A8A8B0 (168,168,176).
- Card top at y 163 vs 161 and bottom at 295 vs 296, so the card is about 3pt shorter.

**3. Mac instructions spacing, unchanged:**
- The "Instructions" heading cap is at 318 vs 316.
- The "Show more" link cap is at 400 vs 403, so it sits about 3pt closer to the text.
- The gap from that link to "Runs" is 36 vs 34.67, which makes the Runs block sit 2pt higher overall.

**4. Phone failure copy.** The app writes "Model unavailable" with a capital M; the board uses lowercase. This is fixture data.

**5. Changes elsewhere since round 2.**
- Phone: only data (card date and countdown, dates) and the fade.
- Mac: the inset shift (everything 2pt left; full-width elements re-laid), the NEXT RUN label colour, the instruction body colour, and the Runs rows' x.
- I found no other changes.

## 6. Interaction checks (phone, live)

- **Upcoming toggle:** 10 upcoming runs, "Show less" with no count, chevron down, no rail above. Scroll position held (Runs stayed at y 399).
- **Past toggle, one tap:** 12 past runs and "Show more · 11 earlier". Scroll position held (Runs at y 103). The failed row renders correctly.
- **Bottom of the opened list:** the toggle clears the Ask bar by 76pt at full strength.

## 7. Coverage limits

- **Mac at 1x only.** The harness renders only at the window's backing scale.
  - The disc and chevron pixel grids are near-identical to the board's own 1x render: fill 54 vs 52 green channel, and the same 3-row chevron with a faint 4th AA row in the app.
  - Retina (2x) rendering itself is not verified.
- **Phone build identity:** no revision label was supplied.
- **Open board's bottom toggle:** it is under the board's own Ask bar, so it was judged from the DOM and the folded template (same as earlier rounds).
- **Mac Codex chip with a raw model id:** not rendered by any stand-in task. Checked on "Codex default".
- **Chrome tab 1045567207** is still open, reset to zoom 1. `tabs_close_mcp` is not in this agent's tool set.

## 8. Files and timing

All paths are under `/Users/eugenechan/dev/personal/lfg/.claude/tasks-a2/evidence/verifier-runs/`.

**Files:**
- **Fresh Mac board captures** (`r3/design/`): `mac-board-1x-401w.png`, `mac-runs-3x-y425.png`, `mac-top-3x-y100.png`.
- **Phone captures** (`r3/app/`): `phone-folded-scrolled`, `phone-later-open-{a,b}`, `phone-past-open-{a,b}`, `phone-task45-top`, `phone-codex-top`. Each has 3x and 1x versions and a `.mov`.
- **Mac captures:** `r3/app/mac-task{45,07,03}.png`, with sRGB copies in `r3/app/srgb/`.
- **Pairs:** `r3/crops/` (29 pairs, review sheets and `index.json`). Manifest: `r3/crops-input/`.

**Timing (HKT):**

| Phase | Time |
|---|---|
| Preparation and board re-render | 00:15–00:17 |
| Phone capture | 00:17–00:21 |
| Mac capture | 00:21 |
| Comparison | 00:17–00:26 |
| Report | 00:26–00:29 |

Tool notes: I used swipes instead of `flowdeck scroll` to return to the top of the list, the same recovery as round 2. There were no capture failures.
