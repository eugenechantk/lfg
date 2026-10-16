# Task view Runs section and model chips: round 2 re-verification (phone and Mac)

**Verdict: FAIL (narrowly).**
- **Round 1 deltas:** all ten are fixed, and each was measured fresh on the new builds.
- **One new in-scope delta (R2-1):** the Mac toggle label sits about 2pt left of the board. The round-2 change that fixed round-1 F7 also moved the toggle labels. The board's offset looks like a CSS artifact, so this needs an owner decision.
- **One flagged item outside the named components (R2-2):** the bottom fade around the ask bar. It is unchanged since round 1, but the opened list now makes it plain to see.

## Contents
1. Scope, references and method
2. Round 1 findings: status
3. Coverage matrix (round 2)
4. New findings
5. Changes elsewhere on these pages
6. Interaction checks
7. Coverage gaps
8. Files
9. Timing and tool recovery

## 1. Scope, references and method

**Scope** is the same as round 1:
- Phone Runs section, folded / upcoming opened / past opened once, with the toggles, rail, run rows (completed and failed) and the header with its count.
- Phone model chips (Claude Code and Codex).
- Mac Runs section, folded, and the Mac model chips.
- The phone chip naming ("Opus" for `opus`) is out of scope, per the coordinator.

**References.** The board files have the same SHA-256 as in round 1 (all seven re-hashed at 23:57):
- `tA2d-runs-rail` e4c35646…, `-open` 97aa8b2f…, `dA2-runs-rail` 1619dce2…, `tA2d-model-pill` 64e08c47…
- `support.js` 3f160299…, and both SVGs unchanged

So the round-1 board renders and DOM values are reused. They used the same renderer, zoom 3 and viewport, and are stored in `design/`. Full hashes are in `evidence.md`.

**Implementation.**
- **Phone:** simulator 1D902A87-40EB-40AF-87A6-BBC19508900B. The app was reinstalled by the coordinator and found on the Sessions tab. Repo HEAD is still 658dae7, with a dirty tree (now also `shared/Tasks/TaskListViews.swift`).
- **Mac:** the bundle binary is dated 23:56:53. Shots for tasks 45 (height 1000), 07 and 03 were converted to sRGB.
- **Hosts:** 8932 and 8933 have the same PIDs as in round 1 (42348/42349). No host state was changed.
- **Data:** midnight passed during capture. Dates shifted ("Today" is now an upcoming row, and the past starts "Thu, Oct 15"); this is data only.

**Capture** used the same methods as round 1:
- Phone: 3x `flowdeck … record` frames (H.264) for geometry, and 1x FlowDeck PNGs for colour.
- Mac: 1x `--window-shot`, converted to sRGB.
- Phone app-to-board alignment offsets, from the first rail dash and nodes:
  - folded and upcoming opened: 138.33pt
  - past opened: 434pt (failed row)
  - past-opened bottom of list: 1024pt
- Mac: the Runs section sits 2.33pt higher than the board (whole block). Internal geometry was compared block-relative.

## 2. Round 1 findings: status (all measured fresh)

| # | Round 1 delta | Round 2 measurement | Status |
|---|---|---|---|
| F1 | Phone greys 140 vs #A1A1A6 (161) | "Runs" 160–161, count 160, "8 later" / "21 earlier" / "11 earlier" 161, upcoming heads 161, tails 161 (3x plateau). 1x p99 175 / 157–174 | **Fixed** |
| F2 | Phone rail 61–65 vs #48484A (72) | 3x 67–70 (codec reads 0–3 dark). 1x straddle 51+77+21 ≈ 74.5 | **Fixed** |
| F3 | Dash stubs [4,3] with open gaps | Phone: 4pt dashes with 0.67pt gaps, three per stub, joined to the solid rail. Each edge matches the board within 0.33pt (above disc 564.33/568.33/569/572.67/573.33; below 595.33/599/604.33). Mac: about 3.5/1.5 vs the board's 3.33/1.67, 9pt stubs both | **Fixed** |
| F4 | Last phone toggle under the fade | The bottom toggle now ends 76pt above the ask bar (board 76). "Show more" (67,152,255) and "21 / 11 earlier" 161 are at full strength in both the folded and the past-opened states | **Fixed** (see R2-2 for the fade itself) |
| F5 | Mac text tokens | Heads (244,244,246), body (199,201,209) vs #C9CBD3, greys (138,138,147). Exact board values | **Fixed** |
| F6 | Mac rail / hollow ring too bright | Rail (65,66,69) vs board (65,65,69). Ring (91,90,98) = #5A5A62. Inside the ring ≈ page | **Fixed** |
| F7 | Mac nodes 12pt; run text 2pt right | Nodes 11×11 (hollow and green). Run text +26 from the content edge (board +26.33) | **Fixed** (but see R2-1) |
| F8 | Mac past-row pitch 51 vs 52.1 | Pitch 52 (node tops 564→616; caps 563→615). Head→body 19 vs 19.67. Top disc→bottom disc 203 vs 203.33 | **Fixed** |
| F9 | Mac chip fill (38,38,43) | (46,46,50) on Pro, model and folder chips. Board (46,46,50) | **Fixed** |
| F10 | Phone failure red bluer | Node and reason (255,69,58) = #FF453A at 1x | **Fixed** |

