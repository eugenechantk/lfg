---
title: Step 3 — check independent CoreDevice HID
subtitle: Service unavailable in the current phone configuration · zero HID input sent
lang: en
template: doc
theme: shadcn
---

## Result

```callout warn The current environment blocks the gesture trial
The exact hihi phone advertised seventy-three remote services, with no universal HID or display service.
The mounted-image query confirms a developer image at /System/Developer.
No independent HID gesture ran.
```

This establishes a limitation of the current configuration. It does not prove that every iOS 26 configuration lacks HID support.

## Verified scope

The probe used pymobiledevice3 11.33.1 in an isolated uv environment.
It selected hihi by its exact UDID, checked the returned identity, and held the existing operation lock.
Its closeable userspace USB tunnel avoids taking over Apple's native RSD connection.
Automatic pairing and network fallback remained disabled. Discovery finished in 0.319 seconds.

The probe inspected advertised service names. It would list HID surfaces only if the service appeared.
It sent zero touch reports. It mounted or unmounted no developer image.
It changed no setting and created no WDA session.

Evidence: [capability result](capability-result.json), [mounted-image check](mounted-images.json), [probe source](capability.py).

## What a useful follow-up requires

Use a separate test phone and a developer image that exposes the universal HID and display services.
Verify compatibility before replacing any mounted image. Preserve existing scheduled-phone sessions during that work.
Then compare persistent touch sessions against the same Settings acceptance checks.
Measure media and tunnel startup separately from warm input.

The upstream implementation requires an active media stream to authorize touches.
Its drag command creates finger contact; its swipe command moves a pointer without contact.
A successful protocol response still needs screen verification.
[HID source](https://github.com/doronz88/pymobiledevice3/blob/4b4e3c04b418d57f205924aae5e314979cc9ccb5/pymobiledevice3/remote/core_device/hid_service.py), [CLI source](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/cli/developer/core_device.py).

The ipb project's supported matrix requires macOS 27, Xcode 27 and iOS 27+.
This host runs macOS 26.6.2. Upgrading the host to try a bridge is outside this bounded experiment.
[ipb requirements](https://github.com/ipbtools/ipb#requirements).
