# Verifier evidence: phone edit form vs `tA2d-edit*` boards

Date: 2026-10-15 16:40–17:35 HKT · Verifier: claude-design-verifier (independent) · Verdict: **FAIL**

## Scope and method
- Boards: all 14 phone edit boards on `http://127.0.0.1:8931/`, rendered in Chrome at 390×844 (`raw/design-*.jpg`). Expected values come from the board markup and its logic class (initial state, sentence and run rules).
  - `tA2d-edit` (Repeat, weekdays) and `tA2d-edit-once`.
  - `-cron-5min`, `-7min`, `-5hours`, `-cron-hourly`, `-daily`, `-cron-3days`, `-3days-after`.
  - `-weekly`, `-monthly`, `-custom`, `-after-n`, `-on-date`.
- App: the build installed on sim `1D902A87-…`, binary from 16:18:59. Opened "Daily repo review", tapped Edit, and drove the form itself to each variant:
  - the mode control and preset chips;
  - the typed Every field (5→7, hourly 1→5, daily 1→3);
  - weekday dots (Tue and Thu off for Mon/Wed/Fri);
  - Ends After N with Number of runs 5 or 10, and Ends On date;
  - the cron field, typed `30 8 1,15 * *` to match the board.

  The form was dismissed with Cancel and never saved. The fixture log shows only `POST /api/scheduled-tasks/preview` (27 calls). The task's schedule on the host is still `cron 0 9 * * 1-5`.
- Every FlowDeck call passed `-S`. Captures are 1x (`raw/app-*.png`).
- Excluded as data: Next-runs values and the relative-time subline (they come from the host preview and the clock), Host "Pro" vs "Eugenes-MacBook-Pro", and the default end date (app Nov 16, board Dec 31).
- Native translations, not deltas:
  - iOS 26 glass toolbar items, with no sheet grabber.
  - Title-case "When" and "Runs on" section headers, where the board has uppercase 13 pt.
  - System segmented controls for Once/Repeat and Ends.
  - Compact `DatePicker` capsules for Time, Starts and End date: white text and "Oct 16, 2026" format, where the board has blue text, "Fri, Oct 16" and a `#3A3A3C` rounded rect.
  - The graphical calendar for Once.
  - Inset list separators and 52 pt list rows for Name/Instructions (board 42 pt).

## Per-component table (shared by all Repeat variants)

| Component | Consistency | Structure | Copy | Type | Colour | Spacing |
|---|---|---|---|---|---|---|
| Toolbar: Cancel / Edit task / Save | PASS | PASS | PASS | PASS | **FAIL**: Save fill (0,145,255) with a **black** label, vs `#0A6EE0` with white | native |
| Name + Instructions card | PASS | PASS | PASS | minor: labels about 17 pt vs 15 | PASS (card 44,44,46 = `#2C2C2E`) | native row height |
| Once / Repeat | PASS | PASS | PASS | native | native | **FAIL** (see spacing) |
| Sentence + "how it runs" | PASS | PASS | PASS except Custom and Weekly (below) | PASS (21 pt semibold / 14 pt) | PASS | **FAIL**: 30 pt gaps vs 14/10 |
| Preset chips | PASS | PASS (7 chips, scrolls sideways) | PASS | PASS (14 pt) | **FAIL**: selected (0,145,255) vs `#0A6EE0`; idle (58,58,60) PASS | **FAIL**: 30 pt below vs 10 |
| Weekday dots | **FAIL**: the separator under the dots starts at x=45; every other row separator starts at x=32 | **FAIL**: extra separator between chips and dots (board has none) | PASS | PASS | PASS (on white, off 58,58,60) | — |
| Every N field + unit | PASS | PASS | PASS | PASS | minor: unit secondary grey (~148) vs `#D1D1D6` (~203); field fill = card vs `#1C1C1E` | PASS (64×34, blue border) |
| Time / At minute / Starts | PASS | PASS | PASS | native | native (hourly ":00" chip matches) | PASS |
| Ends + Number of runs / End date + "Last run" | PASS | PASS | PASS (Last run text matches exactly in after-n and 3days-after) | PASS | native | PASS |
| Next runs chips | PASS | PASS | **FAIL**: format (below) | PASS | **PARTIAL**: text (0,151,255) vs `#64B0FF`; fill (36,62,84) PASS | PASS |
| Time zone line | PASS | PARTIAL: section footer below the card vs a row inside the card | PASS | PASS | PASS | — |
| Runs on | PASS | PARTIAL: extra Model row and an extra paragraph (the feature doc says the Model row is kept on purpose) | data | PASS | PASS | — |
| Whole card | — | — | — | — | — | **FAIL**: the When card for Weekdays is 460 pt tall vs 402 pt. "Runs on" is below the fold; the board shows Host and Folder on the first screen |

