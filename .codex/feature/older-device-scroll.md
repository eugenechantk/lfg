# Older-device scrolling

Product-tier performance fix for Sessions, Tasks, and transcripts.

## User story

Scrolling should respond promptly on Eugene's older iPad mini, including long lists and rich transcripts.

## Success criteria

- Capture baseline and changed scrolling on iPhone SE (2nd generation) and iPad mini (5th generation), iOS 26.3.1.
- Use identical optimized builds, synthetic data, gestures, and measurement windows for each comparison.
- Attribute expensive app work with sampled stacks. Remove measured waste without changing list ordering, navigation, schedules, or transcript selection.
- Add focused regression coverage for changed logic and run the relevant existing tests.
- Obtain independent runtime and performance verification after implementation.

## Test strategy

Use a read-only local host fixture, real production views, process sampling, and recordings. Swift tests cover presentation and clock invariants. Paired profiles verify reduced repeated work. Simulator results do not establish physical A12/A13 performance.

## Implementation and evidence

See `.codex/performance/20261017-older-scroll/`.

- `SessionRowClockTests` checks the next visible age boundary, all unit transitions, future dates, and invalid input.
- `ScrollPresentationPerformanceTests` retains a Release benchmark for formatting 100 task rows.
- Existing task presentation and schedule tests retain the list wording, ordering, and time-zone behavior.
- The full core suite passed 646 XCTest cases (one skipped) and 457 Swift Testing cases.
- The shared macOS app built successfully and passed 204 headless feature checks.
- Independent performance audit passed CPU-waste reduction. Physical frame pacing remains unverified because the simulator rejects Hitches.
- Independent visual/runtime audit: PASS on both simulators. It verified scrolling, navigation, search, collapse/reopen, task refresh, native copy/paste, horizontal code/table scrolling, clock transitions, and portrait-landscape-portrait transcript reflow.
- Visual evidence: `.codex/evidence/20261017-104200-older-scroll-visual-audit/evidence.md`. Performance evidence: `.codex/evidence/20261017-older-scroll-performance-audit.md`.

The fixes defer conditional task row creation, isolate expensive labels from parent updates, suppress unchanged task publications, schedule session clocks at visible boundaries, and reuse per-view text measurements. The iPad mini Time Profiler captures show 22% less main-thread CPU in Tasks and 21% less in transcripts.

## Residual risks

The Mac supplies simulator compute and graphics. A USB-connected iPad mini is available, but this pass uses isolated simulator data and does not replace its installed app. Commit and TestFlight release were authorized on 2026-10-17. Pushing was not requested.