## 3. Coverage matrix (round 2)

Legend: P = PASS, ~ = PARTIAL (1x resolution limit), N/A = not applicable.

Criteria: 1 Internal consistency · 2 Structure · 3 Copy · 4 Typography · 5 Colour · 6 Glyphs · 7 Spacing/shape · 8 States · 9 Chrome

| # | Component / state | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Phone · Runs header + count (all states) | P | P | P (data) | P | P | N/A | P | P | N/A |
| 2 | Phone · upcoming toggle, folded | P | P | P | P | P | P | P | P | N/A |
| 3 | Phone · upcoming toggle, opened (Show less) | P | P | P | P | P | P | P | P | N/A |
| 4 | Phone · upcoming run rows (2 / 10) | P | P | P (data) | P | P | P | P | P | N/A |
| 5 | Phone · past rows, completed (2 / 12) | P | P | P (data) | P | P | P | P | P | N/A |
| 6 | Phone · past row, failed | P | P | P (data) | P | P | P | P | P | N/A |
| 7 | Phone · past toggle, folded + opened once | P | P | P | P | P | P | P | P | N/A |
| 8 | Phone · rail | P | P | N/A | N/A | P | P | P | P | N/A |
| 9 | Phone · chip Claude Code | P | P | P | P | P | P | P | N/A | N/A |
| 10 | Phone · chip Codex | P | P | P | P | P | P | P | N/A | N/A |
| 11 | Mac · Runs header + count | P | P | P (data) | P | P | N/A | P | P | N/A |
| 12 | Mac · upcoming toggle, folded | P | P | P | P | P | ~ (chevron at 1x) | **R2-1** | P | N/A |
| 13 | Mac · upcoming run rows | P | P | P (data) | P | P | P | P | P | N/A |
| 14 | Mac · past run rows | P | P | P (data) | P | P | P (↗ tail) | P | P | N/A |
| 15 | Mac · past toggle, folded | P | P | P | P | P | ~ | **R2-1** | P | N/A |
| 16 | Mac · rail | P | P | N/A | N/A | P | N/A | P (disc centred on rail; see R2-1) | P | N/A |
| 17 | Mac · chip Claude Code (`opus` and default) | P | P | P | P | P | P | ~ (radius, ±1–2px trailing pad at 1x) | N/A | N/A |
| 18 | Mac · chip Codex | P | P | P | P | P | P | ~ | N/A | N/A |
| 19 | Phone · whole screen: fade / below ask bar | — | — | — | — | **R2-2** | — | P (76pt clearance) | — | P |
| 20 | Mac · whole window | P | P | — | — | P (see §5) | — | — | — | ~ (glass items blank: capture limit) |

## 4. New findings

**R2-1. The Mac toggle label sits about 2pt left of the board, relative to the rail.**

| Element | Board, from content edge 18 | App, from content edge 20 |
|---|---|---|
| Disc | 18–34, centre 26 | 19–35, centre 27 |
| Rail centre | 25 | 27 |
| Run text | +26.33 | +26 (matches) |
| Toggle label ("Show more", both toggles) | +28.67, which is 2.33pt right of the run text | +26, aligned with the run text |

- **Delta:** the label is 2.0–2.7pt left (1x, ±0.5). The disc is centred on the rail in the app; on the board it sits 1pt right of the rail.
- **Pair:** `r2/crops/m08-rail-toggle-zoom-*`, also `m02`, `m04`.
- **Probable board artifact (owner to decide):**
  - In `dA2-runs-rail.dc.html`, the toggle's rail column is `flex: 0 0 14px` with no explicit width. Its 16px disc widens it to 16px, which pushes the label 2px right and the disc 1px right.
  - The phone board sets `width: 16px` on the same column. Its labels align with the run text (both x 48) and its disc is centred on the rail. The app now reproduces the phone geometry on the Mac.
  - If the owner wants literal matching, move the Mac toggle labels about 2pt right. Otherwise accept the app's alignment as the intent.
- **Regression:** in round 1 the label matched (+28) and only the run text was off.

**R2-2. The phone bottom fade differs from the board, and content shows below the ask bar.** This is outside the named components; it belongs to the ask-bar fade, which passed earlier rounds. It is unchanged since round-1 O3, but now plainly visible.