## Per-variant table

| Board | Reached by | Sentence / sub-line | Controls shown | Next runs format | Verdict |
|---|---|---|---|---|---|
| `tA2d-edit` (weekdays) | opening Edit | PASS | PASS | "Fri 9:00 AM" vs "Fri 9:00" | PARTIAL (shared) |
| `tA2d-edit-once` | Once segment | PASS | PASS (calendar, Time, 3 shortcuts, footnote) | — | **FAIL**: the shortcut chips truncate to "Tomorrow 9…" and "Monday 9…" (board wraps to two rows, full labels; app chip text is 13 px cap vs 11) |
| `-cron-5min` | Minutes | PASS | PASS (Every, no Time row) | "5:05 PM" vs "10:15" | PARTIAL |
| `-7min` | Every = 7 | PASS ("Exact gap from Fri, Oct 16 at 9:00 AM") | PASS (Starts) | PASS | PASS (shared) |
| `-5hours` | Hourly, Every = 5 | PASS | PASS (Starts) | PASS | PASS (shared) |
| `-cron-hourly` | Hourly | PASS | PASS (At minute :00) | PASS | PASS (shared) |
| `-daily` | Daily | PASS | PASS | "Fri 9:00 AM" vs "Fri 9:00" | PARTIAL |
| `-cron-3days` | Daily, Every = 3 | PASS | PASS (Starts) | PASS ("Oct 16") | PASS (shared) |
| `-3days-after` | + After N, runs = 5 | PASS ("…, 5 times") | PASS; "Last run: Wed, Oct 28 at 9:00 AM" = board | PASS | PASS (shared) |
| `-weekly` | Weekly, Tue + Thu off | **minor**: "Every Mon, Wed, and Fri at 9:00 AM" vs "Every Mon, Wed and Fri at 9:00 AM" | PASS | "Fri 9:00 AM" vs "Fri 9:00" | PARTIAL |
| `-monthly` | Monthly | PASS | **PARTIAL**: adds a day-of-month menu "On the [1st] at"; the board has a fixed label "On the 1st at" | **FAIL**: "Nov 1" (time dropped) vs "Nov 1 · 9:00" | PARTIAL |
| `-custom` | Custom, cron typed | **FAIL**: "On days 1 and 15 of every month at 8:30 AM" vs "At 8:30 AM on the 1st and 15th of every month" | **FAIL**: the cron field is plain text on the card; the board has a 40 pt input with `#1C1C1E` fill and a 1 px `#0A84FF` border | **FAIL**: "Sun 8:30 AM", "Sun 8:30 AM", "Tue 8:30 AM" (two identical chips, no dates) vs "Nov 1 · 8:30", "Nov 15 · 8:30", "Dec 1 · 8:30" | FAIL |
| `-after-n` | Weekdays + After N, runs = 10 | PASS ("…, 10 times") | PASS; "Last run: Thu, Oct 29 at 9:00 AM" = board | "Fri 9:00 AM" | PARTIAL (shared) |
| `-on-date` | Weekdays + On date | PASS ("…, until <date>"; the date is a default value) | PASS (End date, Last run line) | "Fri 9:00 AM" | PARTIAL (shared) |

