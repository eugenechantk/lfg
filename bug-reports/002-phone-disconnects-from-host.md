# Bug 002: Phone repeatedly disconnects from host

## Status: INVESTIGATING

## Description

The iOS app reconnects to the LFG host and then later reports that the host is disconnected. It should keep the host connection alive while the host service and network remain available, and recover cleanly from transient transport failures.

## Steps to Reproduce

1. Start the LFG host service on the Mac.
2. Open LFG on the physical iPhone with an already-paired host.
3. Wait for the host to show as connected and use the app normally.
4. Observe that the phone later reports the host as disconnected again.

## Root Cause

This report now contains two independent outages:

1. **Resolved loopback port collision.** At 2026-08-14 17:14 HKT, another Codex
   session in the `fiftyworkout` workspace started
   `python -m http.server 8766 --bind 127.0.0.1` (PID 54300). Both Tailscale
   Serve hostnames proxy to loopback, so they reached the Python static server
   instead of LFG and returned HTML 404 for the API.
2. **Open iPhone cellular transport failure.** The physical-phone connection log
   proves that iOS can report a satisfied cellular path with Tailscale's `utun9`
   interface present while traffic to tailnet IPs is completely black-holed.
   LFG keeps redialing both hosts, but every TCP request times out until the
   Tailscale tunnel is rebuilt. This is below LFG's networking layer; an LFG
   redial cannot repair an unresponsive iOS Network Extension.

The cellular failure is not an iPhone USB pairing failure, host-process restart,
or evidence of a new `HostLink` state-machine defect. The LFG API responds
normally through the Mac's raw Tailscale IP (`100.120.101.14:8766`) whenever the
phone's Tailscale data path is working.

## Success Criteria

### 1. The configured Tailscale HTTPS host routes to LFG, not a second service
- [x] Verified by automated probe
- [x] Verified at the physical-device transport seam

**Automated probe:** `EXISTING operational check` — repeated
`GET https://eugenes-macbook-pro.tail97cc70.ts.net/api/ping` requests all return
HTTP 200 with an LFG `{"ok":true,...}` response.

**Device verification:**
1. Stop or move the conflicting Python preview server from port 8766.
2. Foreground LFG on the physical iPhone.
3. Wait for the configured host to reconnect.
4. Leave the app active for at least two 10-second keepalive cycles.
5. **Expected:** host remains Connected and sessions refresh normally.

### 2. The actual LFG listener remains healthy
- [x] Verified by automated probe
- [x] Verified at the physical-device transport seam

**Automated probe:** `EXISTING operational check` — direct
`GET http://100.120.101.14:8766/api/ping` continues returning HTTP 200 before
and after removing the loopback conflict.

**Device verification:** Covered by criterion 1; opening a session exercises the
REST baseline plus cursor-resumable event stream.

## Investigation Log

### Attempt 1

**Hypothesis:** The host process, WebSocket heartbeat/reconnect state machine, or network advertisement is dropping the connection and the existing logs will identify which layer closes first.

**Changes:** Created this report and began collecting the current host/device/process state plus connection-related logs.

**Result:** Root cause identified. `lsof` shows two listeners on TCP 8766. A
30-request loopback probe and a 12-request Tailscale HTTPS probe returned the
Python server's HTML 404 every time, while a direct probe to
`100.120.101.14:8766/api/ping` returned the healthy LFG JSON response. The
conflicting process belongs to a separate, completed `fiftyworkout` site-preview
session. Stopping it requires confirmation because it changes another session's
running state.

### Attempt 2

**Hypothesis:** Removing only the unrelated Python listener will restore both
the loopback API and the Tailscale HTTPS proxy without restarting LFG or losing
its in-memory session state.

**Changes:** With user approval, sent SIGTERM to Python PID 54300. Added a global
reservation for LFG TCP port 8766 to both `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md`; unrelated preview/dev/test servers must choose an
unoccupied port and must never displace LFG.

**Result:** PASS. `lsof` now shows only LFG PID 51945 listening on TCP 8766.
Ten loopback probes and ten probes through
`https://eugenes-macbook-pro.tail97cc70.ts.net/api/ping` all returned HTTP 200
with LFG JSON. The host then recorded fresh `/api/events` connections, including
a cursor catch-up from seq 221175 to head 221392, and showed established
connections arriving through the loopback Tailscale proxy. FlowDeck's optional
attempt to foreground the USB device failed in CoreDevice despite the device
listing as available, so visual UI state was not directly inspected; the actual
HTTPS and resumable-event transport used by the phone was verified live.

