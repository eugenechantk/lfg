# Verifier evidence, form round 3: phone edit form vs `tA2d-edit*` boards

Date: 2026-10-15 18:12–18:25 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PARTIAL**. Only spacing remains. Every component, copy, colour and control now matches in all 14 variants. The When card is 34 pt taller than the board's, mostly in the time zone row.

Earlier rounds: `evidence-form.md` (round 1), `evidence-form-r2.md` (round 2).

## Scope and method
- Boards: the same 14 phone edit boards (`raw/design-*.jpg`, rendered in Chrome; board files unchanged since 13:22).
- App build: the binary on sim `1D902A87-…` is from 18:11:28, newer than every Tasks source edit (the latest is `ScheduledTasksView.swift`, 18:10:32). 1x captures are in `raw-r3/`. Every FlowDeck call passed `-S`. I did not touch sim `D379DCF1-…`.
- Drive path, from "Daily repo review" → Edit:
  - Once.
  - Repeat → Minutes; Every 7; Hourly; Every 5; Daily; Every 3.
  - After N with 5 runs; Weekdays with 10 runs; On date; Never.
  - Weekly with Tue and Thu off; Monthly.
  - Custom with `30 8 1,15 * *`.
  - Weekdays → raw-touch Cancel.
- No writes: the fixture log shows only `POST /api/scheduled-tasks/preview` from me. Two push-registration POSTs come from the app relaunch. The task's schedule is still `cron 0 9 * * 1-5`, enabled.
- Regression check on the task view after Cancel: pixel diff against the round-4 capture changes only the countdown line (y 306–317).
- Excluded:
  - Data: next-run values, relative times, Host "Pro", the default end date.
  - The Model row.
- Native, as before: glass toolbar items, title-case section headers, system segmented controls, compact date and time pickers, the graphical calendar, inset list separators.

## Per-component table (all Repeat variants)

| Component | Consistency | Structure | Copy | Type | Colour | Spacing |
|---|---|---|---|---|---|---|
| Toolbar | PASS | PASS | PASS | PASS | **PASS**: Save white on (10,110,224) = `#0A6EE0` | native |
| Name + Instructions | PASS | PASS | PASS | PASS | PASS | native |
| Once/Repeat, sentence, sub-line | PASS | PASS | PASS | PASS | PASS | PASS (mode→sentence 14 vs 12; sub-line→chips 10 = 10) |
| Preset chips | PASS | PASS | PASS | PASS | PASS | PASS (chips→dots 10 = 10) |
| Weekday dots | PASS | PASS | PASS | PASS | PASS | minor: dots→separator 19 vs 11 |
| Every N + unit | PASS | PASS | PASS | PASS | **PASS**: field fill (28,28,30), the board's `#1C1C1E`; blue border; unit `#D1D1D6` | PASS |
| Time / At minute / Starts / "On the 1st at" | PASS | **PASS**: Monthly label is plain white text like the board | PASS | native pickers | native | PASS (Time row 52 vs 51) |
| Ends + Number of runs / End date + Last run | PASS | **PASS**: no separator between Ends and its follow-up row, as on the board | PASS | PASS | **PASS**: runs field fill `#1C1C1E` | PASS (Ends row 52 vs 49) |
| Next runs | PASS | PASS | PASS | PASS | PASS | PASS (64 = 64) |
| Time zone line | PASS | PASS (in the card) | PASS | PASS | PASS | **FAIL**: row 53 vs 33 (text 22 below the separator vs 11; 21 above the card bottom vs 12) |
| Cron field (Custom) | PASS | **PASS**: 338×40 box, `#1C1C1E` fill, 1 px blue border; monospaced 17 pt with inner padding | PASS | PASS | PASS | PASS |
| Runs on (Model row excluded) | PASS | PASS (Host, Folder) | data | PASS | PASS | native |
| Whole When card (Weekdays) | — | — | — | — | — | **PARTIAL**: 436 vs 402 pt (round 2: 473). Card top to segmented control 18 vs 12 |

