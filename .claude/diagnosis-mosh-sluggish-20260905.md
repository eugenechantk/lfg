# Why mosh-bridged feels sluggish — 2026-09-05

## Headline

The Air and the Pro are on the **same LAN** (identical gateway MAC `5c:4d:bf:9b:79:fc`,
192.168.0.76 / 192.168.0.242), but every keystroke between them travels via **Surfshark
WireGuard exits in Taiwan and Cloudflare's TPE edge** — a ~150–250ms round trip with ±30ms
jitter for machines that are physically metres apart — and the TCP carrier freezes for
multiple seconds whenever it drops, which is routine.

## Measurements (2026-09-05, ~23:00 HKT)

| Probe | Result |
| --- | --- |
| Air → CF edge (`ping ssh-pro.eugenechantk.me`) | min 48.5 / avg 72.7 / max 114.8 ms, stddev 27.4 |
| Pro → CF edge (`ping ssh-air.eugenechantk.me`) | min 49.5 / avg 97.8 / max 131.9 ms, stddev 28.3 |
| Warm ssh exec Air→Pro (ControlMaster reused, best of 15) | 0.38 s |
| `curl one.one.one.one/cdn-cgi/trace`, both hosts | `colo=TPE`, `loc=TW` — both exit through Surfshark Taiwan |
| Default route, both hosts | `utun4` (Surfshark WireGuard) ahead of `en0` |
| LAN ping Air→Pro (192.168.0.242) | 100% loss — Surfshark blocks LAN traffic (mDNS too, which is why `eugenes-macbook-pro` doesn't resolve) |
| Carrier drops (`~/Library/Logs/mosh-bridge.log`) | 247 lifetime; **46 today**, 74 on 08-31; respawn backoff 1→2→4→8 s |

## The three compounding causes

1. **Path length.** Keystroke echo = Air → Surfshark(TW) → CF TPE → Pro's cloudflared tunnel
   → Surfshark(TW) → Pro, and back. Sum of the two edge legs ≈ 150–250 ms per echo. The same
   two machines over their own LAN would be ~1–2 ms.
2. **TCP carrier defeats mosh's design.** mosh assumes UDP: fire datagrams, tolerate loss,
   pace frames off its RTT estimate. `mosh-bridge` frames those datagrams over ssh/TCP (inside
   WireGuard): nothing is ever lost, only delayed, so bufferbloat spikes inflate mosh's RTT
   estimator and it paces frames slower; one delayed segment head-of-line-blocks everything
   behind it. Prediction can't mask it either — codex/claude redraw the composer per keystroke,
   so you feel the raw RTT.
3. **Carrier drops = multi-second freezes.** Each ssh carrier death (WireGuard rekey/roam,
   tunnel hiccup) freezes the session for the backoff (up to 8 s) plus a full
   cloudflared-Access + ssh handshake (~1–3 s). At 46/day this is a large share of perceived
   sluggishness.

Not the faint-patched build — these are path/carrier properties, identical under stock mosh.

## LAN fast path — implemented + measured (same day)

Follow-up probes: LAN **TCP/22 passes in both directions** (only ICMP/mDNS/unsolicited-UDP
are filtered — the Pro's side drops unsolicited inbound UDP, so real mosh UDP works
Pro→Air but not Air→Pro). So `mosh-bridged` now probes the peer's pinned LAN IP
(`nc -z` TCP/22, 1s) and, when it answers, runs the same datagram bridge over **direct
LAN ssh** instead of the Cloudflare tunnel. The carrier wrapper retries LAN → tunnel on
every respawn, so a session survives leaving the house and re-upgrades on return.
`LFG_MOSH_NO_LAN=1` forces the tunnel. LAN host keys are pre-seeded with
`StrictHostKeyChecking=yes` so a foreign device holding one of the pinned RFC1918
addresses can never TOFU-poison known_hosts (it just falls back to the tunnel).

Measured keystroke echo (true round trip via remote `tr`, not mosh's predictive echo —
a `cat` echo test measures prediction and reads 0ms):

| path | min | median | max |
| --- | --- | --- | --- |
| LAN fast path | 17–19 ms | 41–51 ms | ~180 ms |
| Cloudflare path | 233 ms | 364 ms | 494 ms |

~9× faster at home; the remaining LAN jitter is Wi-Fi power-save. Deployed both hosts.

## Remaining options for the remote (not-on-LAN) case

- **Split-tunnel cloudflared out of Surfshark** (Bypasser): both edge legs currently pay
  the Taiwan exit (~50–115 ms each); a direct path to the nearest CF PoP should cut echo
  to roughly 40–80 ms and stop VPN rekeys from killing carriers. Needs the Surfshark app
  UI on both Macs — exempt `/opt/homebrew/bin/cloudflared` (the ssh client leg rides
  inside cloudflared's proxy, so exempting cloudflared covers it).
- **Direct WireGuard (Tailscale) between the Macs** would beat the double-CF hop when
  remote, but Tailscale was deliberately deprecated for lfg client access 2026-08-22 —
  reintroducing it even terminal-only is Eugene's call. The tailnet is still intact (both
  Macs logged in, apps stopped; Air 100.75.162.40, Pro 100.120.101.14), and `mosh-bridged`
  now carries a **pre-wired Tailscale tier**: candidates are probed LAN → Tailscale → CF,
  with host keys pre-seeded for the 100.x addresses. While Tailscale is stopped the probe
  fails in 1s bounded (nothing at home, +1s connect when remote); the moment both Macs run
  Tailscale, remote sessions take the direct WireGuard path with no further changes.
- iOS/desktop lfg clients are unaffected — this is about terminal sessions.