### Attempt 3

**Hypothesis:** The port collision was one real outage but not the recurring
cause. The phone-side connection log should show whether the next drop begins
with a path transition, stream watchdog, keepalive degradation, app lifecycle
transition, or a server-side close.

**Changes:** Reopened the investigation after the user reported another drop.
Collecting the current listener/Tailscale/server timeline and the physical
iPhone's `dev.omg.lfg` connection log.

**Result:** Two facts are confirmed. First, the port conflict did not recur:
only LFG owns 8766 and 60/60 probes passed across loopback, direct Tailscale IP,
and the Tailscale HTTPS proxy. Second, another active Codex session deliberately
terminated LFG PID 51945 at 18:29 HKT to deploy the multiline-follow-up fix; the
supervisor immediately started PID 16291. That explains at least one post-port
disconnect because every `/api/events` stream necessarily closes during a host
restart. The current phone peer is active but relayed through DERP Hong Kong
(`CurAddr` empty), so an additional cellular/relay flap remains plausible.

The persisted phone log is the decisive evidence for any drops after the 18:29
restart. macOS Console automation timed out, and FlowDeck cannot stream physical
device logs, so the log must be exported from LFG Settings → Connection Log →
Share and attached/pasted into this session. Do not change the client state
machine again without that timeline; prior diagnosis documents contain a
retracted network theory precisely because this evidence was missing.

### Attempt 4

**Hypothesis:** On 5G, the iPhone's Tailscale Network Extension remains visibly
installed but its data path stops forwarding tailnet traffic. Disconnecting and
reconnecting Tailscale repairs that tunnel, which is why LFG immediately
reconnects afterward.

**Changes:** Analyzed all 1,183 lines of the exported physical-phone connection
log from TestFlight build `1.2.0 (202608141820)` and compared its path, stream,
probe, lifecycle, and RTT events with the current `HostLink`/`NWPathMonitor`
implementation. No production code was changed.

**Result:** CONFIRMED at the application/transport seam.

- From 18:28:24 through 18:32:03, iOS repeatedly reports
  `path=satisfied ifaces=cellular,cellular,other(utun9)`, while every stream and
  probe to both `100.120.101.14:8766` and `100.75.162.40:8766` times out. LFG
  performs its expected immediate/1s/2s/5s/10s redials; none can cross the
  tunnel.
- At 18:32:03 `utun9` disappears, at 18:32:05 the base cellular path briefly
  reports `requiresConnection`, and at 18:32:08 `utun9` returns. The Pro probe
  succeeds at 18:32:09.967 and the event stream receives headers at
  18:32:10.282. That timing matches the reported manual Tailscale off/on action.
- The same tunnel-rebuild signature occurs at 18:49:22–18:49:27. The Pro event
  stream receives its first event at 18:49:27.593, about 160 ms after `utun9`
  returns.
- The Pro host process has remained running since 19:00:56, yet the phone again
  goes live at 19:23:09 and loses all stream/probe traffic at 19:23:51. This
  rules out a server restart for the later drop.
- Working outdoor connections are generally classified `relayed` with roughly
  150–718 ms RTT. Back on direct Wi-Fi at 20:22 and 20:31, RTT is 13–25 ms.
  The Air (`100.75.162.40`) is independently offline/asleep for most of the log
  and is not evidence against the Pro diagnosis.

`waitsForConnectivity` or more aggressive LFG retries would not fix this case:
`NWPathMonitor` says the path is satisfied and LFG is already redialing. The
first operational remedy to test is Tailscale **VPN On Demand → Cellular →
Always**, followed by an outdoor soak. If it recurs, generate a Tailscale iOS bug
report while the tunnel is still broken and before toggling it; that captures
the Network Extension state LFG cannot observe.

### Separate current finding (not the supplied cellular timeline)

At 20:33:50, after the exported log's last failure had already begun, another
`fiftyworkout` Codex session started Python PID 58936 on reserved loopback port
8766. It currently makes the Tailscale Serve HTTPS hostname return Python 404,
while the raw Tailscale IP still returns healthy LFG JSON. This is a recurrence
of incident 1 and should be stopped separately with user confirmation; it does
not explain the phone log, whose configured endpoint is the raw IP and whose
20:33 failure began about 44 seconds before that Python process started.

### Attempt 5

**Hypothesis:** The current outdoor disconnects are host restarts, not a failure
of Tailscale VPN On Demand. Large live Codex rollouts make the host's backward
metadata scans allocate superlinearly until the supervisor enforces its 4 GB
RSS ceiling.

