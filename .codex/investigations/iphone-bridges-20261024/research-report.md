---
title: Why iPhone sessions pause, and which bridges to test
subtitle: Research and read-only measurements · 24 October 2026 · no phone input or production changes
lang: en
template: doc
theme: shadcn
---

## Recommendation

```callout warn Diagnose the delay before replacing the bridge
The strongest traces place the fifteen-minute gaps outside phone gesture execution.
Keep the current bridge as a baseline. Test a persistent direct WDA client, then CoreDevice HID as a genuinely different injector.
```

The current method can still mis-target controls or hang on accessibility queries. Those need separate tests.
Fast request responses do not prove correct navigation.
No alternate bridge has passed a local gesture benchmark in this research.

## What the latest evidence proves

The current path has several distinct waiting boundaries:

```flow LR
Agent -> Local tool: request
Local tool -> Appium: HTTP
Appium -> WDA: USB forward
WDA -> XCTest: synthesize input
XCTest -> iPhone: UI action
```

An input can finish on the phone while its result waits elsewhere.

| Evidence | Measured result | What it establishes |
|---|---|---|
| Original Roxie fitness trace | Local work finished in 1.3 seconds; outer result arrived after 900.081 seconds. | This interval was not a fifteen-minute swipe. The helper refused the attempted tap before dispatch. |
| Original Marisol trace | Local failure finished in about 0.4 seconds; outer failure arrived after 532.650 seconds. | Delay also occurred while returning a refused command. |
| Two concurrent sessions | Both resumed events at exactly 07:16:04.063 UTC after roughly fifteen-minute gaps. | A shared delivery or continuation problem is plausible. Concurrency is not proven causal. |
| Retained gesture metrics | 2,077 completed gesture requests across two phones; maximum 2.28 seconds. | Recorded healthy requests were fast. Missing requests and incorrect destinations remain possible. |
| Fresh health probes | Forty GET requests succeeded, with no phone input. | Existing health endpoints responded quickly. This is not a gesture or navigation benchmark. |

Some original gaps have no outstanding tool at all. A phone bridge cannot resume an agent during that silence.
Exact timestamp and source-line references appear in [trace-findings.md](trace-findings.md).

### The 900-second clue

The selected provider configuration contains stream_idle_timeout_ms=900000. That is exactly fifteen minutes.
Its match with 900.081 seconds is a strong diagnostic clue, not proof of the faulty component.
The provider also advertises WebSocket support.

The current config does not prove which protocol those historical requests used.
The official reference defines this field as an SSE idle timeout. [OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)

A prior sixty-second experiment reproduced delayed delivery, but failed another live probe. That candidate was withdrawn.
We still have gaps because no repair has passed the complete runtime test.
Reducing a timeout may shorten a stall without fixing its trigger or safely restoring continuation.

## How fast the current bridge is

The retained journal records completed HTTP requests from 22 October. They cover multiple operations on each device.
The request duration includes Appium and its device response. It excludes later delivery to the agent.

| Phone | Gesture requests | Gesture median | Gesture 95th percentile | Gesture maximum | Screenshot maximum |
|---|---:|---:|---:|---:|---:|
| Hi Hi | 1,476 | 0.514 s | 0.955 s | 2.276 s | 1.618 s |
| dumb dumb | 601 | 0.492 s | 1.020 s | 1.636 s | 0.722 s |

The journals contain no recorded errors in these requests. They cover a limited retention window.
They do not measure whether the selected tab, post or field was correct.
A narrower window during the problematic bookings also contains no minute-scale completed phone request.

Fresh probes measured median WDA status responses at about 3–4 milliseconds.
Appium settings reads took about one millisecond. We sent no screenshots, gestures, app launches or settings changes.

Both inspected phones connect over USB and run iOS 26.6.2. The Mac runs macOS 26.6.2.
Calmer separately runs iOS 27.0.1; its version does not establish compatibility for the other phones.

Evidence: [existing-driver-metrics.json](existing-driver-metrics.json), [read-only-probe.json](read-only-probe.json), [WDA build readings](wda-build-readings.json).

## Which bridges are realistic alternatives?

A bridge carries commands. An injector generates input on the phone. Replacing the bridge may retain the same injector.

