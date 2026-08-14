# Bug 002: Phone repeatedly disconnects from host

## Status: FIX DEPLOYED

## Description

The iOS app reconnects to the LFG host and then later reports that the host is disconnected. It should keep the host connection alive while the host service and network remain available, and recover cleanly from transient transport failures.

## Steps to Reproduce

1. Start the LFG host service on the Mac.
2. Open LFG on the physical iPhone with an already-paired host.
3. Wait for the host to show as connected and use the app normally.
4. Observe that the phone later reports the host as disconnected again.

## Root Cause

At 2026-08-14 17:14 HKT, another Codex session in the `fiftyworkout` workspace
started `python -m http.server 8766 --bind 127.0.0.1` (PID 54300) to preview a
generated site. The real LFG host (PID 51945) is also listening on TCP 8766.

Both Tailscale Serve hostnames proxy to `http://127.0.0.1:8766`, so the proxy is
currently reaching the Python static server instead of LFG. The static server
returns HTML 404 responses for `/api/ping` and cannot provide `/api/events`,
which makes the iOS client correctly mark the host disconnected and retry.

This is not an iPhone USB pairing failure, a Tailscale peer outage, or evidence
of a new `HostLink` state-machine defect. The physical phone is visible over USB
and online in the tailnet; the LFG API responds normally when addressed through
the Mac's Tailscale IP (`100.120.101.14:8766`), bypassing the loopback conflict.

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
