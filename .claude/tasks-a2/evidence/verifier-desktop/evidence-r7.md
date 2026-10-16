# Desktop Tasks (dA2-*): independent design verification, round 7 (final regression)

Verdict: **PASS**. No regressions. The shared edit-form change only touched the number fields (Every, and Number of runs), and it brought them closer to the board. Every other screen is pixel-identical to round 6, apart from live data: countdowns, next-run times and the Save label.

## Contents
1. Scope and method
2. A transient data mutation during capture
3. What changed since round 6
4. Component pass
5. Edit page rhythm (full outer edges)
6. Observation outside board scope
7. Carry-overs / unverified
8. Files

## 1. Scope and method

- **Boards:** unchanged since 13:22, so the round-1 board captures and DOM dumps are reused.
- **App bundle:** rebuilt at 18:38:11.
- **Shots:**
  - All 19, with up to 3 retries after an unlock; no retries were needed.
  - The list on 8933, plus a list shot on the restarted 8932 host for Paused and Closed.
  - Tasks 14, 03 and 01. `--edit` on 14 and 32–44.
- **Colour:** sRGB (`app-r7/srgb/`).
- **Card edges:** measured from the full outer edge, the same method as rounds 5–6.
- **Pixel diff:** every shot was diffed against round 6, then the full component pass was run.

## 2. A transient data mutation during capture

My first-pass shots of task 14 on 8933 (18:39) showed different task data:

- schedule `0 8 * * 2-5` ("Every Tuesday, Wednesday, Thursday, and Friday at 8:00 AM")
- agent Codex, model gpt-6-astra

A few minutes later the host API returned task 14 as `0 9 * * 1-5`, Claude, with no model, the same as every earlier round. So the task was changed on the host and then restored. Something else was writing to the 8933 host during my first pass.

I re-shot the list, task 14's view and task 14's edit page after the restore. The verdict uses the re-shots. The first-pass shots are kept in `app-r7/first-pass/`, with a comparison in `pairs-r7/task14-transient-mutation.png`. Tasks 03, 01 and 32–44 were unaffected: their data matches every earlier round.

## 3. What changed since round 6 (pixel diff)

| Screen | Change | Assessment |
|---|---|---|
| List (8933 and 8932) | Row times only ("V 5min" next run, running durations) | data |
| Task view, next run / waiting | Countdown text only | data |
| Task view, failed | none | — |
| All edit pages | Save label in the title bar is now brighter (enabled look). Fill not judged (inactive window). | consistent with the board's enabled Save |
| Every field (5min, 7min, 5hours, hourly, daily, 3days, 3days-after) | **Now 56×28 with fill (30,30,34)**. Round 6 was 56×26 with the card fill (38,38,43). | **Now matches** the board (`input 56x28 bg #1E1E22`) |
| Number of runs field (3days-after, after-n) | Same change: 56×28, #1E1E22 | **Now matches** |
| 3days-after, after-n When cards | +2px from the taller field | closer to the board |
| 5min, hourly, once | Next-run chip times and Once countdown | data |

**Correction to rounds 2–6:** I passed the Every field on its ring and size without checking its fill or exact height. It was 2px short and used the card fill until this round.

## 4. Component pass

| Screen | Result |
|---|---|
| List: toolbar (switcher, Tasks badge #FF9F0A, search and + glass circles), host strip, sections, rows, tones (#FFB340, #FF6B61, #5BE37A), Paused/Closed (8932) | PASS. Unchanged from round 6 apart from row times. |
| Task view: next run | PASS (re-shot after the data restore). |
| Task view: last run failed | PASS. Pixel-identical to round 6. |
| Task view: needs input | PASS. Answer in iTerm (255,159,11) = #FF9F0A. |
| Edit: all 14 variants | PASS. Structure, copy, chip formats, accent tokens, cron field, Monthly row, End date, Once calendar and Runs on card all match. Number fields now match exactly. Full-page pairs were reviewed. |

## 5. Edit page rhythm (full outer edges, px; board → app)

| Variant | When card | Gaps | Runs on |
|---|---|---|---|
| weekdays, weekly | 358 → 356 | 44 / 44 (board 44 / 45) | 162 → 162 |
| 5min, monthly | 322 → 322 | 44 / 44 | 162 |
| 7min, 5hours, hourly, daily, 3days | 365 → 365 | 44 / 44 | 162 |
| 3days-after | 426 → **424** (round 6: 422) | 44 / 44 | 162 |
| after-n | 419 → **415** (round 6: 413) | 44 / 44 | 162 |
| on-date | 419 → 415 | 44 / 44 | 162 |
| custom | 373 (2-line sentence) → 348 (1-line, data) | 44 / 44 | 162 |
| once | 453 → 454 | 44 / 44 | 162 |

The Once calendar is 205px (board 206). The shortcut chips are 26px tall. All unchanged from round 6.

## 6. Observation outside board scope (from the transient data)

While task 14 held the cron `0 8 * * 2-5`, its edit page opened as **Custom**, showing the cron field and no day dots. The form did not open it as Weekly with Tue–Fri selected.

No board covers this case, so it is not counted in the verdict. The feature plan says existing tasks should "open in the right mode and pick". A day *range* like `2-5` is a weekly-days schedule; the Weekdays board itself saves the range `1-5`. Worth a `ScheduleDraftTests` case if Weekly is meant to cover ranges. Evidence: `app-r7/first-pass/edit-srgb.png`.

## 7. Carry-overs / unverified

- The titlebar band renders (48,48,48), the page (26,26,30). This may be inactive-window chrome; it needs a key-window check.
- The fill of Save and other prominent buttons (inactive window).
- Host-strip connected/offline colours and the "All hosts" filter.
- "Open session in iTerm" and the "2nd in a row" label (fixture limits).
- The fade over scrolled content.
- Interactive states.
- The "Change task" edit chat the coordinator mentioned on 8932 is a session. The Sessions view is out of scope, and the harness loads no sessions.

## 8. Files

- `app-r7/` (raw), `app-r7/srgb/` (sRGB), `app-r7/first-pass/` (the mutated task-14 shots)
- `pairs-r7/` (design left, app right): `full-*.png`, `edit-3days-after-fields.png`, `r6-vs-r7-*.png`, `task14-transient-mutation.png`
