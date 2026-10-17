# Older-device scroll investigation

The fixes remove repeated task formatting and text measurement from scrolling. Independent Time Profiler captures show 22% less main-thread CPU in Tasks and 21% less in transcripts on the iPad mini simulator.

## Confirmed bottlenecks

- Tasks formatted offscreen rows while List counted conditional rows. Parent updates also rebuilt retained task rows behind the transcript.
- Five-second task polls published equivalent arrays in arbitrary host order.
- Session rows woke every second even when their age showed hours or days.
- Selectable transcript text repeated TextKit measurements for identical width proposals. Short user bubbles also made an unused sizing call.

## Fixes

- Give List a concrete task row. Put expensive presentation behind an Equatable label; keep live actions outside it.
- Normalize and compare complete task snapshots and host configuration before publication. A minute timeline keeps task dates current.
- Wake each session clock at its next visible second, minute, hour, day, or week boundary.
- Cache up to eight measurements per text view. Clear them on content, style, width-dependent rendering, or font-category changes.

## Controlled comparisons

Both simulators run iOS 26.3.1: iPhone SE (second generation), 375×667; iPad mini (fifth generation), 768×1024. Builds use the same optimized Debug settings. The local fixture contains 320 sessions, 200 tasks, and 180 rich transcript messages. Each scenario uses eight explicit-coordinate swipes, four forward and four reverse.

The 20-second process CPU windows include all threads and accessibility automation:

| Simulator | Surface | Before | After | Change |
|---|---|---:|---:|---:|
| iPhone SE 2 | Sessions | 4.49 s | 3.02 s | −33% |
| iPhone SE 2 | Tasks | 4.91 s | 3.09 s | −37% |
| iPhone SE 2 | Transcript | 4.87 s | 4.39 s | −10% |
| iPad mini 5 | Sessions | 3.78 s | 3.50 s | −7% |
| iPad mini 5 | Tasks | 4.63 s | 3.99 s | −14% |
| iPad mini 5 | Transcript | 6.90 s | 6.74 s | −2% |

Treat the last result as unchanged in a single noisy comparison. Its non-waiting, non-accessibility main-thread sample share fell from 24.54% to 21.48%. Accessibility overhead increased. Session measurements use idle records; they do not represent every active-session mix.

Independent Time Profiler plus Hangs captures repeat Tasks and transcripts over about 22.6 seconds:

| iPad mini metric | Before | After | Change |
|---|---:|---:|---:|
| Tasks, main-thread CPU | 4,648 ms | 3,621 ms | −22% |
| Tasks, excluding accessibility | 3,690 ms | 2,655 ms | −28% |
| Task formatting in Tasks | 416 ms | 15 ms | −96% |
| Transcript, main-thread CPU | 7,706 ms | 6,067 ms | −21% |
| Transcript, excluding accessibility | 5,701 ms | 3,995 ms | −30% |
| Transcript text sizing | 875 ms | 32 ms | −96% |
| Transcript table-cell layout | 652 ms | 74 ms | −89% |
| Hidden task formatting | 215 ms | 2 ms | −99% |

These are sampled CPU weights, not contiguous stall durations. Do not add inclusive function weights: their stacks can overlap. Remaining transcript cost is mostly SwiftUI layout and Core Animation. No remaining individual app function exceeds 77 sampled main-thread milliseconds in that window.

All four Time Profiler windows report zero hangs above 250 milliseconds. Animation Hitches returned “Hitches is not supported on this platform.” Its partial capture is excluded. Zero hangs does not establish smooth frame pacing. Encoded recording durations and frame timestamps also vary. Videos prove content and gestures, not frame rate; raw metadata is in `review-video-metadata.json`.

## Verification

- Full core suite: 646 XCTest cases, one skipped; 457 Swift Testing cases.
- Final focused suite: 32 cases across clock, task presentation, and schedule descriptions.
- Final optimized iOS build passed. Shared desktop build passed 204 headless feature checks.
- Independent visual/runtime audit: PASS on both simulators. It verified scrolling, selection and copy/paste, code/table scrolling, navigation, search, collapse/reopen, live task updates, the 51s-to-1m clock transition, and portrait-landscape-portrait reflow.
- Visual report: `.codex/evidence/20261017-104200-older-scroll-visual-audit/evidence.md`. CPU audit: `.codex/evidence/20261017-older-scroll-performance-audit.md`.
- The fixture servers stopped after verification. The task suffix control is empty. The Mac was locked after the narrow cursor-free orientation fallback.

## Evidence map

- `summary.json`, `summarize.py`: process CPU and main-thread sample classification.
- `traces/summary.json`, `parse_traces.py`: genuine Time Profiler and Hangs exports.
- `before-*` and `after-*`: raw samples, metrics, screenshots, and recordings. Valid baseline labels are `before-iphone-sessions-final`, `before-iphone-tasks`, `before-iphone-transcript-final`, `before-ipad-sessions`, `before-ipad-tasks-final`, and `before-ipad-transcript`.
- `iteration1/`: rejected first revision. It did not remove enough hidden task work. It is excluded from final results.
- Earlier baseline folders outside the six labels had capture or navigation failures. They are excluded.
- `preexisting.patch`: preserves the user's pre-existing edits; it is never served in the review page.
- `core-tests.txt`, `v2-regression-tests.txt`, `desktop-tests-v2-final.txt`, `after-build-v2-final.jsonl`: build and test logs.

## Limits

The simulator uses the Mac's CPU and graphics. It does not emulate A12/A13 speed. A USB-connected physical iPad mini is available, but its installed app was not replaced. Physical-device frame pacing remains unverified. No commit, push, or release was made.

[Apple: Optimize SwiftUI performance](https://developer.apple.com/videos/play/wwdc2025/306/) explains expensive view updates. [Apple: Simulator limits](https://developer.apple.com/videos/play/wwdc2019/418/) explains why hardware measurements remain separate.
