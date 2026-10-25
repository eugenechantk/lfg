# Air→Pro keystrokes slow on the same Wi-Fi: router drops DSCP-marked ssh (2026-10-21)

## Symptom

Both Macs on the same router (gateway MAC `5c:4d:bf:9b:79:fc`, channel 149 5 GHz). Air→Pro
mosh windows lagged like the Cloudflare path. `~/Library/Logs/mosh-bridge.log` showed every
connect today as `LAN bootstrap via eugenechan@192.168.0.182 failed, falling back to tunnel`.
On 2026-10-16 the same IP took the LAN fast path.

## Cause

- The TCP probe (`nc -z`) to `192.168.0.182:22` passed; `ssh` to the same address timed out
  at `connect()`. `ssh -o ProxyCommand='nc %h %p'` worked in 0.2 s.
- `ssh -o IPQoS=none` worked. OpenSSH 10.3 (macOS 26.6.2) defaults to `ipqos ef cs0` and marks
  the socket from the SYN on.
- Python connects with `IP_TOS` set: Air→Pro dropped every odd 802.11 user priority
  (CS1/AF11 → UP1, CS3/AF31 → UP3, EF/CS5 → UP5) and passed even ones (0, AF21/CS2, AF41/CS4,
  CS6). Air→router and Pro→Air passed every marking. So the router's Wi-Fi leg toward the Pro
  drops odd-priority frames. It did not on 10-16; it is router or Pro Wi-Fi state, not code.

## Fix

`scripts/mosh-bridged`: `lan_run` passes `-o IPQoS=none`, so the LAN carrier is unmarked
best-effort. The fallback log line now includes ssh's last error line.

## Verified (interleaved, N=30 each, echo via remote `tr a-z A-Z`)

| Path | Run 1 p50 / p90 | Run 2 p50 / p90 |
| --- | --- | --- |
| LAN (fixed) | 20 / 29 ms | 19 / 22 ms |
| Tunnel (`LFG_MOSH_NO_LAN=1`) | 69 / 79 ms | 69 / 87 ms |

Log shows `LAN fast path via eugenechan@192.168.0.182`. Pro mosh-server count unchanged after
the test (no leaks). Sessions opened before the fix keep the tunnel until reopened.

Probe used: `.claude/tools/net-latency/mosh-echo-probe2.py` (copy that exits cleanly instead of
SIGKILL).
