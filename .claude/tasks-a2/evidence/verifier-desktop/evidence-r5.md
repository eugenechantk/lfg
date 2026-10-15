# Desktop Tasks (dA2-*): independent design verification, round 5

Verdict: **PARTIAL**. The edit-page spacing is the only thing left. The list (toolbar included) and the three task-view states pass.

On the edit page, structure, copy, tokens and colours match on every variant. The Name row regression from round 4 is fixed. What remains is small vertical spacing:

- The gaps between cards are 3–4 px tight.
- The Once calendar block is 9 px short. It has been that way since round 3; my round-4 report wrongly called it fixed.
- The Once shortcut chips are 2 px taller than the board.

## Contents
1. Scope and method
2. List and task view
3. Edit page: vertical rhythm
4. Edit page: components
5. Corrections to my round-3 and round-4 numbers
6. Carry-overs / unverified
7. Files

## 1. Scope and method

- **Boards:** unchanged since 13:22, so the round-1 captures and DOM dumps are reused.
- **App bundle:** rebuilt at 17:39:10.
- **Shots:** all 19, as in round 4. The `edit-3days` shot failed once with a transient screencapture error ("could not create image from window"). A retry succeeded with the screen unlocked.
- **Colour:** sRGB (`app-r5/srgb/`).
- **Outer card edges, measured a new way.** A card's outer top and bottom rows are the rows where *every* pixel from x=60 to 340 differs from the page background (26,26,30). This captures the full rounded edge.
  - The round-4 method sampled a single column at x=377. That column sits about 2px inside each rounded corner, so every card read about 2px short at both ends and every gap about 4px wide. §5 corrects those numbers.
  - Design values come from the DOM (exact).
- **Diff against round 4:**
  - The list (8933 and 8932) and the failed view are pixel-identical to round 4.
  - The next-run and waiting views differ only in the live countdown text: "in 15 h 29 min" and the waiting time.
  - Every edit page changed.

## 2. List and task view: PASS

Pixel-identical to round 4 apart from the countdown text, so the round-4 component pass stands unchanged. I re-ran the colour checklist on the round-5 shots:

- List: amber (255,179,63) = #FFB340, red (255,106,97) = #FF6B61, green (90,227,122) = #5BE37A.
- Tasks badge: (255,159,11) = #FF9F0A.
- Answer in iTerm: (255,159,11) = #FF9F0A.
- Edit accents: #3B8EFF fill, #9CC2FF chip text, chip fill (41,57,83).

Crops: `pairs-r5/full-list.png`, `pairs-r5/list-paused.png`, `pairs-r5/full-detail*.png`.

## 3. Edit page: vertical rhythm (outer edges, px)

Weekdays board (`dA2-edit`) vs task 14:

| Measure | Board (DOM) | r3 | r4 | **r5** | r5 result |
|---|---|---|---|---|---|
| Name card | 69–226 (157, 3 lines) | 68–261 | 68–253 | **68–266 (198, 5 lines)** | PASS. The 2 extra instruction lines add 40px, which explains 157→197. |
| Name row (card top → divider) | 59 | 55 | 47 | **60** | PASS |
| Name label / value / Instructions label / first line (from card top) | 13 / 31 / 71 / 91 | — | — | 15 / 33 / 72 / 90 | PASS |
| Gap: Name card → When card | 44 | 43 | 36 | **41** | minor (−3) |
| When card | 270–628 (358) | 304–677 (373) | 289–654 (365) | **307–667 (360)** | PASS (+2) |
| When top section (top → first divider) | 177 | 185 | 185 | **180** | minor (+3; the dots row sits 3–4px lower) |
| Time / Ends / Next runs / time-zone rows | 43 / 43 / 60 / 35 | — | — | 43 / 43 / 59 / 35 | PASS |
| Gap: When card → Runs on card | 45 | 43 | 36 | **41** | minor (−4) |
| Runs on card / rows | 673–835 (162) / 40–41 | 160 | 160 | **708–868 (160) / 40 each** | PASS (−2) |

When-card heights for every variant (r5 vs board):

| Variant | Board | r5 | Δ |
|---|---|---|---|
| weekdays | 358 | 360 | +2 |
| weekly | 358 | 360 | +2 |
| 5min | 322 | 322 | 0 |
| monthly | 322 | 322 | 0 |
| 7min | 365 | 365 | 0 |
| 5hours | 365 | 365 | 0 |
| hourly | 365 | 365 | 0 |
| daily | 365 | 365 | 0 |
| 3days | 365 | 365 | 0 |
| 3days-after | 426 | 422 | −4 |
| after-n | 419 | 417 | −2 |
| on-date | 419 | 419 | 0 |
| custom | 373 (2-line sentence) | 348 (1-line, data) | about −3 after allowing for the data |
| once | 453 | 448 | −5 |

The card gaps are 41 and 41 on every variant.

**Once (task 32) detail:**

| Block | Board | r5 | Result |
|---|---|---|---|
| Top section → calendar divider | 103 | 102 | PASS |
| Calendar block | 206 | **197** | **minor (−9).** The weekday header sits 8px closer to the month label (+36 vs +44 below the divider). The 28px day-row pitch matches the board. |
| Time row | 43 | 43 | PASS |
| Shortcut block | 66 | 71 | minor (+5) |
| Shortcut chips | 26 tall; 111 / 100 / 86 wide | **28 tall; 116 / 104 / 90 wide** | minor |
| Time-zone row | 35 | 35 | PASS |

Crops: `pairs-r5/edit-top.png`, `pairs-r5/edit-once-calendar.png`, `pairs-r5/full-edit*.png`.

## 4. Edit page: components: PASS on all 14 variants

Mode segmented, sentence and how-it-runs line, preset chips (selected #3B8EFF, "Weekly" not clipped), weekday dots (selected #F4F4F6), Every field, Starts / Time / At minute pills (#8FB8FF), Ends segmented, Number of runs / End date ("Thu, Dec 31, 2026"), Last run line, Next runs chip formats and counts, time zone + Change, custom cron field (#3B8EFF border, #1E1E22 fill, 13px mono), Monthly "On the 16th at", the Once calendar's tokens and divider, and the Runs on card. None of these changed in a way that breaks a match since round 4. The full-page pairs were reviewed for every variant.

## 5. Corrections to my round-3 and round-4 numbers

Re-measured with the outer-edge method:

| Measure | Board | What I reported | Actual |
|---|---|---|---|
| Card gaps, round 3 | 44 / 45 | 46 / 46 | 43 / 43 |
| Card gaps, round 4 | 44 / 45 | 40 / 38 | 36 / 36 |
| Name row, round 4 | 59 | 46 | 47 |
| Once calendar block, round 4 | 206 | 204 ("fixed") | 197 (unchanged since round 3) |

The round-4 calendar figure came from reading coordinates off a scaled side-by-side image, not from pixel measurement. My round-2 "51" for the card gaps came from a column inside the corner radius.

## 6. Carry-overs / unverified

- The titlebar band renders (48,48,48), the page (26,26,30). This may be inactive-window chrome; it needs a key-window check.
- Host-strip connected/offline colours and the "All hosts" filter. The single task host and an unresolved local config prevent checking them.
- "Open session in iTerm" and the "2nd in a row" label (fixture limits).
- The fade over scrolled content.
- Interactive states.

## 7. Files

- `app-r5/` (raw), `app-r5/srgb/` (sRGB)
- `pairs-r5/` (design left, app right)