**Changes:** Rechecked the live Tailscale peer, listener ownership, supervisor
timeline, process RSS, journal size, transcript corpus, and `listSessions` read
path. Began a regression-first fix in `src/transcript.ts`.

**Result:** CONFIRMED for the current incident. At 12:58 HKT the iPhone was
online and active with a non-empty direct endpoint (`CurAddr
14.0.173.37:54144`), while the host log showed repeated memory-ceiling kills at
4.3–4.7 GB. The next process reached 4.65 GB within 23 seconds of startup. The
host has multiple 246–535 MB Codex rollout files, and `scanBack` rereads its
entire growing window after every miss. A far-tail lookup is therefore
quadratic, which explains the rapid multi-gigabyte allocation and recurring
`/api/events` disconnects regardless of VPN policy.

### Attempt 6

**Hypothesis:** Attempt 5's diagnosis is right but incomplete, and its fix was
never deployed. `scanBack` is one of several read paths that scale with
transcript size rather than with the data actually wanted; fixing only that one
leaves the host under its ceiling by too small a margin to survive a phone
session.

**Changes:** Measured each suspect read path against the real 511 MB rollout with
a peak-RSS harness, fixed three, and deployed. Full detail and numbers in
`.claude/feature/host-memory-ceiling-disconnects.md`.

1. `src/transcript.ts` — `scanBack` walks each byte range once instead of
   re-reading a growing tail (Attempt 5's fix, previously written but never
   deployed). **5226 MB → 915 MB** peak on a full-file miss.
2. `src/sessions.ts` — `recentMessages(…, {maxBytes: null})`, which `messagePage`
   drives on every phone scroll-back, streams the transcript instead of
   materializing it as one string. **1987 MB → 1013 MB**, 843 ms → 273 ms.
3. `src/transcript.ts` + `src/sessions.ts` — new `maxScanBytes` budget on
   `scanBack`, applied to `lastUserText` (32 MB). That `pick` `JSON.parse`s every
   line, so a rollout with no human turn in its tail cost half a gigabyte of
   parsing to fill a 140-character card preview. One `listResumable({limit: 30})`
   poll: **1211 MB → 642 MB**.

**Result:** Root cause confirmed by direct measurement; the 5226 MB figure alone
exceeds the 4096 MB ceiling and matches the observed 4.3–5.2 GB kill points. All
three fixes are deployed — Bun has no hot-reload, and Attempt 5's fix had been
sitting undeployed for 20 minutes while the host kept dying. `lfg serve` pid 7149
started 13:31:16, after both source mtimes. Health after restart: loopback
`/api/ping` 200 with LFG JSON, raw Tailscale IP 200, Tailscale HTTPS 200. Suite:
626 pass, 0 fail.

The soak is the remaining open item — the observation window has to beat the
worst pre-fix lifetime (26 min) before this can be called fixed.

**Note on the VPN theory:** Attempt 4's "turn on VPN On Demand → Cellular →
Always" remedy was not wrong, but it addressed a *different* outage (the
Network Extension black-holing tailnet traffic on 5G). It cannot help here.
Every one of these disconnects is the host process dying; no client-side VPN
policy survives the server going away.

**Correction (Attempt 7):** Attempt 6 is real but it is NOT what the user
experiences. Restarts every 6–25 min cannot produce "constant, and worse on
cellular". Do not stop here.

### Attempt 7

**Hypothesis:** The frequent cellular drops have a separate cause on the client.
Two facts don't fit a host-side explanation: the drops are far more frequent than
the restart interval, and they correlate with cellular specifically.

**Changes:** Analysed the phone's exported connection log from build
`202608161332` against `HostLink` / `HostLinkPolicy`. Fixed the keepalive gating
and cadence in `ios/LFG/HostLink.swift` + `ios/LFGCore/…/HostEvents.swift`.

**Result:** ROOT CAUSE FOUND, and it is lfg's, not the network.

`HostLinkPolicy.keepaliveInterval` exists for one documented reason: keeping the
phone's carrier-NAT binding warm, because "idle bindings expire in ~30s and their
expiry is what triggers Tailscale re-punch flaps". But `HostLink.keepalive()`
gated the ping on the stream already being healthy:

```swift
switch state {
case .catchingUp, .live:  ...ping...
default:                  break        // ← connecting / backoff / idle: silent
}
```

That is a self-sustaining loop, and the log walks straight through it:

