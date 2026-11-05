---
title: iPhone reliability — results and fixes
subtitle: Three sequential diagnostics · 24 October 2026 · no production transport or bridge replacement
lang: en
template: doc
theme: shadcn
---

## Recommendation

```callout warn Keep the bridge; fix the waiting and targeting boundaries
The measured Appium and direct WDA paths both completed twenty verified Settings transitions.
Direct WDA saved milliseconds, while the historical failures lost minutes outside gesture execution.
Target settlement exposed a real navigation issue. CoreDevice HID is unavailable in the current phone configuration.
```

No result establishes a repair for the execution-gap defect.
The three diagnostics now separate what failed, what passed and what remains blocked.

## The three results

| Step | Result | Decision |
|---|---|---|
| Agent delivery and continuation | A history fork reproduced a WebSocket broken pipe and HTTPS fallback before any phone command. HTTP-only also failed acceptance. | Keep the transport defect open. No global timeout or transport switch. |
| Appium versus direct WDA | Each path verified twenty Settings transitions on the same iPhone and WDA session. Direct WDA did not improve median verified-screen time. | Keep Appium. Retain stable-target and screen-verification checks. |
| Independent CoreDevice HID | The exact phone advertised seventy-three remote services without HID or display services. A developer image is already mounted. | No HID gesture benchmark is possible in the current configuration. Use a separate compatible test environment. |

[Step 1 evidence](step1-delivery/index.html), [Step 2 evidence](step2-wda/index.html), [Step 3 evidence](step3-hid/index.html).

## Why the latest scheduled runs lost time

```flow LR
Agent -> Tool: request
Tool -> Appium: local call
Appium -> WDA: USB
WDA -> iPhone: touch
Tool --> Agent: result delivery
```

The original traces show nine outer-result delays above thirty seconds across the selected phone windows.
Five exceeded five minutes after nested local spans below two seconds.
Other long gaps contain no recorded outstanding tool. Replacing WDA cannot resume an agent during those gaps.

| Latest run | Longest wait after local completion | Longest gap without a pending tool |
|---|---:|---:|
| Toni AM | None found | 327.221 s |
| Marisol AM | 532.298 s | 949.103 s |
| Jess AM | 905.252 s | 91.218 s |
| Toni PM | 898.927 s | 914.829 s |
| Roxie fitness TikTok | 898.805 s | 903.070 s |

The 900-second provider timeout resembles several gaps. It does not prove their cause.
The approved diagnostic database read could not recover the old events: retention starts the following day.
The selected power-log window contains no host sleep or wake transition.

Five fresh diagnostic launches passed twenty local command rounds.
Three forks using Jess's existing history failed their bounded acceptance windows.
The forks differ from the original early failure in history size, so they do not establish the exact historical trigger.

## What the phone test establishes

The local controller alternated backend order across five cycles on hihi, running iOS 26.6.2.
Both paths reused the existing video-mode sessions and sent identical W3C touch gestures.
Each cycle opened General, scrolled in both directions and returned to Settings.

| Measurement | Appium | Direct WDA |
|---|---:|---:|
| Verified transitions | 20 / 20 | 20 / 20 |
| Median input request | 0.724 s | 0.684 s |
| Request p95, nearest rank | 1.106 s | 0.957 s |
| Median verified screen | 1.821 s | 1.871 s |

The screen measurement includes a fixed settle wait, screenshot retrieval and local OCR.
It excludes model response delays. The full forty-transition sample took about eighty seconds.
This sample covers Settings. It does not establish reliability in TikTok, Reels or a long scheduled session.

## The control failure worth fixing now

Preparation caught a moving General row. A screenshot arrived before scroll momentum stopped, and the following tap missed it.
A faster bridge would still have used the stale position.
The corrected diagnostic controller requires two observations with the target position within three points before tapping.
It then verifies the destination before another action.

The prototype also confused a search result with a page title and initially chose the wrong scroll direction.
Those failures came from controller logic. They remain in the evidence and are separate from the accepted paired sample.
A final checker needed to recognize both compact and large General headings.

The durable rule is: settle, identify from the latest observation, act once, then verify.
Use stable accessibility identifiers in suitable native screens. Keep screenshot-based targeting for playing-video screens that block accessibility.

## Which bridge to use

Appium remains the practical default for the current fleet. Direct WDA still uses the same XCTest injector.
The measured hop reduction is too small to justify a replacement for this problem.

pymobiledevice3 provides a genuinely separate CoreDevice touch path.
Its current service is absent on the tested phone configuration. Its media stream and compatible developer image are prerequisites.
The probe changed neither pairing nor the mounted image and sent no input.
[CoreDevice HID implementation](https://github.com/doronz88/pymobiledevice3/blob/4b4e3c04b418d57f205924aae5e314979cc9ccb5/pymobiledevice3/remote/core_device/hid_service.py).

The inspected idb coordinate path resolves a simulator. It does not show a physical-phone replacement.
ipb requires a newer supported host and device matrix than this setup.
[IDB implementation](https://github.com/facebook/idb/blob/8ac770ad571152e877f730ed73f4430eda4a2f41/CompanionLib/IDBCommandExecutor.swift#L481-L485), [ipb requirements](https://github.com/ipbtools/ipb#requirements).

[Full bridge research](research-index.html), [source review](idb-bridges.md), [WDA alternatives](wda-alternatives.md).

## Fix order and boundaries

1. Keep scoped transport telemetry and reproduce the history failure before selecting a transport repair.
2. Use stable target observations and explicit destination checks in the existing phone workflow.
3. Move short, known navigation sequences into a bounded local controller with durable receipts.
4. Validate playing-video navigation and a bounded soak before another representative scheduled run.
5. Evaluate independent HID on a separate compatible phone and developer-image setup.

A local controller reduces model round trips for known steps. It cannot replace decisions when content or navigation differs.
It must retain one owner, one mutation in flight, deadlines and uncertain-result handling.
Do not repeat input after a timeout. Inspect the actual screen first.

The user approved all operations. The investigation changed no saved schedule, original session or production transport setting.
No social action occurred. No Appium or WDA session restarted.

Home restoration has screenshot evidence. One power press completed, but lock confirmation failed; no replay followed.
Lock restoration remains unverified. Both existing control sessions remain ready.

[Final evidence checks](sequence-verification.json) confirm the forty screenshots, OCR postconditions, session identities and report links.

The research, bounded comparison and capability check are complete. The transport repair and independent HID gesture trial remain open.
