# Verifier evidence, form round 4: phone edit form vs `tA2d-edit*` boards

Date: 2026-10-15 18:26–18:40 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PASS**. All 14 variants match the boards in structure, copy, colour, controls and spacing. The remaining differences are 1–3 pt row-height variations and the agreed native controls.

Earlier rounds: `evidence-form.md`, `evidence-form-r2.md`, `evidence-form-r3.md`.

## Scope and method
- Boards: the same 14 phone edit boards (`raw/design-*.jpg`; board files unchanged since 13:22).
- App build: the binary on sim `1D902A87-…` is from 18:25:45, newer than every Tasks source edit (`TaskEditorViews.swift` 18:24:44, `ScheduledTasksView.swift` 18:24:46). I re-checked it after the pass and it was unchanged. 1x captures are in `raw-r4/`. Every FlowDeck call passed `-S`. I did not touch sim `D379DCF1-…`.
- Drive path, from "Daily repo review" → Edit:
  - Once.
  - Repeat → Minutes; Every 7; Hourly; Every 5; Daily; Every 3.
  - After N with 5 runs; Weekdays with 10 runs; On date; Never.
  - Weekly with Tue and Thu off; Monthly.
  - Custom with `30 8 1,15 * *`.
  - Raw-touch Cancel.
- No writes: the fixture log shows only preview POSTs from me (plus push registrations from the app relaunches). The task's schedule is still `cron 0 9 * * 1-5`, enabled.
- Regression check: after Cancel, the task view differs from the round-4 list/view capture only in the countdown line (y 306–317).
- Excluded:
  - Data: next-run values, relative times, Host "Pro", the default end date.
  - The Model row.
- Native, as before: glass toolbar items, title-case section headers, system segmented controls, compact date and time pickers, the graphical calendar, inset list separators.

## Measurements (Weekdays base screen, board vs app)

| Item | Board | App (round 3 → now) |
|---|---|---|
| When card height | 402 | 436 → **397** |
| Card top → Once/Repeat control | 12 | 18 → **10** |
| Mode → sentence / sub-line → chips / chips → dots | 12 / 10 / 10 | **14 / 10 / 10** |
| Dots → separator | 11 | 19 → **12** |
| Time row | 51 | 52 → **51–52** |
| Ends row | 49 | 52 → **46–47** |
| Next runs row | 64 | 64 → **63** |
| Time zone row (text 11/12 from edges on the board) | 33 | 53 → **35** (text 13 / 12) |
| Every-5-minutes card | 354 | **347** |

On the first screen the app now shows Host and Folder in full, as the board does (`r4-full-edit.png`).

## Per-component table (all Repeat variants)

| Component | Consistency | Structure | Copy | Type | Colour | Spacing |
|---|---|---|---|---|---|---|
| Toolbar | PASS | PASS | PASS | PASS | PASS (white Save on `#0A6EE0`) | native |
| Name + Instructions | PASS | PASS | PASS | PASS | PASS | native (rows 50) |
| Once/Repeat, sentence, sub-line | PASS | PASS | PASS (all 14) | PASS | PASS | PASS |
| Preset chips | PASS | PASS | PASS | PASS | PASS | PASS |
| Weekday dots | PASS | PASS | PASS | PASS | PASS | PASS |
| Every N + unit | PASS | PASS | PASS | PASS | PASS (`#1C1C1E` field, blue border) | PASS |
| Time / At minute / Starts / "On the 1st at" | PASS | PASS | PASS | native pickers | native | PASS |
| Ends + Number of runs / End date + Last run | PASS | PASS (no extra separator) | PASS | PASS | PASS | PASS |
| Next runs | PASS | PASS | PASS | PASS | PASS (text about (102,180,255) = `#64B0FF`; fill (37,62,88)) | PASS |
| Time zone line | PASS | PASS | PASS | PASS | PASS | PASS |
| Cron field | PASS | PASS (338×40, `#1C1C1E`, blue border) | PASS | PASS | PASS | PASS |
| Runs on (Model excluded) | PASS | PASS | data | PASS | PASS | native |

## Per-variant table

| Board | Sentence / sub-line | Controls | Next runs | Verdict |
|---|---|---|---|---|
| `tA2d-edit` | PASS | PASS | PASS | PASS |
| `tA2d-edit-once` | PASS | PASS (calendar, Time, 3 full shortcuts, footnote, time zone) | — | PASS |
| `-cron-5min` | PASS | PASS | PASS | PASS |
| `-7min` | PASS (exact gap) | PASS (Starts) | PASS | PASS |
| `-5hours` | PASS | PASS (Starts) | PASS | PASS |
| `-cron-hourly` | PASS | PASS (At minute :00) | PASS | PASS |
| `-daily` | PASS | PASS | PASS | PASS |
| `-cron-3days` | PASS | PASS (Starts) | PASS | PASS |
| `-3days-after` | PASS ("…, 5 times") | PASS (Last run = board) | PASS | PASS |
| `-weekly` | PASS | PASS | PASS | PASS |
| `-monthly` | PASS | PASS (white "On the 1st at") | PASS ("Nov 1 · 9:00") | PASS |
| `-custom` | PASS | PASS (bordered field) | PASS ("Nov 1 · 8:30", "Nov 15 · 8:30", "Dec 1 · 8:30") | PASS |
| `-after-n` | PASS ("…, 10 times") | PASS (Last run = board) | PASS | PASS |
| `-on-date` | PASS | PASS | PASS | PASS |

## Remaining (not counted)
- Ends row 46–47 pt vs 49, the card top inset 10 vs 12, and the time zone row 35 vs 33. These are 2–3 pt each and within row tolerance at 1x.
- The native controls listed in Scope.

## Files
- Base: `r4-base-01-toolbar.png` … `r4-base-07-runs-on.png`, `r4-full-edit.png`
- Variants: `r4-v-once-top.png`, `r4-v-once-lower.png`, `r4-v-5min-when-card.png`, `r4-v-7min-when-card.png`, `r4-v-5hours-when-card.png`, `r4-v-cron-hourly-when-card.png`, `r4-v-daily-when-card.png`, `r4-v-cron-3days-when-card.png`, `r4-v-3days-after-ends.png`, `r4-v-weekly-when-card.png`, `r4-v-monthly-when-card.png`, `r4-v-custom-when-card.png`, `r4-v-custom-field.png`, `r4-v-after-n-ends.png`, `r4-v-on-date-ends.png`
- Full screens: `r4-full-edit*.png` (14)
- Raw: `raw-r4/`