## Per-variant table

| Board | Sentence / sub-line | Controls | Next runs | Verdict |
|---|---|---|---|---|
| `tA2d-edit` | PASS | PASS | PASS ("Fri 9:00") | PASS (shared spacing) |
| `tA2d-edit-once` | PASS | PASS (calendar, Time, 3 full shortcuts, footnote, time zone); unchanged from round 2 | — | PASS |
| `-cron-5min` | PASS | PASS | PASS ("6:20") | PASS |
| `-7min` | PASS (exact gap) | PASS (Starts) | PASS | PASS |
| `-5hours` | PASS | PASS (Starts) | PASS | PASS |
| `-cron-hourly` | PASS | PASS (At minute :00) | PASS ("7:00 PM") | PASS |
| `-daily` | PASS | PASS | PASS | PASS |
| `-cron-3days` | PASS | PASS (Starts) | PASS ("Oct 16") | PASS |
| `-3days-after` | PASS ("…, 5 times") | PASS (Last run "Wed, Oct 28 at 9:00 AM" = board) | PASS | PASS |
| `-weekly` | PASS ("Every Mon, Wed and Fri at 9:00 AM") | PASS | PASS | PASS |
| `-monthly` | PASS | PASS (white label) | PASS ("Nov 1 · 9:00") | PASS |
| `-custom` | PASS | PASS (bordered field) | PASS ("Nov 1 · 8:30", "Nov 15 · 8:30", "Dec 1 · 8:30") | PASS |
| `-after-n` | PASS ("…, 10 times") | PASS (Last run "Thu, Oct 29 at 9:00 AM" = board) | PASS | PASS |
| `-on-date` | PASS | PASS (End date, Last run line) | PASS | PASS |

## Remaining deltas (design vs app)
1. **Time zone row is taller:** 33 pt vs 53 pt. Text sits 11 pt below the separator on the board vs 22 in the app, and 12 pt above the card's bottom edge vs 21. Crop: `r3-base-06-nextruns-tz.png`.
2. **Gap under the weekday dots:** 11 pt vs 19 pt.
3. **Card top inset:** 12 pt vs 18 pt above the segmented control.

Together with Ends (+3) and Time (+1), the When card for Weekdays is 436 pt vs 402. On the first screen the board shows Host and Folder in full; the app shows Host and the top of Folder. Crop: `r3-full-edit.png`.

## Fixed since form round 2 (re-measured)
- Save label is white (`raw-r3/zoom-app-save.png`).
- The Custom cron field has its bordered dark input box, focused and unfocused (`r3-v-custom-field.png`, `r3-v-custom-focused.png`).
- The Every and Number-of-runs fields use `#1C1C1E`.
- Monthly's "On the 1st at" is a plain white label.
- The separator between Ends and Number of runs / End date is gone.
- Row heights: Time 66 → 52 and Ends 61 → 52 (board 51 and 49). Next runs 78 → 64 (board 64). The When card is 473 → 436 (board 402).

## Files
- Base: `r3-base-01-toolbar.png` … `r3-base-06-nextruns-tz.png`
- Variants: `r3-v-once-top.png`, `r3-v-once-lower.png`, `r3-v-5min-when-card.png`, `r3-v-7min-when-card.png`, `r3-v-5hours-when-card.png`, `r3-v-hourly-when-card.png`, `r3-v-daily-when-card.png`, `r3-v-3days-when-card.png`, `r3-v-3days-after-ends.png`, `r3-v-weekly-when-card.png`, `r3-v-monthly-when-card.png`, `r3-v-custom-when-card.png`, `r3-v-custom-field.png`, `r3-v-custom-focused.png`, `r3-v-after-n-ends.png`, `r3-v-on-date-ends.png`
- Full screens: `r3-full-edit*.png` (14)
- Raw: `raw-r3/`
