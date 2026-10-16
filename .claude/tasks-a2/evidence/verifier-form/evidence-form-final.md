# Verifier evidence, final regression: phone edit form vs `tA2d-edit*` boards

Date: 2026-10-15 18:58–19:05 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PASS**. All 14 variants match their boards, and the form is unchanged from round 4 apart from data.

Earlier rounds: `evidence-form.md`, `evidence-form-r2.md`, `evidence-form-r3.md`, `evidence-form-r4.md` (PASS).

## Scope and method
- Boards: the 14 `tA2d-edit*` boards (`raw/design-*.jpg`, unchanged since 13:22).
- App build: the binary on sim `1D902A87-…` is from 18:46:56, newer than `ScheduleDraft.swift` (18:46:16, the Weekly day-range change) and the other in-scope sources. Every FlowDeck call passed `-S`. I did not touch sim `D379DCF1-…`.
- Drive path, from "Daily repo review" → Edit:
  - Once.
  - Repeat → Minutes; Every 7; Hourly; Every 5; Daily; Every 3.
  - After N with 5 runs; Weekdays with 10 runs; On date; Never.
  - Weekly, also checking Mon–Fri and Mon–Wed before the board's Mon/Wed/Fri; Monthly.
  - Custom with `30 8 1,15 * *`.
  - Raw-touch Cancel.
- No save: the host log shows two task POSTs at 10:56:50 and 10:57:00 UTC. Those are the task view's Pause and Resume, made before the form opened (the first preview request is 10:57:17). Everything after is preview calls only. The task's schedule is still `0 9 * * 1-5`.
- Excluded: data (next-run values, relative times, Host, default end date) and the Model row. Native controls as in round 4.

## Regression diff against round 4 (all 14 variants)

| Capture | Changed bands | Cause |
|---|---|---|
| Base (Weekdays) | none | — |
| Once (top) | y 388–397 | Relative time "In 14 h 3 min" (data) |
| Once (lower) | none | — |
| Every 5 minutes | y 590–598 | Next-run times (data) |
| 7 min, 5 hours, hourly, daily, 3 days, 3 days + 5 runs, weekly, monthly, custom, after N, on date | none | — |

Round 4 judged every component of these screens PASS against the boards (`evidence-form-r4.md`). With no non-data pixel changes, those judgements carry over. Fresh paired crops for the variants touched by this build's changes are `final-v-weekly-when-card.png`, `final-v-custom-when-card.png` and `final-v-once-lower.png`, plus `final-full-*.png` for all 14.

## Weekly day reading (changed in this build)
- Mon/Wed/Fri: "Every Mon, Wed and Fri at 9:00 AM". This matches the board.
- Mon–Fri picked by dots: "Every Mon, Tue, Wed, Thu and Fri at 9:00 AM".
- Mon–Wed: "Every Mon, Tue and Wed at 9:00 AM".

The board's weekly rule joins the chosen days with ", " and " and ", and never collapses them into a range. The app follows that rule. Next runs for Mon–Wed are "Mon 9:00, Tue 9:00, Wed 9:00".

## Per-variant verdicts
All PASS:
- `tA2d-edit`, `-once`, `-cron-5min`, `-7min`, `-5hours`, `-cron-hourly`, `-daily`.
- `-cron-3days`, `-3days-after`, `-weekly`, `-monthly`, `-custom`, `-after-n`, `-on-date`.

Remaining (not counted, unchanged from round 4): the Ends row is 2–3 pt shorter than the board's, and the agreed native controls.

## Files
- `final-full-edit.png` and `final-full-edit-*.png` (14 full-screen side-by-sides)
- `final-v-weekly-when-card.png`, `final-v-custom-when-card.png`, `final-v-once-lower.png`
- Raw: `raw-final/` (includes `app-edit-weekly-all5.png`, `app-edit-weekly-mon-wed.png`)
