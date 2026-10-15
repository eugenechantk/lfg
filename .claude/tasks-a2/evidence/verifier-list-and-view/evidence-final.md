# Verifier evidence, final regression: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 18:50–19:05 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PARTIAL**. Everything matches except one copy delta: the model chip shows the raw id "opus" (now visible because the fresh data gives a task a model). The sparkle glyphs are fixed.

Earlier rounds: `evidence.md`, `evidence-r2.md`, `evidence-r3.md`, `evidence-r4.md` (PASS).

## Scope and setup
- Boards: `tA2d-list`, `tA2d-detail` (+ paused), `tA2d-detail-failed` (+ retrying), `tA2d-detail-input` (+ answered). Board files are unchanged since 13:22.
- App build: the binary on sim `1D902A87-…` is from 18:46:56.
  - It is newer than the in-scope sources: `TaskDetailViews.swift` 18:44:35, `ScheduledTasksView.swift` 18:44:52, `ScheduleDraft.swift` 18:46:16.
  - `TaskChatViews.swift` was edited at 18:47:25, after the build. The chat sheet is outside this scope, so that edit is unverified.
- Fixture: the host was restarted by the coordinator at 18:38 with fresh data ("Nightly dependency audit" model `opus`). I reset it once after Retry and Answer; it is now PID 8555, logging to `fixture-8932.log` in the session scratchpad. Pause was undone with Resume; the host shows `pausedAt: null`.
- Full pass:
  - List with the Pro filter: top, bottom, Closed expanded.
  - Task view in all six states: failed, retrying, waiting, answered, next run, paused.
- Method: each capture is diffed against the round-4 capture of the same state, and every changed band is inspected. Paired crops against the boards are in this folder (`final-*`). Every FlowDeck call passed `-S`. I did not touch sim `D379DCF1-…`.

## What changed since round 4 (pixel diff bands, then judged)

| State | Changed bands | Cause | Judgement |
|---|---|---|---|
| List top | y 403–436 | Running row's start time and elapsed (data) | — |
| List Paused/Closed | y 26–39 | Running row's elapsed (data) | — |
| Dock + badge | none | — | PASS |
| Next run | y 306–317, 798–817 | Countdown (data); Ask-bar sparkle | **PASS**: outline sparkle like the board |
| Paused | y 798–817 | Ask-bar sparkle | PASS |
| Failed | y 203–216, 369–380, 798–817 | Model chip; Ask-to-fix sparkle; Ask-bar sparkle | Sparkles **PASS**; chip **delta** (below) |
| Retrying | y 203–216, 278–294, 474–487, 798–817 | Chip; start times (data); sparkle | as above |
| Waiting | y 259–268, 798–817 | Elapsed "8 h 53 min" (data); sparkle | PASS |
| Answered | y 798–817 | Sparkle | PASS |

Everything else is pixel-identical to round 4, which passed every component.

## Per-component table

| Component / state | Consistency | Structure | Copy | Type | Colour | Glyphs | Spacing |
|---|---|---|---|---|---|---|---|
| Section headers | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Rows, Paused rows, Closed rows | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| Dock + badge | PASS | PASS | PASS | PASS | PASS | minor: filled Tasks icon (unchanged) | PASS |
| Task view top bar | PASS | PASS | — | — | native | native | PASS |
| Title, schedule, chips | PASS | PASS | **FAIL (minor)**: model chip "opus" vs board "Opus 5.5" | PASS | PASS | PASS | PASS |
| Card: next run / paused / failed / retrying / waiting / answered | PASS | PASS | PASS | PASS | PASS | **PASS**: Ask-to-fix sparkle is now an outline star | PASS |
| Instructions | PASS | PASS | PASS | PASS | PASS | — | PASS |
| Runs header + timeline | PASS | PASS | minor: full error text (unchanged) | PASS | PASS | PASS | PASS |
| Ask bar + fade | PASS | PASS | PASS | PASS | native glass | **PASS**: outline two-star sparkle like the board | PASS |

## Delta
1. **Model chip shows the raw model id.**
   - Design: "Opus 5.5" with the C badge. App: "opus" (lowercase) with the C badge. Crop: `final-failed-03-header.png`.
   - Cause in source: the chip renders `task.modelLabel`, which returns the stored id unchanged (`ScheduledTasks.swift:328`). The app already has `ModelName.display` (`TaskChangeDiff.swift:44`), which the chat change card uses and which would give "Opus".
   - The "5.5" version cannot come from the alias "opus" without a model catalog, and the stand-in host serves no `/api/models`. So I count only the casing and formatting as the app's delta; the version number is data.

## Confirmed
- Sparkle glyphs match the board's outline style in the Ask bar (every state) and in Ask to fix (`final-sparkles-design-left-app-right.png`, design left, app right).
- No regressions from the dead-code removal: no other pixel changed in any list or task-view state.

## Files
- Pairs: `final-list-01-needs-input.png`, `final-list-02-active.png`, `final-list-03-dock.png`, `final-list-04-paused.png`, `final-list-05-closed.png`, `final-next-01…06`, `final-paused-01/02`, `final-failed-01/02/03/04`, `final-retrying-01/02/03`, `final-waiting-01/02/03`, `final-answered-01-card.png`, `final-sparkles-design-left-app-right.png`
- Raw: `raw-final/`
