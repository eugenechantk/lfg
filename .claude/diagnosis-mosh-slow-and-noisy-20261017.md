# Why mosh/ssh to the Pro is slow and noisy — 2026-10-17

Working notes; measurements first, fixes at the bottom. Session on the Air (192.168.0.50).

## Measurements (before any change, ~21:20–21:45 HKT)

| Probe | Result |
| --- | --- |
| Air Wi-Fi | SSID **Red Chan**, gateway MAC `6c:5a:b0:95:a2:c`, -52 dBm, ch 157 |
| Pro Wi-Fi | SSID **3Broadband_79FC_5G**, gateway MAC `5c:4d:bf:9b:79:fc`, -47 dBm, ch 149 |
| LAN TCP/22 Air→Pro (.182) and Pro→Air (.50) | both time out — **different routers that both use 192.168.0.0/24** |
| Surfshark exit, both Macs | `colo=SJC loc=US` (Air quick-connect = "US region fastest") |
| Air → CF edge via VPN (curl tcp connect) | 168–338 ms |
| Air → CF edge via en0 directly | 7–10 ms (edge = HKG) |
| Pro → CF edge via VPN / en0 | 180 ms / 29 ms |
| Air `cloudflared access ssh` socket source | `10.12.130.78` = **utun, not bypassed** despite Cloudflared.app in the Bypasser list |
| Pro's lfg-pro tunnel | edge-bound to en0, registered at hkg — fine |
| Air's lfg-air tunnel | answered **530** from both Macs (stale edge connections); restarted 21:32 → 200 |
| `ssh pro` connect (Air) | 1.0–3.4 s; banner at 1.6 s, kex+auth +3 s (7 round trips × 170 ms) |
| `ssh air` connect (Pro) | 5.2–5.9 s; banner 1.8 s, kex+auth +2.6 s |
| ssh keystroke echo Air→Pro | n=30 min 31 / p50 171 / p90 657 / max 1401 ms |
| ssh keystroke echo Pro→Air | n=30 min 338 / p50 348 / p90 476 / max 528 ms |
| mosh-bridged keystroke echo Air→Pro | n=40 min 37 / p50 97 / p90 350 / max 1849 ms |
| mosh-bridged connect to prompt | **14 s** = 3 dead LAN probes (3 s) + /24 sweep (~3 s) + bootstrap ssh (~4 s) + carrier ssh (~4 s) |
| Carrier deaths today (`~/Library/Logs/mosh-bridge.log`) | 10:19 10:53 11:08 11:46 12:00 12:25 12:42 13:08 13:40 13:58 14:09 14:35 — every 15–35 min |
| Surfshark log at 12:25:06 and 13:08:01 | `IDAC connectionUnavailable` — the Air's VPN link blinked at the same seconds |
| Air sleep log | no sleep between 10:00 and 14:52 — the drops are not sleep |

## Causes, in order of weight

1. **The two Macs are on different Wi-Fi networks.** The LAN fast path (~40 ms echo, no Cloudflare) can never engage; every session takes the tunnel, and every connect wastes ~6 s probing and sweeping a LAN the Pro is not on.
2. **Both Access ssh clients ride the VPN to a US exit.** 170–180 ms edge RTT instead of 10–30 ms, on both legs. Surfshark's Bypasser does not catch the ProxyCommand's cloudflared. This also explains the carrier deaths: the carrier TCP stream lives inside the VPN, and Surfshark's own log shows the link going unavailable at the exact seconds the carriers died.
3. **Carrier deaths print ssh's stderr onto the mosh screen.** `websocket: bad handshake` (edge said no while the path was down), `Connection closed by remote host`, `client_loop: send disconnect` — all from the respawn cascade, none actionable.
4. **Connect cost is two full Access+ssh handshakes plus serial 1 s probes.** Each handshake is ~4 s at VPN RTT.
5. The Air's own tunnel had gone stale (530) — Pro→Air was 100 % broken until restarted. Separate, now fixed; cloudflared's DNS refresh fails through the VPN (`lookup region1.v2.argotunnel.com: i/o timeout`).

## What the uplinks actually are (found while A/B-testing)

| Mac | Wi-Fi | Router | Public IP | en0 → HKG edge TCP connect |
| --- | --- | --- | --- | --- |
| Air | Red Chan | TP-Link `6c:5a:b0:95:a2:c` | 218.102.217.104 (HKT/PCCW fixed line) | 6–7 ms, 30/30 samples same IP, 1/30 > 50 ms |
| Pro | 3Broadband_79FC_5G | `5c:4d:bf:9b:79:fc` | 124.217.188.60 (3 HK **5G home broadband**) | 29–150 ms, jittery |

