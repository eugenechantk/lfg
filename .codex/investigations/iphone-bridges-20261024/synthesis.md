# Faster and more reliable iPhone control

Research synthesis, 24 October 2026. Alternate bridges have not been installed or benchmarked.

## Recommendation

Keep the current bridge while investigating Codex's response delivery. Then compare Appium with a persistent direct WDA client on one reserved phone. This is the smallest experiment that can separate host overhead from device execution. Use a tiny LFG-owned adapter that preserves the existing ownership, receipt, deadline, and uncertain-action rules.

For a genuinely different injector, test **pymobiledevice3 CoreDevice HID** next, after checking that the required developer service is available on the exact phone and DDI. It bypasses WDA and XCTest, unlike most alternative wrappers. Compatibility with our iOS 26.6.2 phones remains unverified.

The recent fifteen-minute gaps are not evidence of fifteen-minute swipes. We have direct production evidence of local work finishing in 1.3 seconds, followed by an outer result nearly fifteen minutes later. We also have gaps with no phone command outstanding.

Use a second device runner only if an isolated benchmark demonstrates that XCTest accessibility or event synthesis causes a different failure. Keep one input in flight and verify the destination after every transition.

## The control path and the proven waiting boundary

```text
Agent -> tool host -> phone CLI -> Appium
                                  |
                                 WDA
                                  |
                               XCTest
                                  |
                                 App
```

The decisive production trace finishes the nested local command at 07:42:16.803 UTC. Its outer tool result appears at 07:57:15.608 UTC. This places **898.805 seconds after local completion**. Another approximately fifteen-minute interval has **no outstanding tool**. Changing the path below the phone CLI cannot directly fix either interval.

Current Codex configuration selects `openai-long-timeout`, with a **900,000 ms stream idle timeout**. The production outer call lasted **900.081 seconds**. A previous 60-second candidate produced a **61.066-second** outer call. These matches make timeout and response handling a strong lead. They do not establish which protocol, client component, provider, or tool host caused the failure.

The prior candidate was withdrawn because another session still lost substantial continuation time. There is no verified active transport fix. Raising phone timeouts or rewriting swipe commands would miss the observed boundary.

Sources: `trace-findings.md`, including original rollout line references; `.codex/feature/iphone-execution-gaps/independent-audit.md:28–79`.

## What the current bridge actually measured

The saved metrics include **2,077 W3C action requests** across hihi and dumb dumb. Median action latency is approximately **0.5 seconds**. Recorded action p95 is approximately **one second**, with maximum **2.2762 seconds**. There are no recorded request errors in these two retained files.

These are retained completed-request measurements, rather than every historical request or proof that every tap reached its intended target. The exact 22 October booking window independently shows action maxima below 1.5 seconds.

The fresh read-only probe completed **40 GET requests with no errors**. They queried Appium status, WDA status, and existing session settings. They sent no gestures, screenshots, session creation requests, or settings changes. This demonstrates current health endpoints respond; it does not benchmark swipes or video-app navigation.

Sources: `existing-driver-metrics.json`, `read-only-probe.json`, and `trace-findings.md`.

## Ranked experiments

| Priority | Candidate | What it could improve | What it cannot establish |
|---|---|---|---|
| 1 | Correlated transport and tool timing | Locate the current fifteen-minute delay; test bounded recovery | A healthy phone status probe alone cannot verify recovery |
| 2 | Persistent direct WDA versus current Appium | Isolate Appium and client startup overhead; simplify a known path | Both still use WDA/XCTest and can share device-side stalls |
| 3 | Persistent pymobiledevice3 CoreDevice HID | Test touch input outside WDA/XCTest | Current-phone service availability, DDI compatibility, and gesture correctness require verification |
| 4 | Lean XCTest runner, such as iphone-use | Compare a different on-device implementation and event synthesis | It still shares XCTest and can conflict with the existing runner |
| 5 | Bluetooth HID input, such as Ghosthand | Test a second independent input route | Mouse-style dragging, no multitouch, fleet compatibility, and source access remain limitations |

Direct WDA is an experiment, not an assumed upgrade. Current sessions already persist. It must show a material gain in verified navigation, rather than only faster health checks.

Official Maestro currently rejects physical iPhones. DeviceLab's separate runner supports them, but its WDA/XCTest backends need explicit selection. Airtest/Poco mainly add targeting and framework features; their WDA roots do not offer an independent escape. Airtest's broad retry behavior also needs review before outward-facing actions.

Facebook idb can manage physical devices and run XCTest, but its inspected coordinate HID executor resolves a simulator. It is not a demonstrated direct physical-phone tap/swipe replacement. go-ios and DeviceKit change orchestration or runner implementation while retaining XCTest.

