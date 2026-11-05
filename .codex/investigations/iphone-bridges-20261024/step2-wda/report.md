---
title: Step 2 — Appium versus direct WebDriverAgent
subtitle: Forty verified Settings transitions · no meaningful speed gain · lock cleanup unverified
lang: en
template: doc
theme: shadcn
---

## Decision

```callout ok Keep Appium as the default
Both backends passed twenty measured Settings transitions.
Direct WDA saved about forty milliseconds per request at the combined median.
It did not improve the median time to a verified screen.
```

This small sample does not establish production reliability. It gives no reason to replace Appium to fix minute-scale gaps.

## Paired local measurement

| Backend | Verified transitions | Median request | Request p95, nearest rank | Maximum request | Median verified screen |
|---|---:|---:|---:|---:|---:|
| Existing Appium | 20 / 20 | 0.724 s | 1.106 s | 1.112 s | 1.821 s |
| Direct WDA | 20 / 20 | 0.684 s | 0.957 s | 0.966 s | 1.871 s |

The test alternated backend order across five cycles. Each cycle opened General, scrolled down, scrolled back up and returned to Settings.
The request medians combine ten taps and ten swipes per backend. Per-action medians provide a cleaner comparison.

| Action | Appium median request | Direct WDA median request | Verified per backend |
|---|---:|---:|---:|
| Open General | 0.506 s | 0.495 s | 5 / 5 |
| Swipe upward | 0.940 s | 0.938 s | 5 / 5 |
| Swipe downward | 0.956 s | 0.934 s | 5 / 5 |
| Back to Settings | 0.499 s | 0.489 s | 5 / 5 |

Verified-screen time includes a fixed 0.65-second settle wait, screenshot retrieval and local OCR.
The measurement excludes the model's response time. The controller completed the forty transitions in about eighty seconds.

## What the setup failures revealed

Earlier preparation attempts failed before the accepted paired sample. Their evidence remains in events.jsonl and separate result files.
The first prototype confused a search-result heading with a navigation title. A later preparation scrolled in the wrong direction.
Those were controller errors, not bridge failures.

A screenshot also caught General while scroll momentum continued. The next tap missed the moving row.
The corrected controller requires two observations with the target within three points before tapping.
That change addresses a demonstrated navigation failure without changing the bridge.

Another checker falsely rejected the General page after scrolling to its top.
iOS hid the compact navigation title while showing the large General heading and About row.
The corrected check recognizes both the page content and its scroll state.

The accepted sample uses the corrected controller. Do not combine prototype failures with its twenty-per-backend acceptance score.
Do not erase those failures when assessing the broader workflow.

## Scope and cleanup

The controller held the existing per-UDID lock on hihi, running iOS 26.6.2.
Both backends reused the same ready video-mode Appium and WDA sessions. Both sent identical W3C touch payloads.
Each transition received fresh screenshot and OCR verification. The controller stopped uncertain or unexpected results without input replay.

No setting changed. No social action occurred. No session restarted.

Home restoration has screenshot evidence. A single power press completed, but the lock check timed out.
A later read still reported unlocked. The controller did not repeat the uncertain power press.
Lock restoration remains unverified. The existing sessions remain alive.

Evidence: [measured result](result.json), [per-action summary](action-summary.json), [events](events.jsonl), [cleanup observation](cleanup-observation.json).
The accepted run ID is 0b14fad2. Its numbered PNG and OCR files retain every measured transition.

## Limits and next use

This test covers Settings on one phone. It does not cover playing video, Search tabs, keyboard focus, account switching or a long soak.
The direct path still uses the same device-side WDA and XCTest. It cannot isolate an XCTest defect.
The sample is too small for a ninety-ninth percentile or a fleet reliability claim.

Keep target settlement and destination verification in any future adapter.
A local controller can execute known navigation without waiting for a model after every input.
It still needs bounded ownership, durable receipts and fresh decisions when the screen differs from the expected state.