So the Pro's tunnel leg rides a cellular uplink. That is the floor for Air→Pro keystrokes as long
as the Pro stays on 3Broadband and the Air is not on the same LAN: the hop-by-hop series
(gateway ping 3–5 ms, en0→edge 6 ms) showed the echo jitter is *not* the Air's Wi-Fi or ISP.
Periodic 60–90 ms gateway-ping stalls (every ~7 s, AWDL active) appeared in one run and not the
next — minor.

## Fixes landed (2026-10-17 21:40–22:00)

1. **VPN bypass for the Access ssh client** — `scripts/cloudflared-en0-connect.py` + new
   `scripts/lfg-cloudflared-ssh`, installed to `~/.local/bin` on both Macs (backups
   `lfg-cloudflared-ssh.bak-20261017`). A loopback CONNECT proxy bound to en0's address carries
   cloudflared's TLS to the edge; `HTTPS_PROXY` points cloudflared at it; stdio untouched. Falls
   back to the VPN path when en0 can't reach the edge; `LFG_CF_DIRECT=0` forces the fallback.
   Log: `~/Library/Logs/cloudflared-direct.log`.
   - Pro→Air keystroke echo, interleaved A/B ×2: direct p50 **116** / p90 200–230 ms vs VPN p50
     412–414 / p90 467–494 ms. `ssh air` connect 5.2–5.9 s → **1.3–1.5 s**.
   - Air→Pro: direct and VPN both land at p50 ~90–440 ms across runs — the Pro's 5G uplink
     dominates, the VPN exit no longer does (Air en0→edge 6 ms vs VPN 167 ms).
   - Side effect: the carrier stream no longer lives inside the Air's VPN, so Surfshark's
     `connectionUnavailable` blinks (the cause of today's 12 carrier deaths) can't kill it.
2. **Carrier stderr goes to the log, not the screen** (`scripts/mosh-bridge`): every ssh death
   line is logged with the carrier pid; the terminal is told only after
   `LFG_BRIDGE_QUIET_SECS` (45 s) without a carrier, once a minute, with the last error, and
   "carrier restored" afterwards. Verified: SIGKILL of the carrier printed 0 bytes to the pty,
   respawn echoed again in 1.7 s, log has `carrier exited -9` / `carrier back after 1s down`.
   **Sessions started before 21:55 still run the old code** — reconnect to pick it up.
3. **Connect time 14 s → 4.1–4.5 s** (`scripts/mosh-bridged`): LAN candidates probed in
   parallel (3 s → 1 s); the /24 sweep is skipped when the router MAC is not the one the peer was
   last found on (`~/.cache/mosh-bridged/<target>.gw`, written on each LAN success, seeded with
   the Pro's router now), at most once per 10 min elsewhere; ssh ControlMaster shares the
   bootstrap handshake with the carrier (`~/.ssh/cm-mosh-*`, ControlPersist 20 s).
4. **Air tunnel restarted** (`launchctl kickstart -k gui/501/dev.omg.lfg-air-cloudflared`):
   ssh-air 530 → 200 on both Macs. Its cloudflared logs `Failed to refresh DNS local resolver …
   i/o timeout` through the VPN; worth watching for a repeat.

## What only Eugene can change

- **Put both Macs on one Wi-Fi.** Then the LAN fast path engages (Sept measurement: p50 ~45 ms
  echo, no Cloudflare, no uplink at all) and the Pro's 5G link drops out of the loop. Red Chan
  (fixed line, 6 ms) is the better network for the Pro too if it is his to use.
- Surfshark's quick-connect on the Air is "US region fastest" (SJC, 167 ms). No longer in the
  ssh path after fix 1, but every other app on the Air pays it; a HK location would cut it to
  ~10–20 ms.
- Optional: switch the Pro's tunnel to QUIC now that it is en0-bound (the 2026-09 QUIC flapping
  was the VPN utun). Not done — remote tunnel restarts need a dead-man revert and the gain on a
  5G uplink is unproven.

## Probes (kept in `.claude/tools/net-latency/`)

`ssh-echo-probe.py` (per-byte echo over an ssh command), `mosh-echo-probe2.py` (same through
mosh-bridged, login shell + `tr`), `hop-series.py` (echo + gateway ping + en0→edge per 0.25 s),
`mosh-e2e.py` (connect, echo, carrier kill, leak check). Measure echo via a remote upper-casing
command, never `cat` — mosh predicts the lowercase locally.