**ipb is a real iOS ADB-style bridge**, with direct CoreDevice HID. Its supported matrix requires macOS 27 and iOS 27; it explicitly dropped iOS 26. The current host runs macOS 26.6.2. Hi Hi and dumb dumb run iOS 26.6.2; calmer runs iOS 27.0.1. Its physical-device release gate is also open. Do not upgrade the fleet or replace the current bridge to try it now. Keep it as a future reserved-device candidate.

ADB means Android Debug Bridge and does not control stock iOS. “ADP Bridge” did not resolve to a confirmed project in the research; it may refer to ADB or ipb, but that interpretation is unconfirmed.

The pymobiledevice3 HID path is the more relevant independent experiment for this fleet. Its `drag` command supplies finger contact; the command named `swipe` supplies pointer motion without contact. It requires an active media stream, and known authentication timing can otherwise produce protocol success with dropped touches. Use a persistent, exclusively owned session and verify the resulting screen. Do not assume that bypassing XCTest guarantees reliability.

Sources: `wda-alternatives.md`, with primary documentation and current release references. Useful primary sources: [Appium WDA slowness](https://appium.github.io/appium-xcuitest-driver/latest/troubleshooting/wda-slowness/), [attach to running WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/attach-to-running-wda/), [iphone-use runner](https://github.com/leeguooooo/iphone-use/blob/main/runner/README.md).

Independent-injector and idb sources: `idb-bridges.md`; [pymobiledevice3 HID implementation](https://github.com/doronz88/pymobiledevice3/blob/4b4e3c04b418d57f205924aae5e314979cc9ccb5/pymobiledevice3/remote/core_device/hid_service.py), [dropped-touch report and fix](https://github.com/doronz88/pymobiledevice3/issues/2036), [idb HID executor](https://github.com/facebook/idb/blob/8ac770ad571152e877f730ed73f4430eda4a2f41/CompanionLib/IDBCommandExecutor.swift#L481-L485), [ipb requirements](https://github.com/ipbtools/ipb#requirements), [ipb verification](https://github.com/ipbtools/ipb/blob/main/docs/verification.md).

## WDA version and live capability distinction

The installed host package is **appium-xcuitest-driver 12.8.0**, containing **appium-webdriveragent 16.8.0**. This review read their package metadata and confirmed local source contains `accessibilityDeadline`.

The fresh existing-session GET responses do **not** expose `accessibilityDeadline`; the probe records a missing field as `null`. Both phones report SpringBoard targeting and `waitForIdleTimeout: 0`.

WDA status identifies both live runners as **16.8.0**, compiled **30 September** and **1 October**, using SDK **26.2** on iOS **26.6.2**. The matching nominal package version does not establish their exact source revision or explain the missing settings field. Do not say the deadline is configured to zero, unsupported, or safely available on the live runners from these observations alone.

Separately test this safeguard on a reserved phone after reconciling the deployed build with its source. The deadline can bound a known busy-app accessibility hang. It cannot repair an agent continuation gap or a result delayed after local work has finished.

Local source pointers: `~/.appium/node_modules/appium-xcuitest-driver/package.json`; its nested `appium-webdriveragent/package.json`; WDA `WebDriverAgentLib/Utilities/FBSettingsHandler.m:146,257` and `FBConfiguration.m:354`. Probe evidence: `read-only-probe.json` and `wda-build-readings.json`.

## Test design before adoption

Measure three layers independently:

1. **Agent and result delivery.** A tiny local command plus an image, without phone input. Record dispatch, nested completion, outer result, and next action. Repeat sequentially and concurrently.
2. **Phone request and destination.** On one reserved device, compare the current bridge with a pinned candidate using identical navigation. Include static pages, animations, and playing video. Record request duration separately from the screenshot that verifies the intended screen.
3. **Representative task.** After both controls pass, run a bounded task with the same ownership and deadline rules. Attribute time to model continuation, result delivery, local HTTP, app loading, verification, and intentional waits.

Record correlated operation IDs, monotonic durations, bridge versions, phone OS, screenshots, unknown outcomes, recovery actions, wrong targets, and duplicate inputs. A client timeout is not cancellation. Preserve uncertain outcomes and inspect state before any retry.

Proposed adoption gates: zero duplicate inputs or wrong-device actions; at least 99% verified destinations; no unexplained silence over 30 seconds; materially better p95 without worse accuracy. Use at least 100 trials per operation and soak runs. These are experiment criteria, not revised social-task completion rules.

## Questions that remain open

- Which response or tool-host component waits for the current 900-second boundary?
- Do the live WDA binaries support an accessibility deadline, and can their build identity be established without replacement?
- Does direct WDA improve end-to-end navigation enough to justify maintaining another adapter?
- Can an alternate runner pass the same video navigation tests without introducing different uncertainty or ownership failures?
- Which recent Toni and Jess gaps share the proven boundary? The two original production traces do not settle every run.
