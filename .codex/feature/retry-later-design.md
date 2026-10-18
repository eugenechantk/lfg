# Retry later redesign

Implemented and verified locally on 2026-10-18. No commit, push, release, or production host restart.

## Request

Add a retry by delay or exact local time. First use a Claude design pass on the existing LFG UI Map canvas, then implement it with LFG's task components and patterns.

## Result

- Failed tasks keep Retry now and Ask to fix, with Retry later as a quiet clock action.
- A compact When card offers selected 35-minute, 45-minute, and 1-hour presets, custom whole minutes, or an exact local date and time.
- The preview and confirmation name the actual retry time. The local time zone stays visible.
- The pending card offers Retry now, Change time, and Cancel retry.
- Saving disables editing and repeat submission while keeping the progress button visible. An error preserves the input and shows recovery guidance.
- This is one extra run. The recurring schedule and finite run budget stay unchanged. The retry persists across host restarts and runs when the host is awake.

## Design source

Claude published the initial design before product edits, then corrected the light token translation after independent review.

- Canvas: https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD#page-retry-later
- Final version: 81, `1792297149-cc18`.
- Page: Retry later (Oct 18), `retry-later`.
- A fresh read matched all 16 retry boards byte for byte. The previous 147 boards and all 8 pages stayed unchanged.
- Exact exports: `.codex/design/retry-later/reference/project/`.
- Design notes: `.codex/design/retry-later/design.md` and `color-decision.md`.

Use existing task colors and native controls. The light idle fill uses native tertiary fill so unselected chips and invalid confirmation remain visible. Existing accent and failed-card colors stay intact. Complete validation sentences retain final periods; this punctuation translation is documented in the visual report. The source uses a Unicode ellipsis, which accessibility text may normalize.

## Success criteria

- [x] D1: Claude designs on the existing canvas before implementation; saved sources and canvas persistence verified.
- [x] D2: Actions, presets, preview, and compact sheets follow existing task components and tokens; independent comparison passes all nine criteria across 79 component pairs.
- [x] D3: Presets, custom minutes, exact time, invalid input, replacement, and cancellation work through real UI and the isolated production API.
- [x] D4: Delayed saving prevents duplicates and editing. Injected failure preserves input and permits recovery.
- [x] D5: Light/dark appearance, phone keyboard clearance, fitted iPad sheets, and narrow Mac sheets pass runtime review.

## Verification

| Check | Result | Evidence under `.codex/` |
|---|---|---|
| Swift tests | 469 tests in 70 suites passed | `design/retry-later/swift-tests-presentation.txt` |
| Host tests | 57 passed, 330 assertions | `design/retry-later/host-tests.txt` |
| Final signed iOS build | Passed | `design/retry-later/final-color-build.jsonl` |
| Final Mac build | Passed | `design/retry-later/desktop-build-final-color.txt` |
| Desktop checks | 254 passed | `design/retry-later/desktop-tests-final-color.txt` |
| Independent runtime audit | PASS | `evidence/20261018-120914-retry-design-ui-audit/evidence.md` |
| Independent visual comparison | PASS for native design intent; 79 pairs, nine criteria | `evidence/20261018-041032-retry-design-comparison/evidence.md` |
| Final source stability and whitespace | Passed | `design/retry-later/source-stability.txt`; `git diff --check` |

The deterministic presentation tests cover readable units, local midnight rollover, invalid minutes and past time, relative versus absolute time, and future-year display.

### Live behavior proof

- Repeated taps during a delayed save produced exactly one retry POST.
- Injected failure kept custom 90 minutes and showed recovery guidance; a later save succeeded.
- The Mac native picker changed 1:50 PM to 3:50 PM, and Return saved it. The regular next run, three-run budget, and scheduled run count stayed unchanged.
- Today at 1:00 AM showed future-time validation and disabled confirmation. AXPress and Return produced zero POSTs and zero persisted mutation. Changing the same draft to 2:00 PM restored the valid state; Cancel preserved the saved retry.
- Fresh final iPad captures 90 and 91 show final light fills and fitted 420x476pt / 420x526pt sheets. Older iPad captures 30 and 31 prove geometry only.
- Mac light/dark captures show a 400x700pt window, 360x338pt minutes sheet, and 360x384pt exact-time sheet.

The runtime report contains the capture manifest, recordings, request counts, and persisted state comparisons. The visual report preserves the initial failed comparison and the corrected reference baseline.

## Verification limits

The iOS compact time picker ignored synthetic taps during the past-time attempt. That specific iOS interaction is not claimed. The real Mac picker closed the live validation gap through the shared draft and validation UI.

Some unchanged states use explicitly identified earlier-build captures. Fresh final captures cover all corrected phone states and final iPad/Mac appearance. Mac point geometry comes from Accessibility because the screenshots include canvas scaling. Native optical font metrics and platform chrome are documented translations; exact internal font metrics are not certified. No physical-device or released-build claim is made.

## Implementation

The shared retry sheet reuses the task chip, segmented picker, date/time pill, color, and typography patterns. A pure LFGCore presentation model resolves copy from one clock and local time zone. The host retry endpoint and durable scheduler were retained.

The prior implementation snapshot is `.codex/design/retry-later/baseline.patch`. Product files changed only after the initial canvas design was verified.

## Isolation and cleanup

Verification used the production store, routes, and scheduler with inert agent launches on owned fixture ports 18963 and 18964. No real task was changed. Production port 8766 was never rebound or stopped.

Owned fixture and reference servers are stopped. Owned test apps and capture sessions are stopped. Other LFG apps remain running. The Mac's original dark appearance and locked state are restored. Cleanup record: `.codex/design/retry-later/cleanup.json`.