## Deltas (design vs app)
1. **Once shortcuts truncated.** Design "Tomorrow 9 AM", "Monday 9 AM", "Next Friday", 13 pt, wrapping to two rows. App: one row, 14 pt, "Tomorrow 9…" and "Monday 9…". Crop: `v-once-lower.png`.
2. **Custom next runs cannot be told apart.** For `30 8 1,15 * *` the host returns Nov 1, Nov 15, Dec 1 (timestamps 1793493000000…). The app labels them "Sun 8:30 AM", "Sun 8:30 AM", "Tue 8:30 AM". The board labels runs that are weeks apart by date ("Nov 1 · 8:30"). Monthly shows "Nov 1" but drops the time. Crops: `v-custom-when-card.png`, `v-monthly-when-card.png`.
3. **Custom cron field is unstyled.** Design: a bordered dark input. App: borderless monospaced text on the card. Crop: `v-custom-when-card.png`.
4. **Custom sentence wording** (copy above). Weekly adds an Oxford comma.
5. **Accent fill.** The selected preset chip and the Save fill are (0,145,255) system blue vs `#0A6EE0`. Save's label is black vs white (`raw/zoom-app-save.png`). In this same build the task view's Run now is exactly `#0A6EE0`, so this form does not use the shared token.
6. **Vertical spacing.** Segmented control to sentence: 30 vs 14. Sub-line to chips: 30 vs 10. Chips to dots: 30 (with a separator) vs 10. The toolbar sits 44 pt above the Name card vs 14. The When card is 460 vs 402 pt. Crops: `full-edit.png`, `base-03…05`.
7. **Separators.** Extra separator between chips and dots. The separator under the dots is inset to x=45; the rest start at x=32 (internal inconsistency). Measured in `raw/app-edit.png` and `raw/app-edit-weekly.png`.
8. **Next-run chip text** (0,151,255) vs `#64B0FF`. The time format adds AM/PM where the board omits it ("Fri 9:00", "10:15").
9. **Every unit label** is secondary grey vs `#D1D1D6`. The field fill is the card colour vs `#1C1C1E`.
10. **Monthly** adds a day-of-month menu that the board does not have.
11. **Time zone line** is a footer outside the card. **Runs on** has an extra Model row and a paragraph of text.

## Confirmed correct
- Every variant is reachable by driving the form, and every one shows the right control set:
  - Every N appears only for Minutes, Hourly and Daily.
  - Starts appears only for exact gaps (7 min, 5 h, 3 days).
  - Time or At minute appears only for clock-aligned schedules.
  - The Cron field appears only for Custom.
  - Number of runs and End date appear only for their Ends option.
- The sentence and "how it runs" sub-line follow the board's rules in 12 of 14 variants. Clock-aligned picks say "Runs at fixed clock times"; exact gaps say "Exact gap from Fri, Oct 16 at 9:00 AM".
- "Last run" lines for After N match the board exactly ("Wed, Oct 28" and "Thu, Oct 29").
- Typography of the sentence (21 pt semibold), chips (14 pt), the 64×34 Every field, card fill `#2C2C2E` and idle chip fill all match.
- Cancel closes without saving; the host saw no write.

## Not verified / notes
- The installed build is from 16:19. `shared/Tasks/TaskEditorViews.swift` was edited at 16:31 (its chip style now names `TaskColors.accentFill`), so a newer build may fix delta 5. This report covers the 16:19 build only.
- The Instructions page, the Time zone picker and the Folder picker were not opened; they are outside the boards.
- Save was not exercised, as instructed.
- FlowDeck's `type --clear` did not clear the Every field (it produced "75" and then "775"). I used double-tap to select first. This is a test-tool issue, not an app issue.

## Files
- Per-variant pairs (design on top, app below): `v-once-top.png`, `v-once-lower.png`, `v-5min-when-card.png`, `v-7min-when-card.png`, `v-5hours-when-card.png`, `v-hourly-when-card.png`, `v-daily-when-card.png`, `v-3days-when-card.png`, `v-3days-after-ends.png`, `v-weekly-when-card.png`, `v-monthly-when-card.png`, `v-custom-when-card.png`, `v-after-n-ends.png`, `v-on-date-ends.png`
- Base form components: `base-01-toolbar.png`, `base-02-details.png`, `base-03-when-mode-sentence.png`, `base-04-presets-days.png`, `base-05-time-ends.png`, `base-06-nextruns-tz.png`
- Full screens side by side: `full-edit*.png` (14)
- Raw: `raw/design-*.jpg`, `raw/app-*.png`, `raw/zoom-*`