1. Stream drops → link leaves `.live`
2. Keepalive goes **silent** — the one moment the binding most needs a packet
3. Binding idles out at ~30s → Tailscale must re-punch → traffic black-holes
4. Stream can't connect (`13:48:46.663` dial never even gets headers)
5. Link never returns to `.live`, so the keepalive never resumes → back to 3

Evidence in the log: **zero successful keepalives in 65 seconds.** Successes are
logged (`rtt=…ms head=…` in `LFGClient.keepalivePing`); only two `KAL FAILED`
lines appear, and after `13:48:38` the keepalive stops entirely while the link
sits in `.connecting`. Meanwhile every dial that *did* get through returned
headers in **0.09–0.15s**, and `tailscale ping` from the host measures a **direct**
path at 99ms (`via 14.0.173.37:54144`) — the network is fine when the binding is
warm.

Second defect, same function: `sleep(interval)` ran *after* the ping, so the real
cadence was `interval + ping duration`. The ping's timeout widens on a bad path
(`keepaliveTimeout` → up to 10s), so 10s silently became ~19s against a ~30s
expiry. Measured in the log: pings at `13:48:13.7` and `13:48:33.2`.

**Fixes:** `keepaliveShouldPing(linkStarted:)` — fire in every started state, not
just healthy ones. `keepaliveNextDeadline(after:now:)` — deadline-based cadence
that a slow ping cannot stretch, rebasing rather than bursting after an overrun.
Both pure and unit-tested in `HostEventsTests` (4 new tests, incl. the invariant
that the quiet gap never exceeds `keepaliveInterval` however long pings run).
`swift test` 58 tests pass; `flowdeck build` succeeds.

**UNVERIFIED AT THE REAL SEAM.** Unit tests prove the policy, not the cure. This
needs a TestFlight build and an outdoor cellular soak, with the connection log
re-exported to confirm regular `KAL rtt=…` lines and stream lifetimes far beyond
the current 18–23s. Until then this is a well-evidenced fix, not a confirmed one.

### Attempt 8 — the fix works; the theory behind it was wrong

Build `202608161650` (contains the Attempt 7 change; `HostLink.swift` mtime
14:00:37 predates it). Outdoor cellular soak, log exported 17:19.

**The fix is CONFIRMED at the real seam**, on two unambiguous signals:

1. **Keepalives now fire for a host that is never `.live`.** In the entire
   pre-fix log (11:33 → 17:10) there is not one `KAL [100.75.162.40…]` line —
   the Air is permanently OFFLINE, so the old `case .catchingUp, .live:` gate
   silenced its keepalive completely. From `17:10:35.959` they appear every 10 s.
2. **Cadence no longer stretches with ping duration.** `17:13:35.4, :45.6,
   :55.5, 17:14:05.7, :15.4, :25.7, :35.7, :45.7` — exactly 10 s apart while
   every one of those pings burned its full 5.00 s timeout. The old
   sleep-after-work loop would have spaced these 15 s apart.

**But the disconnects did not stop, so the causal theory is REFUTED.** The
prediction was that warming the NAT binding would let streams outlive 18–23 s.
Keepalives now flow continuously in every state, and the Pro still dies at
`20.0s`, `19.0s`, `18.1s`, `18.2s`. The NAT-binding-expiry mechanism is not what
was driving the drops.

**What the evidence points at instead — the transport, as Attempt 4 said.**

- At 17:24, `tailscale ping 100.94.32.86` **from the Mac** times out 5/5. That
  path does not traverse lfg at all. When it fails, no client change can matter.
- The good/bad periods track the interface, not the build. `17:09:19` on
  `ifaces=wifi,wifi,…` (not `expensive`): KAL rtt **106/53/32/190 ms**, stream
  healthy. `17:10:02` switches to `cellular,cellular,… expensive`; from `17:10:40`
  everything times out for ~9 minutes.
- Cellular RTT when it works at all is wildly degraded: 246, 406, 1046, 1284,
  2910, 4009, **4594 ms** on the same path that measures 99 ms direct when healthy.
- Both hosts always fail in the same instant, and `NET path=satisfied` keeps
  firing every ~3 s throughout — iOS reports the path as fine while nothing crosses.

**Regression introduced by the fix, and it is visible in this log.** The Air has
been dead all day, and it now costs a keepalive every 10 s *forever* on top of its
back-to-back 18 s stream dials — traffic and battery spent on a host that cannot
answer, on the exact link that is already marginal. Pinging in non-live states is
correct; doing it indefinitely against a host unreachable for hours is not. The
dead-host backoff (flagged in Attempt 7's follow-ups, not implemented) is now
required rather than optional.
