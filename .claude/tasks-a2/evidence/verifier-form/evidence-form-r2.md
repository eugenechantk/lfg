# Verifier evidence, form round 2: phone edit form vs `tA2d-edit*` boards

Date: 2026-10-15 17:55–18:08 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PARTIAL**. Every round-1 defect is fixed. Three visible differences remain:

1. The Custom cron field has no input box.
2. The Save label is black, not white.
3. The lower rows of the When card are 12–20 pt taller each.

Round 1: `evidence-form.md`.

## Scope and method
- Boards: the same 14 phone edit boards, rendered in Chrome (`raw/design-*.jpg`, unchanged since 13:22).
- App build: the binary on sim `1D902A87-…` is from 17:42:53, newer than every Tasks source edit. 1x captures are in `raw-r2/`.
- Same drive path as round 1, starting from "Daily repo review" → Edit:
  - Once segment.
  - Repeat → Minutes; Every 7; Hourly; Every 5; Daily; Every 3.
  - After N with 5 runs; Weekdays with 10 runs; On date; Never.
  - Weekly with Tue and Thu off; Monthly.
  - Custom with `30 8 1,15 * *` (Select All, then typed).
- Closed with raw-touch Cancel. The host log shows only `POST /api/scheduled-tasks/preview` (22 calls); the task's schedule is still `cron 0 9 * * 1-5`. Every FlowDeck call passed `-S`.
- Excluded:
  - Data: next-run values, relative times, Host "Pro", and the default end date.
  - The Model row under "Runs on" (deliberate per the decision log).
- Native, as before:
  - Glass toolbar items.
  - Title-case section headers.
  - System segmented controls.
  - Compact date and time pickers, the graphical calendar, and inset list separators.

## Per-component table (all Repeat variants)

| Component | Consistency | Structure | Copy | Type | Colour | Spacing |
|---|---|---|---|---|---|---|
| Toolbar | PASS | PASS | PASS | PASS | **PARTIAL**: Save fill now (10,110,224) = `#0A6EE0`; label still **black** vs white | native |
| Name + Instructions | PASS | PASS | PASS | PASS (labels 15 pt) | PASS | native rows |
| Once / Repeat + sentence + sub-line | PASS | PASS | PASS (all 14) | PASS | PASS | PASS: 14 / 10 vs board 12 / 10 |
| Preset chips | PASS | PASS | PASS | PASS | PASS: selected (10,110,224); idle (58,58,60) | PASS: 10 pt to the dots |
| Weekday dots | PASS (no separator above; separator below at x=32 like the others) | PASS | PASS | PASS | PASS | minor: 18 pt to the separator vs 10 |
| Every N + unit | PASS | PASS | PASS | PASS | PASS: unit (214) = `#D1D1D6`; minor: field fill = card (44,44,46) vs `#1C1C1E` | PASS |
| Time / At minute / Starts / "On the 1st at" | PASS | minor: Monthly's "On the 1st at" is a menu drawn in system blue (0,146,253); the board has a plain white label | PASS | native | native | — |
| Ends + Number of runs / End date + Last run | PASS | minor: separator between Ends and the follow-up row (board has none) | PASS (Last run matches exactly) | PASS | minor: runs field fill = card vs `#1C1C1E` | — |
| Next runs | PASS | PASS | **PASS**: "Fri 9:00", "6:00", "Nov 1 · 9:00", "Nov 15 · 8:30" match the board's format | PASS | **PASS**: text about (101,178,255) = `#64B0FF`; fill (37,62,88) | PASS |
| Time zone line | PASS | **PASS**: inside the card under a separator | PASS | PASS | PASS | — |
| Runs on (Model row excluded) | PASS | **PASS**: Host and Folder; the extra paragraph is gone | data | PASS | PASS | native |
| Whole When card | — | — | — | — | — | **PARTIAL**: 473 vs 402 pt (see below) |

## Per-variant table

