# Desktop Tasks (dA2-*): independent design verification, round 4

Verdict: **PARTIAL**. The list (toolbar included), the three task-view states and every edit variant now match the boards in structure, copy, glyphs, surfaces and every colour token I measured. All round-3 deltas are fixed except edit-form spacing.

What remains is edit-form vertical spacing only. One part of it got worse this round: the Name row in the Name/Instructions card is now 13 px shorter than the board.

This report also corrects my own earlier numbers. The card-gap figures I gave in rounds 2 and 3 (51 px) were wrong; the real round-3 gaps were 46 px. That error probably led to the over-tightening seen here (§4).

## Contents
1. Scope and method
2. List
3. Task view
4. Edit page
5. Round-3 deltas: status
6. Carry-overs / unverified
7. Files

## 1. Scope and method

- **Boards:** unchanged since 13:22, so the round-1 captures and DOM dumps are reused.
- **App bundle:** rebuilt at 17:29:49.
- **Shots:** the same set as round 3. The list on 8933, plus 8932 for Paused and Closed. Tasks 14, 03 and 01. `--edit` on 14 and 32–44.
- **Colour:** all colours are sRGB (`app-r4/srgb/`). The monitor-profile round trip was checked in round 3: it is accurate to within 1 level.
- **Scope:** as in round 3. The list toolbar is in scope, glass surfaces count as native, and the host-strip label font is out of scope.
- **Diff against round 3:** I diffed every round-4 shot against round 3 to find what changed. I still ran the full component pass on all 19 screens.

## 2. List

| Component | Result | Measured, design vs app |
|---|---|---|
| Switcher + Tasks badge | PASS | Badge 16×16, fill **(255,159,11)** = #FF9F0A (round 3 measured (255,158,50)). Selected segment 76×26. The Sessions badge is absent because the harness has no sessions (data). |
| Search, + buttons | PASS | Both now have a glass surface (54,54,54). Round 3 had no surface behind +. |
| Host strip | PASS | Same surface as the list (26,26,30). Layout from x=16, hairline, 30px tall. |
| Section headers | PASS | Chevron 6×4 at x=20, now (144,144,146), board about (138,138,140). In round 3 it was a dim (84,84,86); I missed that then. |
| Rows | PASS | Time x=17, title x=75, chevron x=376–380, pitch 74, separators x=74–399. |
| Tones | PASS | Amber #FFB340, red #FF6B61, "Now" and running text #5BE37A, running dot #32D74B. |
| Paused / Closed | PASS | Full "…its run time has passed" line. Closed is collapsed. |
| Internal consistency | PASS | Uniform from the strip down. |

Crops: `pairs-r4/list-toolbar-zoom.png`, `pairs-r4/full-list.png`, `pairs-r4/list-needs-input.png`, `pairs-r4/list-paused.png`.

## 3. Task view

| Component | Result | Measured |
|---|---|---|
| Next run, all components | PASS | Runs header at y=436–445 (board 437–445). Timeline rows at y=464/498/531/582/633 (board 465/498/530/582/633). The 4–5px offset from round 3 is gone. |
| Timeline nodes | PASS | Done (51,215,76) = #32D74B. Failed (255,90,80) = #FF5A50. |
| Last run failed | PASS | Border, fill, label, 17pt title, ↗, "Fix or change with chat", full instructions. Timeline red: node #FF5A50, text #FF6B61. |
| Needs input | PASS | Answer in iTerm **(255,159,11)** = #FF9F0A, and the dot is the same colour. Button at y=282–317 (board 281–316). Footer at 332 (board 331). Card bottom at 380 (board about 377). Context line pitch 19. Copy correct. |

Crops: `pairs-r4/full-detail*.png`, `pairs-r4/input-card.png`.

## 4. Edit page (14 variants)

Structure, copy, chip formats, accent tokens, dividers, the Once calendar, the custom cron field, Monthly "On the 16th at", and the Runs on card all still match.

**Spacing, measured precisely this round:**

| Item | Board | App r3 | App r4 | Result |
|---|---|---|---|---|
| Name row (card top → divider) | 59 | 54 | **46** | **FAIL (regressed)** |
| Name label → value (relative to card top) | 13 / 31 | 12 / 29 | 10 / 25 | minor |
| Divider → Instructions label → first line | 12 / 20 | 12 / 18 | 12 / 18 | PASS |
| Gap: Name card → When card | 44 | 46 | **40** | minor (now under) |
| Gap: When card → Runs on card | 45 | 46 | **38** | minor (now under) |
| When card top section (top → first divider) | 177 | 184 | 183 | minor (+6; the dots row sits 3px lower and 15px above the divider, board 9) |
| Rows: Time / Ends / Next runs / time zone | 43 / 43 / 60 / 35 | — | 43 / 43 / 59 / 34 | PASS |
| Once calendar block | 206 | 197 | 204 | PASS |
| Runs on card / rows | 162 / 40–41 | 160 | 158 / 39–40 | PASS |

**Correction to rounds 2 and 3:** I reported the gaps between cards as 51px and the time-zone row as 39px. Those numbers came from a column that sat inside each card's corner radius, which shifts every edge by about 5px. Measured at x=377 instead, round 3 was 46 and 46 for the gaps, close to the board's 44 and 45. The round-4 change tightened them past the board to 40 and 38. The time-zone row was +6 in round 3 and is now 34 vs 35. Any spacing fix based on my earlier figures should be re-checked against the table above.

Crops: `pairs-r4/full-edit*.png`.

## 5. Round-3 deltas: status

| Round-3 delta | Round 4 |
|---|---|
| + button had no surface | Fixed |
| Answer in iTerm and dot colour (255,146,48) | Fixed: #FF9F0A |
| Tasks badge (255,158,50) | Fixed: #FF9F0A |
| Done node green | Fixed: #32D74B |
| Failed node red | Fixed: #FF5A50 |
| Waiting card spacing | Fixed: within 1–3px |
| Task view runs block 4–5px high | Fixed |
| Edit card gaps / Name row / time-zone row | Time-zone row fixed. Gaps now 4–7px under the board. **Name row regressed to 46 (board 59).** |

## 6. Carry-overs / unverified

- The titlebar band renders (48,48,48), the page (26,26,30). This may be inactive-window chrome; it needs a key-window check.
- Host-strip connected/offline colours and the "All hosts" filter. The single task host and an unresolved local config prevent checking them.
- "Open session in iTerm" and the "2nd in a row" label (fixture limits).
- The fade over scrolled content.
- Interactive states.

## 7. Files

- `app-r4/` (raw), `app-r4/srgb/` (sRGB)
- `pairs-r4/` (design left, app right)