| Option | Underlying input | Fit for these physical phones | Decision |
|---|---|---|---|
| Current Appium and WDA | XCTest | Already running with video mode and USB. | Keep as the baseline. |
| Persistent direct WDA | Same XCTest and WDA | Removes the Appium hop; retains device-side XCTest limits. | First control comparison. |
| pymobiledevice3 universal HID | CoreDevice touchscreen service | Genuine WDA/XCTest bypass. Exact service and developer-image support remain unverified on iOS 26.6.2. | Preferred independent-input experiment. |
| ipb | CoreDevice HID and private services | Supported matrix requires macOS 27, Xcode 27 and iOS 27+. Current host misses it. | Defer; do not upgrade the fleet for this experiment. |
| Lean iphone-use runner | Its own XCTest runner | Changes the on-device server, but still depends on XCTest and private APIs. | Consider if device-side stalls recur. |
| Facebook idb | Simulator HID for the inspected coordinate path | Physical-device management does not establish real-phone tap/swipe support. | Reject as a demonstrated gesture replacement. |
| go-ios and DeviceKit | WDA or another XCTest runner | Useful orchestration; not an independent escape from XCTest. | Lower priority than the small control comparison. |
| Ghosthand | Bluetooth mouse and keyboard; USB capture | Independent path, but no multitouch or accessibility tree. Mouse drags differ from finger swipes. | Experimental fallback. |

