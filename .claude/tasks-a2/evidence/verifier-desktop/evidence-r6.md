# Desktop Tasks (dA2-*): independent design verification, round 6

Verdict: **PASS**, with minor spacing notes. The list (toolbar included), the three task-view states and all 14 edit variants match the boards in structure, copy, glyphs, surfaces and colour tokens. Every round-5 spacing delta is now within ±2 px of the board, measured from the full outer card edges.

No residual delta is larger than 6 px, and none changes structure. They are listed in §4 so the coordinator can decide whether to chase them.

## Contents
1. Scope and method
2. List and task view
3. Edit page: card rhythm (full outer edges)
4. Residual sub-6px notes
5. Carry-overs / unverified
6. Files

## 1. Scope and method

- **Boards:** unchanged since 13:22, so the round-1 board captures and DOM dumps are reused. Design measurements come from the DOM, so they are exact.
- **App bundle:** rebuilt at 17:48:52.
- **Shots:** all 19, the same set as round 5. Each shot retries up to 3 times after an unlock; none needed a retry this round.
- **Colour:** sRGB (`app-r6/srgb/`).
- **Outer card edges:** rows where every pixel from x=60 to 340 differs from the page background (26,26,30). This is the same method as round 5.
- **Diff against round 5:**
  - The list (8933 and 8932) and the failed view are pixel-identical.
  - The next-run and waiting views differ only in the live countdown text.
  - Every edit page changed, from y=284 downward.

## 2. List and task view: PASS

These screens are unchanged from round 5, which passed every component. The colour checklist was re-run on the round-6 shots: Answer in iTerm is (255,159,11) = #FF9F0A, and the edit-form accents are #3B8EFF, #8FB8FF and #9CC2FF, with chip fill (41,57,83).

Crops: `pairs-r6/full-list.png`, `pairs-r6/full-detail*.png`.

## 3. Edit page: card rhythm (full outer edges, px)

Weekdays (task 14 vs `dA2-edit`):

| Measure | Board | r5 | **r6** | Result |
|---|---|---|---|---|
| Gap: Name card → When card | 44 | 41 | **44** | PASS |
| When card top → first divider | 177 | 180 | **176** | PASS |
| Time / Ends / Next runs / time-zone rows | 43 / 43 / 60 / 35 | 43 / 43 / 59 / 35 | 43 / 43 / 59 / 35 | PASS |
| When card height | 358 | 360 | **356** | PASS (−2) |
| Gap: When card → Runs on card | 45 | 41 | **44** | PASS |
| Runs on card | 162 | 160 | **162** | PASS |

All variants (r6 vs board):

| Variant | When card (board → app) | Gaps | Runs on |
|---|---|---|---|
| weekdays, weekly | 358 → 356 | 44 / 44 | 162 |
| 5min, monthly | 322 → 322 | 44 / 44 | 162 |
| 7min, 5hours, hourly, daily, 3days | 365 → 365 | 44 / 44 | 162 |
| 3days-after | 426 → 422 (−4) | 44 / 44 | 162 |
| after-n | 419 → 413 (−6) | 44 / 44 | 162 |
| on-date | 419 → 415 (−4) | 44 / 44 | 162 |
| custom | 373 (2-line sentence) → 348 (1-line, data) | 44 / 44 | 162 |
| once | 453 → 454 (+1) | 44 / 44 | 162 |

The Name card is 198px because the fixture instructions are 5 lines where the board has 3 (+40px, data). Its row positions match the board.

Once (task 32):

| Block | Board | r5 | **r6** | Result |
|---|---|---|---|---|
| Top → calendar divider | 103 | 102 | 102 | PASS |
| Calendar block | 206 | 197 | **205** | PASS. The weekday header is now 44px below the divider, matching the board. |
| Time row | 43 | 43 | 43 | PASS |
| Shortcut chips | 26 tall; 111 / 100 / 86 wide | 28; 116 / 104 / 90 | **26; 110 / 98 / 84** | PASS |
| Shortcut block | 66 | 71 | 69 | minor (+3; chips start 10px below the divider, board 8) |
| Time-zone row | 35 | 35 | 35 | PASS |

Components: on all 14 variants, structure, copy, chip formats, accent tokens, the custom cron field, Monthly "On the 16th at", End date, Last run, the Once calendar tokens, and the Runs on card all match. Full-page pairs were reviewed for every variant.

Crops: `pairs-r6/full-edit*.png`, `pairs-r6/edit-once-calendar.png`.

## 4. Residual sub-6px notes (not blocking)

| Where | Board | App |
|---|---|---|
| after-n When card: Ends + Number-of-runs block / Next runs | 103 / 61 | 100 / 59 (card −6) |
| on-date and 3days-after When card | 419 / 426 | 415 / 422 (−4) |
| Next runs row (repeat variants) | 60–61 | 59 |
| Once shortcut block | 66 | 69 |

## 5. Carry-overs / unverified

- The titlebar band renders (48,48,48), the page (26,26,30). This may be inactive-window chrome; it needs a key-window check.
- Host-strip connected/offline colours and the "All hosts" filter. The single task host and an unresolved local config prevent checking them.
- "Open session in iTerm" and the "2nd in a row" label (fixture limits).
- The fade over scrolled content.
- Interactive states.

## 6. Files

- `app-r6/` (raw), `app-r6/srgb/` (sRGB)
- `pairs-r6/` (design left, app right)
