# Verifier evidence, final regression 2: Tasks list + task view vs A2 dark boards

Date: 2026-10-15 19:05–19:12 HKT · Verifier: claude-design-verifier (independent) · Verdict: **PASS**. The one delta from the previous final pass (the model chip showing the raw id "opus") is fixed, and nothing else changed.

Earlier rounds: `evidence.md`, `evidence-r2.md`, `evidence-r3.md`, `evidence-r4.md` (PASS), `evidence-final.md` (PARTIAL: model chip).

## Scope and setup
- Boards: `tA2d-list`, `tA2d-detail` (+ paused), `tA2d-detail-failed` (+ retrying), `tA2d-detail-input` (+ answered). Board files are unchanged since 13:22.
- App build: the binary on sim `1D902A87-…` is from 19:04:53, newer than every Tasks source edit (latest: `TaskDetailViews.swift`, 19:04:37). Re-checked after the pass: unchanged. Every FlowDeck call passed `-S`. Sim `D379DCF1-…` was shut down, as you said.
- Fixture: the host started in its seeded state.
  - Pause was undone with Resume; the host shows `enabled: true, pausedAt: null`.
  - After Retry and Answer, I reset the host. It is now PID 55465, logging to `fixture-8932.log` in the session scratchpad.
- Full pass:
  - List with the Pro filter: top, bottom, Closed expanded.
  - Task view in all six states: next run, paused, failed, retrying, waiting, answered.
- Method: each capture is diffed against the previous final pass's capture of the same state, and every changed band is checked against the board.

## Diff against the previous final pass

| State | Changed bands | Cause | Judgement |
|---|---|---|---|
| List top | y 403–412 | Running row's elapsed time (data) | PASS |
| Dock + badge | none | — | PASS |
| List Paused / Closed | y 26–39 | Running row's elapsed time (data) | PASS |
| Next run | y 306–317 | Countdown (data) | PASS |
| Paused | none | — | PASS |
| Failed | y 203–216 | Model chip "opus" → "Opus" | **PASS** (fixed) |
| Retrying | y 203–216, 278–294, 474–487 | Model chip; start time and retry row time (data) | PASS |
| Waiting | y 259–268 | Elapsed "9 h 10 min" (data) | PASS |
| Answered | none | — | PASS |

The previous final pass judged every other component against the boards, and all passed. No other pixel changed, so those judgements stand.

## Model chip (the previous delta)
- Design: "Opus 5.5". App: "Opus" with the same C badge (`final2-failed-03-header.png`).
- The casing and formatting now match the board's style. "5.5" cannot come from the stored alias `opus` (the stand-in host serves no model catalog), so that difference is data.

## Extra observation (list, while navigating)
After Retry, the list shows "Nightly dependency audit" in Active with "Now <1 min" and "Running · started 7:09 PM" in green, as the board does for running rows. The Tasks badge dropped to 2, the Needs input count across all hosts. It stays consistent with the all-hosts rule.

## Remaining (not counted, unchanged)
- Failed result text is the fixture's full error sentence ("Failed · Opus 5.5 was unavailable, so no sessio…").
- Filled Tasks dock icon (the board uses an outline).
- The schedule line and the "by next run" hint are slightly darker than `#A1A1A6` at 1x (low confidence).

## Files
- Pairs: `final2-failed-03-header.png`, `final2-failed-01-status-card.png`
- Full screens: `final2-full-list-top.png`, `final2-full-list-paused-closed.png`, `final2-full-view-{next,paused,failed,retrying,waiting,answered}.png`
- Raw: `raw-final2/` (incl. `zoom-design-model-chip.png`, `zoom-app-model-chip.png`)