| | Board (`tA2d-runs-rail-open`) | App |
|---|---|---|
| Fade start | 50pt above the bar's top | about 70pt above the bar |
| Content visible at the bar's top | 26% (fade 0→0.96 over 65pt) | about 3% |
| Mid-fade sample | 30pt above the bar, a row is mostly visible | 36pt above the bar, a row is at 56% ("Sun, Oct 18" 90 vs 161) |
| Strip below the bar | 0.96 black, so content is hidden | no fade |

- **Effect:** in the opened states, a run row ("Today · 9:00 AM" head 250, green node (45,207,86)) shows at full brightness in the 40pt strip below the ask bar, while the rows just above the bar are faded out.
- **Pair:** `r2/crops/p17-bottom-fade-and-below-bar-*`. Rail-column profile in `r2/app/phone-later-open-a-3x.png`.
- Earlier rounds never saw content behind the bar (round-1 list-and-view notes the task view was too short).
- Not counted toward the verdict; flagged so the owner can decide.

## 5. Changes elsewhere on these pages

Method: the round-1 and round-2 shots were pixel-diffed. Only bands with a change are listed.

**Phone** (excluding the clock, countdown and data):
- The "Instructions" heading changed from 140 to 161 and now matches #A1A1A6.
- The instruction body, status card, header, chips and ask bar are pixel-identical apart from data.

**Mac:**
- Title 224 → (244,244,246), now matching #F4F4F6.
- Schedule line → (201,203,211), now matching #C9CBD3.
- "Instructions" heading → (138,138,147), now matching #8A8A93.
- Chip text → (201,203,211). Chip fill → (46,46,50).
- The gap from the instructions "Show more" to "Runs" is 36pt vs the board's 34.67 (round 1: 37).

Still different on the Mac, unchanged and outside scope (these passed earlier rounds):
- Instruction body (216,216,216) vs the board's (228,229,234).
- Card "NEXT RUN" label and card subtitle (165,165,167) vs the board's (138,138,147) and (168,168,176).
- Page content inset: chips start at x 20 vs the board's 18.

## 6. Interaction checks (phone, live)

- **Upcoming toggle:** the tap shows all 10 upcoming runs, and the label becomes "Show less" with no count. The chevron points down and there is no rail above the disc. Scroll position held (the Runs header stayed at y 399).
- **Past toggle, one tap:** 12 past runs and "Show more · 11 earlier". The scroll position held (Runs at 103). The failed run renders correctly.
- **Bottom of the opened list:** the toggle clears the ask bar by 76pt at full strength.
- **Not exercised** (not requested): collapsing again, and the final past "Show less".

## 7. Coverage gaps

- **Mac is 1x only:** the chevron, chip corner radius and chip trailing pad (app 9–10 vs board 8–8.7) are within ±1–2px and marked "~".
- **Phone build identity:** the reinstalled build's revision label was not supplied.
- **Open board bottom toggle:** it is under the board's own ask bar, so it was judged from the DOM and the folded template (same as round 1).
- **Mac Codex chip with a raw model id** ("gpt-6-astra"): not rendered by any stand-in task. Geometry and logo were checked on "Codex default".
- **Chrome tab 1045567207** is still open. `tabs_close_mcp` is not available in this agent's tool set.

## 8. Files

All paths are under `/Users/eugenechan/dev/personal/lfg/.claude/tasks-a2/evidence/verifier-runs/`.
- **Round 2 phone captures** (`r2/app/`): `phone-task45-top`, `phone-folded-scrolled`, `phone-later-open-{a,b}`, `phone-past-open-{a,b}`, `phone-codex-top`. Each has `-3x.png` and `-1x.png` versions and a `.mov`.
- **Round 2 Mac captures:** `r2/app/mac-task{45,07,03}.png`, with sRGB copies in `r2/app/srgb/`.
- **Pairs:** `r2/crops/*-design.png` / `*-app.png` (26 pairs), `r2/crops/review-0{1..5}.png` and `r2/crops/index.json`. Manifest: `r2/crops-input/pairs.json`.
- **Board captures** (reused, hashes unchanged): `design/`.

## 9. Timing and tool recovery

| Phase | Time (HKT) |
|---|---|
| Preparation (hashes, build times, hosts) | 23:57:32–23:58 |
| Board capture | reused (hashes unchanged) |
| Phone capture | 23:58–00:03 |
| Mac capture | 00:03–00:04 |
| Comparison and crops | 23:59–00:08 (interleaved) |
| Report | 00:08–00:12 |

Tool notes (each recorded once):
1. **The Mac `--height 1000` flag was dropped on the first task-45 shot.** zsh does not word-split an unquoted variable. I re-shot task 45 explicitly.
2. **One `flowdeck scroll` at the end of the list moved nothing.** A `swipe` from 650 to 100 worked.
3. **The fade pair first used the folded board,** which has no content behind its bar. I switched to the open board's bottom tile, which does.