| Board | Sentence / sub-line | Controls | Next runs format | Verdict |
|---|---|---|---|---|
| `tA2d-edit` (weekdays) | PASS | PASS | PASS ("Fri 9:00") | PASS (shared items) |
| `tA2d-edit-once` | PASS | PASS (calendar, Time, three shortcuts in full: "Tomorrow 9 AM", "Monday 9 AM", "Next Friday", 13 pt; footnote; time zone) | — | PASS |
| `-cron-5min` | PASS | PASS | PASS ("6:00") | PASS |
| `-7min` | PASS (exact gap) | PASS (Starts) | PASS ("Fri 9:00 AM") | PASS |
| `-5hours` | PASS | PASS (Starts) | PASS | PASS |
| `-cron-hourly` | PASS | PASS (At minute :00) | PASS ("6:00 PM") | PASS |
| `-daily` | PASS | PASS | PASS ("Fri 9:00") | PASS |
| `-cron-3days` | PASS | PASS (Starts) | PASS ("Oct 16") | PASS |
| `-3days-after` | PASS ("…, 5 times") | PASS (Last run "Wed, Oct 28 at 9:00 AM" = board) | PASS | PASS |
| `-weekly` | **PASS**: "Every Mon, Wed and Fri at 9:00 AM" (no extra comma) | PASS | PASS | PASS |
| `-monthly` | PASS | minor: menu instead of a label | **PASS**: "Nov 1 · 9:00" | PASS (minor) |
| `-custom` | **PASS**: "At 8:30 AM on the 1st and 15th of every month" | **FAIL**: the cron field has no input box (below) | **PASS**: "Nov 1 · 8:30", "Nov 15 · 8:30", "Dec 1 · 8:30" | PARTIAL |
| `-after-n` | PASS ("…, 10 times") | PASS (Last run "Thu, Oct 29 at 9:00 AM" = board) | PASS | PASS |
| `-on-date` | PASS (default date is data) | PASS | PASS | PASS |

## Remaining deltas (design vs app)
1. **Cron field has no input box.** Design: a 40 pt field with `#1C1C1E` fill, a 1 px `#0A84FF` border and 12 pt inner padding. App: monospaced text sitting directly on the card. There is still no box when the field is focused; only the caret shows. Crops: `r2-v-custom-when-card.png`, `r2-v-custom-focused.png`.
2. **Save label is black.** Design: white on `#0A6EE0`. App: black on (10,110,224). Crop: `raw-r2/zoom-app-save.png`.
3. **Lower When rows are taller.**

   | Row | Board | App |
   |---|---|---|
   | Time | 51 pt | 66 pt |
   | Ends | 49 pt | 61 pt |
   | Next runs | 64 pt | 78 pt |
   | Time zone | 33 pt | about 53 pt |
   | Dots → first separator | 10 pt | 18 pt |
   | Whole When card (Weekdays) | 402 pt (254→656) | 473 pt (303→776) |

   The upper part (mode control to dots) matches within 2 pt. The extra height comes from native form-row padding. On the first screen the board shows Host and Folder; the app shows only "Runs on" and the top of Host. Crop: `r2-full-edit.png`.
4. **Minor:**
   - The Every and Number-of-runs fields use the card fill, not `#1C1C1E`.
   - Monthly's "On the 1st at" is a blue menu, where the board has a white label.
   - The app adds a separator between Ends and the Number of runs / End date row.

## Fixed since form round 1 (re-measured)
- **Once shortcuts:** full labels in one row at 13 pt; no truncation.
- **Custom:**
  - The sentence wording matches the board.
  - Next runs carry dates, with no duplicate "Sun 8:30 AM" chips.
- **Monthly:** next runs show the time ("Nov 1 · 9:00").
- **Weekly:** no extra comma.
- **Accent fill:** the selected chip and the Save fill are `#0A6EE0`.
- **Spacing:** the gaps around the sentence, chips and dots are now 10–14 pt (were 30). The chip/dots separator is gone. Separator insets are all x=32.
- **Next-run chips:** text `#64B0FF`, and the format follows the board ("Fri 9:00", "10:15"-style).
- **Every unit** label is `#D1D1D6`.
- **Time zone** line is inside the card. The extra "Runs on" paragraph is removed.

## Files
- Base components: `r2-base-01-toolbar.png` … `r2-base-06-nextruns-tz.png`
- Variants: `r2-v-once-top.png`, `r2-v-once-lower.png`, `r2-v-5min-when-card.png`, `r2-v-7min-when-card.png`, `r2-v-5hours-when-card.png`, `r2-v-hourly-when-card.png`, `r2-v-daily-when-card.png`, `r2-v-3days-when-card.png`, `r2-v-3days-after-ends.png`, `r2-v-weekly-when-card.png`, `r2-v-monthly-when-card.png`, `r2-v-custom-when-card.png`, `r2-v-custom-focused.png`, `r2-v-after-n-ends.png`, `r2-v-on-date-ends.png`
- Full screens: `r2-full-edit*.png` (14)
- Raw: `raw-r2/` (app), `raw/design-*.jpg` (boards)
