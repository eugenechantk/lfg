# iPhone control alternatives: WDA wrappers and other input paths

Research checked 24 October 2026. Read-only research; no phone actions, builds, installs, or service changes.

## Decision

Measure the current bridge before replacing it. Healthy coordinate-action timings cannot explain a fifteen-minute gap by themselves. Match each gap to command start, device response, tool-result delivery, and the agent's next request. Keep screenshot latency separate from accessibility-tree latency.

First controlled comparison: existing Appium/WDA against a persistent direct HTTP client to the **same WDA build**. This isolates host/session overhead. It does not replace XCTest. If AX stalls are reproduced, compare a lean XCTest runner next. Ghosthand provides a separate, non-XCTest input path, with material gesture and compatibility limits.

## A concrete known failure mechanism

Appium documents an unbounded XCTest accessibility request when the target app's main loop remains busy, including video playback. Its newer `accessibilityDeadline` setting defaults to zero, which disables protection. A positive value checks responsiveness and aborts rather than waiting indefinitely. This is a credible mechanism to investigate, **not proof that it caused these scheduled-run gaps**. Check installed driver/WDA support before changing it. [Official slowness guide](https://appium.github.io/appium-xcuitest-driver/latest/troubleshooting/wda-slowness/)

`waitForIdleTimeout`, `animationCoolOffTimeout`, and `accessibilityDeadline` address different waits. Turning off idle waiting does not bound every accessibility request. Animation cool-off defaults to two seconds. Use screenshot-based postconditions with a deadline rather than treating a returned gesture as completed navigation. [Settings](https://appium.github.io/appium-xcuitest-driver/latest/reference/settings/)

## Options

| Option | Physical iPhone and backend | Assessment |
|---|---|---|
| Persistent direct WDA HTTP / openatx `facebook-wda` | Real devices over USB; same XCTest/WDA | Best first A/B. Removes Appium hop and repeated client startup; no guaranteed reduction in device-side stalls. |
| `leeguooooo/iphone-use` | Real iPhone, Mac, USB or Wi-Fi; its own XCTest runner since v0.20 | Worth a second-stage experiment. Changes on-device implementation, still shares XCTest/testmanagerd. |
| Official Maestro | Current release explicitly supports iOS simulators, rejects physical iPhones | Reject for these phones. |
| DeviceLab `maestro-runner` | Real iPhones and simulators; WDA or newer prebuilt XCTest agent | Maintained alternative for YAML flow authoring; not an independent escape from XCTest. |
| Airtest / Poco / iOS-Tagent | Real iOS over USB; WDA-derived iOS-Tagent | Adds image matching, native element access, and convenience; not a new gesture backend. Retry behavior requires changes. |
| `tidevice` | Physical-device transport/launch tooling, not a replacement gesture engine | Reject old project: stopped maintenance and lacks iOS17 support. |
| Ghosthand | Physical iPhone + Mac; Bluetooth HID input, USB screen capture | Real independent path. Experiment only; mouse drags differ from finger swipes. |

### Direct WDA

The Python client supports coordinate tap/swipe, screenshots, explicit UDIDs and USB connections. Screenshot pixels differ from UIKit points; conversion must be explicit. Its README still advertises testing against WDA 2.16.1, so do not assume current compatibility. Prefer a tiny pinned HTTP adapter over adopting another broad framework. Appium already supports attaching to an existing WDA, so persistent reuse does not require dropping Appium. [Client documentation](https://github.com/openatx/facebook-wda), [attach to running WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/attach-to-running-wda/)

Maintenance: `facebook-wda` latest release 1.5.4, 3 September 2025; latest main commit 1 July 2026. Appium WDA's old repository was archived on 17 October 2026 **because development moved to the appium-ios monorepo**. It was not abandoned. [Client releases](https://github.com/openatx/facebook-wda/releases), [WDA move notice](https://github.com/appium/WebDriverAgent)

### Lean XCTest runner

`iphone-use` v0.22.3 was released 23 October 2026. Its runner uses a reduced accessibility snapshot and direct event synthesis. It disables quiescence waits globally, then callers verify settlement. The documented Xcode27 XCTest dependency effectively requires iOS17+, despite the host target saying iOS15. Only one XCTest runner can own a phone. Private API and orientation handling need testing on our exact phones. Author benchmarks are not independent reliability evidence. [Runner architecture and caveats](https://github.com/leeguooooo/iphone-use/blob/main/runner/README.md), [release](https://github.com/leeguooooo/iphone-use/releases/tag/v0.22.3)

### Maestro, Airtest, and device transport

Official Maestro 2.11.0, dated 1 October 2026, explicitly exits when a physical iPhone is targeted. The separate DeviceLab project supports physical devices. Its current README advertises both WDA and a newer prebuilt XCTest agent, so pin the selected driver when benchmarking. `maestro-runner` latest release was v1.1.29 on 15 October; main changed on 22 October. [Official Maestro release](https://maestro.dev/blog/maestro-cli-2-11-0), [DeviceLab source](https://github.com/devicelab-dev/maestro-runner)

Airtest iOS imports `wda` and uses WDA touch methods. Its class-wide retry wrapper reacquires a session and reruns the original method after broad WDA errors. That risks duplicate likes or other mutations when the action succeeded but acknowledgement failed. Do not adopt this default. Airtest latest release was v1.4.3 on 4 December 2025; iOS-Tagent main last changed 3 December 2025. [Airtest iOS implementation](https://github.com/AirtestProject/Airtest/blob/master/airtest/core/ios/ios.py), [iOS-Tagent](https://github.com/AirtestProject/iOS-Tagent)

The original `tidevice` explicitly stopped maintenance and points users to go-ios or pymobiledevice3. These can improve device discovery, USB transport, screenshots, or runner lifecycle. They do not alone supply an independent general-purpose tap/swipe backend. [Maintainer notice](https://github.com/alibaba/tidevice)

### Independent HID path

Ghosthand uses Bluetooth Classic HID through AssistiveTouch, plus USB capture. It avoids XCTest idle waits and runner signing. Its swipes are mouse drags without momentum; wheel scrolling may be required. There is no multitouch or AX tree. The docs report two phones tested, versus about seven theoretical connections. Tested examples are XR/iOS18.7 and 6s/iOS15.8 through earlier BLE; newer fleet compatibility remains unverified. Its bounded text verification sends input once and never replays on timeout. [Architecture, limitations and tests](https://ghosthand.dev/)

Npm metadata reports v0.11.0 published 23 October 2026. Its declared public GitHub repository returned 404 during research, so source maintenance and implementation could not be audited. Do not infer detection resistance from HID input. [Package metadata](https://registry.npmjs.org/ghosthand)

## Proposed acceptance test

This is a proposed test, not performed research evidence.

1. Reserve one phone. Record its UDID, OS, target app version, bridge version, and account. Do not compete with a running scheduled session.
2. Use a fixed sequence of non-publishing navigation: app launch, Search tab, search entry, result opening, return, Home tab, feed swipe. Separate static, animation, and playing-video conditions.
3. Collect at least 100 trials per operation and three 30-minute soak runs per candidate. Repeat across two phone models before adopting fleet-wide.
4. Log one correlation ID across agent request, host queue, HTTP send, device response, screenshot, verification, tool return, and next agent action. Use monotonic durations and wall-clock timestamps.
5. Compare p50/p95/p99, maximum wait, verified destination rate, stale screenshot rate, transport loss, session restart count, wrong-device count, and unknown execution count.
6. Proposed gates: at least 99% verified destinations; zero duplicate or wrong-device actions; no unexplained 30-second silence. Require a material p95 improvement without worse navigation accuracy.

Use one mutation in flight per phone and explicit per-stage deadlines. A client timeout does not cancel an on-device action. Mark it `executed_unverified`; inspect read-only state and never automatically replay. A recovery must preserve the run, account, lease, and fixed session end time. Do not count screen-open time as verified playback.

Version dates above came from repository release/commit API metadata on 24 October 2026. No candidate has been benchmarked locally in this research.
