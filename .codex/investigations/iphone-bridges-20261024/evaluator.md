# Research evaluation

Verdict: **STOP the research phase. Proceed to measured experiments, with the limitations below.**

Reviewed `trace-findings.md`, `idb-bridges.md`, and `synthesis.md` on 24 October 2026. Also checked current primary source for pymobiledevice3 HID, ipb requirements, and rPlayHub's reported iOS26 device test. No phone, app, service, or configuration changes.

## Evidence supports the central recommendation

The user's suspicion is reasonable but is not supported as the explanation for the strongest retained gaps. A recorded outer call spans 900.081 seconds although its nested work completed after about 1.3 seconds. Another interval has no outstanding agent tool. These establish a waiting boundary outside that completed phone command. They do not identify the faulty response component or explain every latest session.

The synthesis correctly distinguishes low HTTP latency from correct navigation. Retained completed-request metrics exclude some possible unfinished requests. Successful status GETs establish current endpoint health, not reliable TikTok/Reels swipes. Neither measurement warrants declaring the bridge universally reliable.

The configuration's 900-second timeout closely matches one observed interval. `supports_websockets: true` is only capability/configuration evidence. It does not prove that WebSocket carried that request, that SSE timed out, or that a specific timeout handler caused the delay. The synthesis preserves this distinction.

Installed host package source contains `accessibilityDeadline`; missing GET fields do not identify the deployed phone binary. Do not state that the live runner supports, enables, or disables that setting until its build is established.

## Final synthesis check

Re-read the updated synthesis after its CoreDevice integration. It now includes the genuine independent injector and the unsupported ipb host matrix. These distinctions are necessary and supported:

1. **pymobiledevice3 universal HID is a genuine independent input candidate.** It bypasses WDA/XCTest and provides touchscreen contact/release reports. Evaluate a persistent session after transport attribution; service, DDI and authentication availability on the exact fleet remain unverified. Its CLI's `drag` is the touch-contact feed gesture; `swipe` is pointer motion. [Implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/core_device/hid_service.py)
2. **ipb is outside the current supported host matrix.** Its published matrix requires macOS27, Xcode27/CoreDevice636+, and iOS27+. The current macOS26.6.2 host does not satisfy that matrix. Its physical-device release gate also remains open. Do not upgrade the working host merely for this experiment. [Requirements and release limits](https://github.com/ipbtools/ipb)
3. **That is not a universal iOS26 HID prohibition.** rPlayHub reports USB touch/swipe on an iPhone12Pro running iOS26.5.2. This is maintainer-reported, limited hardware evidence from an experiment harness; it does not verify current fleet compatibility. [Reported test](https://github.com/rPlayAI/rPlayHub/blob/main/host/README.md)

The experiment order is sound: trace agent/result delivery; compare persistent direct WDA using the same on-device build; then compare persistent CoreDevice HID as the independent injector if prerequisites can be met. Lean XCTest and Bluetooth HID remain fallback experiments with their stated limits.

One small factual correction was sent to the parent: the synthesis's phrase "current host and phones run 26.6.2" should name the two inspected phones. The bridge report records calmer as iOS27.0.1. That phone still does not satisfy ipb's supported matrix while the host runs macOS26.6.2. This does not change the recommendation.

## Why no further broad research is needed

The remaining questions require local, bounded measurement: which component loses continuation, whether a compatible HID service exists, the live WDA build, and whether any candidate improves verified navigation. More bridge lists cannot answer them. Direct WDA is useful for isolating Appium overhead, not a presumed reliability upgrade. Its value must justify another maintained adapter.

The proposed 100-trial operation tests and soak runs are a pilot, not proof of production failure rates. Preserve one owner and one mutation in flight per phone. Timeout is not cancellation; inspect uncertain state rather than replaying input. Keep diagnostic adoption criteria separate from the user's social-task completion policy.