The direct WDA client documentation supports physical devices and coordinate gestures. It provides no fleet-specific speed guarantee.
Appium itself can also reuse an existing WDA. Persistence alone does not require replacing Appium.
[Direct client](https://github.com/openatx/facebook-wda), [attach to running WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/attach-to-running-wda/)

Current idb code resolves a simulator before connecting its coordinate HID channel. Do not copy simulator tap examples into a physical-phone plan.
[idb implementation](https://github.com/facebook/idb/blob/8ac770ad571152e877f730ed73f4430eda4a2f41/CompanionLib/IDBCommandExecutor.swift#L481-L485)

If “ADP Bridge” meant ADB, ADB controls Android. This search did not identify a standard iPhone tool with that exact name.
[Official ADB documentation](https://developer.android.com/tools/adb)

Official Maestro currently targets iOS simulators. The separate DeviceLab runner supports physical phones through XCTest-based agents.
Airtest's iOS retry wrapper can repeat a mutation after an uncertain failure. That behavior needs removal before adoption.
[Maestro release](https://maestro.dev/blog/maestro-cli-2-11-0), [DeviceLab runner](https://github.com/devicelab-dev/maestro-runner), [Airtest retry source](https://github.com/AirtestProject/Airtest/blob/master/airtest/core/ios/ios.py)

## The genuinely different HID path

pymobiledevice3 now implements com.apple.coredevice.hid.universalhidservice.
It sends touch contact reports without a WDA server or XCTest runner.
Its touch session also starts a media stream, which the device uses to authorize input.
A persistent session avoids repeated tunnel and stream setup. [HID implementation](https://github.com/doronz88/pymobiledevice3/blob/4b4e3c04b418d57f205924aae5e314979cc9ccb5/pymobiledevice3/remote/core_device/hid_service.py)

There is an important command distinction: its drag command supplies finger contact for a feed swipe.
Its command named swipe sends pointer motion without touch contact.
Text input also has encoding limits. We must verify actual navigation, not just a successful command response.
[CLI implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/developer/core_device.py)

A recent issue describes successful command returns with silently dropped touches on an iPhone 11.
Increasing the media authentication wait fixed that case. Release 11.33.1 raised the default wait to 0.5 seconds.
This shows why a newer bridge still needs screen-based verification. [Reproduction](https://github.com/doronz88/pymobiledevice3/issues/2036), [fix release](https://github.com/doronz88/pymobiledevice3/releases/tag/v11.33.1)

The rPlayHub maintainer reports this HID route working on iOS 26.5.2. Its code remains an experiment harness.
That makes iOS 26 testing plausible, but does not establish compatibility with our iOS 26.6.2 phones.
[Reported device evidence](https://github.com/rPlayAI/rPlayHub/blob/main/host/README.md)

ipb is another real CoreDevice path. Its supported host and device matrix is newer than this setup.
Its own full physical-device release gate remains open. Calmer's iOS 27 version alone does not satisfy the host requirements.
[ipb requirements](https://github.com/ipbtools/ipb#requirements), [verification scope](https://github.com/ipbtools/ipb/blob/main/docs/verification.md)

Ghosthand avoids XCTest through Bluetooth HID. Its documented tested devices differ from this fleet.
Its public source link returned 404 during research, which limits the source audit.
[Ghosthand architecture and limits](https://ghosthand.dev/)

## Improve the current path without hiding its failures

Current video mode already targets SpringBoard and uses coordinate gestures, avoiding the playing app's accessibility tree.
It disables idle and animation waits. That mitigation does not establish a deadline for every XCTest wait.

Appium documents accessibility requests hanging when video keeps an app busy.
The newer accessibilityDeadline setting can bound a responsiveness check. A value of zero disables that protection.
It can also cause legitimate transitions to fail, so blanket activation is unsuitable.
[Appium settings](https://appium.github.io/appium-xcuitest-driver/latest/reference/settings/), [slowness guide](https://appium.github.io/appium-xcuitest-driver/latest/troubleshooting/wda-slowness/)

Local packages report XCUITest driver 12.8.0 and WDA 16.8.0. The running phones also report WDA 16.8.0.
The local source contains accessibilityDeadline, but live settings responses omit it.
Its effective support and configuration remain unknown. A package version match does not prove identical on-device code.
Validate the setting in isolation before relying on it.

The current launch configuration allows thirty minutes for a WDA connection.
Ordinary client requests usually have thirty-second budgets. A client timeout does not cancel an accepted device action.
Keep launch budgets separate from gesture budgets. Never fix a timeout by blindly repeating the input.

Use one small LFG-owned command adapter if the comparison justifies it.
Keep the existing CLI usable by independently started terminal agents.
All backends should share the same phone lease, command identity, deadline, receipt and verification rules.
Do not create a new framework merely to remove an already-fast HTTP hop.

## Proposed controlled comparison

This plan is ready for a reserved test. We did not execute these gestures during research.

1. Reproduce agent delays with tiny local commands and image reads, without phone input.
2. Correlate local completion, outer result delivery and the next agent action under one ID.
3. Compare the current path with persistent direct WDA on the same phone and WDA build.
4. Check CoreDevice HID service and developer-image availability before attempting its gesture comparison.
5. Test Search-tab changes, search focus, keyboard dismissal, back navigation, Home and feed swipes.
6. Repeat static-screen and playing-video cases. Score the actual destination from fresh screenshots.
7. Run a bounded soak after the short trials pass. Then test one newly booked representative session.

Record median, p95, p99 and maximum latency. Separate cold startup, warm input, screenshots, visible settlement and agent continuation.
Also record wrong targets, missed input, stale frames, unknown execution and session restarts.
A proposed adoption gate is at least 99% verified destinations, with zero duplicate or wrong-device actions.
Treat unexplained silence above thirty seconds as a diagnostic failure, not a new social completion rule.

Preserve one mutation in flight per phone. Inspect uncertain results before another input.
Never replay a whole batch after a partial failure. Never extend ownership or a phone deadline to finish a test.
Use fresh targets after layout changes. Keep cleanup within the reservation.

Official Codex telemetry distinguishes API, SSE, WebSocket and tool events. Those are useful diagnostic boundaries.
No telemetry export or configuration change occurred here.
[OpenAI diagnostics documentation](https://learn.chatgpt.com/docs/config-file/config-advanced)

## Evidence and remaining uncertainty

Verified here: primary-source capability review, original trace timestamps, retained driver metrics, forty read-only probes and current device/build discovery.
Still unknown: the faulty transport component, exact HID compatibility, comparative navigation accuracy and long-run stability of alternate bridges.
The independent evaluator recommends ending document research and moving to bounded measurement.

No phone inputs, session creation, installs, restarts, schedule edits, database queries or product changes occurred.
Reading the existing diagnostic database remains subject to the standing approval rule. This research did not need that read.

Detailed research:

- [Causal attribution and exact source lines](trace-findings.md)
- [IDB, CoreDevice HID, ipb and device transports](idb-bridges.md)
- [WDA clients, lean runners and Bluetooth HID](wda-alternatives.md)
- [Research synthesis](synthesis.md)
- [Independent evidence evaluation](evaluator.md)
