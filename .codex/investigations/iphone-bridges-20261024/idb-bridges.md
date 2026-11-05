# Physical iPhone bridges: primary-source findings

Research checked 24 October 2026. No software was installed. No device commands were run.

## Recommendation

Keep the present XCTest/WDA route as the baseline. Evaluate **pymobiledevice3 CoreDevice HID** as a genuinely different injector on one reserved phone. Its direct touch path bypasses WDA and XCTest. First check that the correct developer disk image exposes the service. Do not presume iOS 26.6.2 support from the package's general iOS support.

**ipb is another genuine alternative, but its supported matrix is iOS 27+, macOS 27 and Xcode 27.** It explicitly dropped iOS 26 support. Its own verification document leaves the full supported physical-device release gate open. This is a candidate for a controlled experiment, not a proven replacement for scheduled TikTok/Reels work. [ipb requirements](https://github.com/ipbtools/ipb#requirements), [verification](https://github.com/ipbtools/ipb/blob/main/docs/verification.md)

The parent investigation reports the current host is macOS 26.6.2, HiHi and dumb dumb run iOS 26.6.2, and calmer runs iOS 27.0.1. None is a fully supported ipb host/device combination today. The project records some macOS 26 development tests, but expressly excludes those from its supported release matrix. Do not upgrade the host or phones merely to try a bridge before measuring the existing gaps.

Changing only a USB bridge will not fix delays that occur before a command is submitted or after its result returns. Measure those intervals separately from gesture dispatch.

## The important distinction

```text
Planner → wrapper → bridge → injector → app
```

The bridge carries messages. The injector produces input. A faster bridge can still use the same XCTest injector.

| Method | Real stock iPhone input | Actual mechanism | Assessment |
| --- | --- | --- | --- |
| Apple XCTest / WDA | Yes | Signed test runner and XCTest touch synthesis | Established baseline; not eliminated by switching its host launcher |
| Facebook idb coordinate `ui` | Not through inspected HID path | Companion resolves `target.simulator()` | No demonstrated direct physical-device replacement |
| go-ios `ui` with WDA | Yes | HTTP to WDA; testmanagerd launches runner | Different orchestration, same WDA/XCTest injector |
| go-ios `ui` with DeviceKit | Yes | HTTP JSON-RPC to an XCUITest runner | Different server, still XCTest |
| pymobiledevice3 universal HID | Yes on reported compatible devices | CoreDevice RemoteXPC to `dtuhidd`; touchscreen reports | Genuine WDA/XCTest bypass; service/DDI and authentication requirements apply |
| ipb | Yes on scoped reported devices | CoreDevice private HID services | Genuine bypass; iOS 27 supported target, beta/private ABI dependency |
| libimobiledevice / usbmuxd | Transport and device services | Multiplex sockets and named services | Not a standalone tap/swipe injector |
| Android ADB | Android only | Android daemon and shell | Not an iPhone bridge |

## Facebook idb: the physical-device caveat

`idb` supports physical-device management and XCTest execution. That does not mean all `idb ui` commands support real phones. Its current UI documentation says accessibility operations support simulators only and that a subset of HID works on devices. However, the inspected coordinate HID implementation resolves a simulator:

```swift
private func connectToHID() async throws -> SimulatorHID {
  let simulator = try target.simulator()
  ...
  return try await simulator.hid.connect()
}
```

Both streamed HID and individual HID requests use that method. Therefore, do not recommend `idb ui tap 201 286` or `idb ui swipe 100 500 100 100` as a physical-phone solution. Simulator examples cannot prove the required capability. The broad documentation and implementation need reconciliation before claiming any physical HID subset. [current UI guide](https://github.com/facebook/idb/blob/main/website/docs/idb/ui.mdx), [executor source](https://github.com/facebook/idb/blob/8ac770ad571152e877f730ed73f4430eda4a2f41/CompanionLib/IDBCommandExecutor.swift#L481-L485)

This is **not** evidence that idb cannot launch a physical XCTest. It can serve as another launcher for a test runner, which retains the underlying XCTest dependency. [device XCTest source](https://github.com/facebook/idb/blob/main/FBDeviceControl/Commands/DeviceXCTestCommands.swift)

## go-ios and DeviceKit: fewer layers, same test subsystem

Current go-ios commands include:

```sh
ios --udid=<udid> ui run wda --host-port=<free-port>
ios ui tap --x=100 --y=200 --driver=wda --session-id=<existing-session>
ios ui swipe --from-x=100 --from-y=500 --to-x=100 --to-y=100 --duration=0.3 --driver=wda --session-id=<existing-session>
```

These are source examples, not instructions to execute against a current session. `ui run` starts `testmanagerd.RunTestWithConfig` and forwards the runner's port. WDA tap calls `/session/.../wda/tap/...`; swipe calls `/wda/dragfromtoforduration`. DeviceKit calls `device.io.tap` or `device.io.swipe` over JSON-RPC. [launcher implementation](https://github.com/danielpaulus/go-ios/blob/main/cmd_device_ui_run.go), [UI client](https://github.com/danielpaulus/go-ios/blob/main/cmd_ui.go)

DeviceKit explicitly runs as an XCUITest. Its hierarchy and touch synthesis wrappers live in its XCTest module. A switch can reduce Appium-specific overhead, but cannot be described as escaping XCTest hangs. Signed artifacts, provisioning and Developer Mode remain relevant. [DeviceKit architecture and requirements](https://github.com/mobile-next/devicekit-ios#architecture), [go-ios install/run command reference](https://github.com/danielpaulus/go-ios/blob/main/main.go)

The go-ios client creates a WDA session when no session ID is supplied. Reusing an existing session avoids repeating this setup. Its source uses a 60-second HTTP timeout. Neither number explains a 15-minute scheduler gap without correlated logs. [UI session and timeout source](https://github.com/danielpaulus/go-ios/blob/main/cmd_ui.go)

## pymobiledevice3: a real alternative injector

Current master implements `UniversalHIDServiceService` over `com.apple.coredevice.hid.universalhidservice`. It sends contact/release reports to the phone's touchscreen surface. `touch_session` also starts a screen media stream. Without that stream, backboardd treats reports as an unsupported external accessory and drops touches. This route does **not** require the WDA HTTP server or a signed XCTest runner. It still requires trusted pairing, usable developer services, a compatible DDI and an unlocked phone for ordinary navigation. [HID implementation](https://github.com/doronz88/pymobiledevice3/blob/4b4e3c04b418d57f205924aae5e314979cc9ccb5/pymobiledevice3/remote/core_device/hid_service.py), [CLI implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/developer/core_device.py)

Examples from the current CLI:

```sh
# UInt16 coordinates, normalized across the screen.
pymobiledevice3 developer core-device universal-hid-service tap -- 32768 32768
pymobiledevice3 developer core-device universal-hid-service drag --duration 0.3 -- 32768 55000 32768 15000
pymobiledevice3 developer core-device universal-hid-service session --script gestures.txt
```

The script accepts `tap`, `drag`, `move`, `swipe` and bounded sleeps. **Here `drag` produces the finger contact used for a feed swipe. The command named `swipe` sends pointer motion without touch contact.** Using the wrong command can succeed at the protocol level while failing to navigate TikTok. Type commands support printable ASCII through a virtual HID keyboard; do not presume arbitrary Unicode entry. [CLI recipes](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md), [touch/keyboard command source](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/developer/core_device.py)

A persistent session can amortize the tunnel/media setup. The current default creates an in-process userspace tunnel per command; the guide says that adds startup latency. On macOS, its native tunnel can be lower latency, but the guide also describes competing RSD connections evicting one another. A persistent, exclusively owned connection is the better experiment. Transport support from iOS 17.4 onward does **not** establish the HID service's own OS support. [tunnel support and caveats](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md)

### Known failure with direct HID

Issue 2036 documents a real iPhone 11 on iOS 27.0.1. It used a personalized Xcode 27 DDI on a macOS 26 host. One-shot commands returned success but every touch was dropped with a 0.3-second authentication wait. Increasing the total wait to 0.4 or 0.5 seconds delivered touches. Release 11.33.1 raised the default wait to 0.5 seconds. A comment reports that 0.1 seconds worked on an iPhone 15 Pro. This is limited device evidence, not a general latency benchmark. [issue and reproduction](https://github.com/doronz88/pymobiledevice3/issues/2036), [fix release](https://github.com/doronz88/pymobiledevice3/releases/tag/v11.33.1)

The lesson applies to both bridges: successful submission does not prove that the UI changed. Observe the selected tab or new screen before counting navigation as complete.

## ipb: promising, version constrained, explicitly incomplete acceptance

`ipb` means iOS Physical-device Bridge. Its README calls it an ADB equivalent and says it was formerly `devicehubctl` and briefly `hdb`. It exposes `tap`, `swipe`, `scroll`, keys, Home, Recents, a screen stream and an optional accessibility backend. Its HID route uses CoreDevice private services, independently of XCTest and WDA. [README](https://github.com/ipbtools/ipb)

Its requirements specify CoreDevice 636.x+, Xcode 27's private-framework stubs and DDI, macOS 27, and an iOS 27+ phone. It dropped iOS 26 on 20 September because no device remained for verification. The README says the gesture surface was absent on iOS 26 and Xcode 26's DDI lacks `dtuhidd`. That is a support boundary, not proof that all direct HID is impossible on iOS 26 with another compatible DDI. [requirements](https://github.com/ipbtools/ipb#requirements), [wire protocol and DDI](https://github.com/ipbtools/ipb/blob/main/docs/protocol.md)

Important limits from its own documents:

- Version 0.5.0 publication proceeded after host/package checks without another full physical-device run. The supported physical acceptance gate remains open.
- Ordinary and deep accessibility graphs have different coverage. Settings examples are much smaller than XCTest trees.
- Measured query medians include different graph scopes, so AX versus WDA numbers are not a bridge-only speed comparison.
- Its native deep snapshot study reports 10/10 success on one Bilibili page, but a later transition still caused a supplementary read failure.
- The default helper watchdog is 30 seconds and its post-send settle is 700 milliseconds. Those are configured waits, not measured end-to-end action latency.

[verification scope and measurements](https://github.com/ipbtools/ipb/blob/main/docs/verification.md), [UI guide](https://github.com/ipbtools/ipb/blob/main/docs/ui.md), [runtime parameters](https://github.com/ipbtools/ipb#choosing-a-device)

Examples suitable for a future reserved iOS 27 test are `ipb -s <CoreDevice-UUID> tap 0.5 0.5`, `ipb ... swipe 0.5 0.75 0.5 0.35` and `ipb ... ui --deep --json`. CoreDevice UUID is not the phone UDID. No test was run here.

That experiment also needs a supported macOS 27 host and the required CoreDevice/Xcode stack; calmer's iOS version alone does not satisfy the matrix.

## iOS 26 evidence needs its own test

The rPlayHub project's own harness documentation reports live tap/swipe on an iPhone 12 Pro running iOS 26.5.2 over USB. It uses universal HID plus an active media stream. This supports testing availability on the current iOS 26.6.2 phones. It does not prove compatibility, reliability or session stability on those phones. The same page explicitly calls its Python code an experiment harness, not a shipping artifact; its HEVC recording still had packet-loss glitches. [maintainer's reported device evidence](https://github.com/rPlayAI/rPlayHub/blob/main/host/README.md)

## libimobiledevice, usbmuxd, ADB and “ADP Bridge”

`usbmuxd` multiplexes socket connections to services listening on the phone. `libimobiledevice` implements services such as pairing, device information, files, screenshots, logs and image mounting. These are useful for transport and diagnostics, but neither project's documented core interface provides arbitrary native tap/swipe injection. Adding them underneath WDA does not remove WDA. [usbmuxd design](https://github.com/libimobiledevice/usbmuxd#features), [libimobiledevice features](https://libimobiledevice.org/)

ADB is Android Debug Bridge. Android runs its `adbd` daemon; stock iOS does not provide that Android service. The phrase “ADP Bridge” did not identify a primary-source iPhone control project in this search. It may mean ADB, or an iOS ADB-style bridge such as ipb, but that remains an interpretation. [official ADB architecture](https://developer.android.com/tools/adb)

Apple documents enabling Developer Mode through a restart and user confirmation. Do not silently change that state during a benchmark. [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

## What evidence is still missing

No inspected source provides a controlled TikTok/Reels comparison of WDA, DeviceKit, pymobiledevice3 HID and ipb on our exact devices. No source demonstrates that changing the bridge removes these 15–16-minute execution gaps.

A useful comparison records cold startup separately from warm actions. Measure command enqueue, dispatch, response, visible screen change and planner continuation. Compare missed/wrong actions and p50/p95/p99 completion time. Repeat after screen streaming, app switching and a bounded disconnect. Keep one command owner per phone and re-observe any uncertain mutation before another action.

## Inspected revisions

These repositories were unarchived when checked. Recent activity proves maintenance, not suitability:

| Repository | Main commit inspected | Last push reported by GitHub |
| --- | --- | --- |
| facebook/idb | `8ac770ad571152e877f730ed73f4430eda4a2f41` | 2026-10-23 |
| doronz88/pymobiledevice3 | `4b4e3c04b418d57f205924aae5e314979cc9ccb5` | 2026-10-22 |
| danielpaulus/go-ios | `ca2c56d2c294ff702cadf4821edd30b069d3a264` | 2026-10-09 |
| ipbtools/ipb | `bf3fcad375db5e11d5573a7ef11fa9a02c8cd1d7` | 2026-10-21 |
| rPlayAI/rPlayHub | `fe6a7a9f1cff431acfda142cd3564fc8e0e849a3` | 2026-10-01 |
| mobile-next/devicekit-ios | `9f0dd67710bf3a1847d990eb23adbbbdcbb46258` | 2026-10-17 |

Metadata was read through each repository's GitHub REST `repos/<owner>/<repo>` and `commits/<default_branch>` endpoints.
