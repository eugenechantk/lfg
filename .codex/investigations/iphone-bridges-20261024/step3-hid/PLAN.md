# Step 3: independent CoreDevice HID capability

The user approved all operations. Run after the paired WDA comparison finishes.
Target only hihi, UDID 00008110-0011083A1151801E. Hold its existing runtime operation lock.

First use pymobiledevice3 11.33.1 in an isolated uv environment. Open a closeable userspace USB tunnel.
Keep automatic pairing and RemotePairing fallback disabled. Do not use the native tunnel that can evict Apple's RSD connection.
Inspect only advertised service names and, when available, the connected HID surfaces. Bound discovery to 35 seconds.
Create no WDA session. Mount no DDI. Change no phone setting. Send no input during capability discovery.

Only if the independent touchscreen service is available should a persistent touch/media session receive Settings-only navigation.
Measure setup separately from warm commands. Observe every intended destination. Stop uncertain input without replay.
If the service is absent, record that exact environment limitation. Do not claim the bridge can never work on iOS 26.
Leave the original WDA and Appium sessions alive, and leave the phone locked after cleanup.
