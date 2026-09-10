# cloudflared outside Surfshark (Bypasser) — 2026-09-10

## Why
Every keystroke on the Cloudflare path pays two Surfshark exits (Air via Taipei, Pro via
Singapore) plus a Cloudflare edge: ~410–450 ms to the edge measured 2026-09-10 vs 50–115 ms
on 09-05. Both `cloudflared tunnel` daemons also re-register hundreds of times a day
(Air 324, Pro 160 on 09-10) — UDP/QUIC through the WireGuard utun was already replaced by
http2 on 09-08, TCP still flaps. Exempting cloudflared from the VPN removes both.

## What was built (both Macs)
- `scripts/cloudflared-app-wrap.sh` → `~/Applications/Cloudflared.app`: a copy of
  Homebrew's cloudflared, ad-hoc signed with identifier `dev.omg.cloudflared`. Surfshark's
  Bypasser exempts apps by **signing identifier**, and Homebrew's binary is linker-signed as
  `a.out` (every Go binary is), so it could not be selected. Re-run the script after
  `brew upgrade cloudflared`, then reload the tunnel(s).
- `~/.local/bin/lfg-cloudflared-ssh` (ssh ProxyCommand for `pro`/`air`) now execs the
  wrapper binary. Backup: `lfg-cloudflared-ssh.bak-20260910`.
- LaunchAgents `dev.omg.lfg-air-cloudflared` (Air) and `dev.omg.lfg-cloudflared` (Pro) now
  run the wrapper binary. Backups: `*.plist.bak-20260910-wrap`. Reload = bootout → poll
  until gone → bootstrap (kickstart does NOT re-read the plist).
- Not repointed (still inside the VPN): the Pro's `com.eugene.openclaw-cloudflared` and
  `com.eugene.treehole-gbrain-cloudflared`. Same edit if wanted.

## Eugene's step (needs the Surfshark UI, both Macs)
Surfshark → Settings → VPN settings → Bypasser → **Add app** → *Open finder* →
`~/Applications/Cloudflared.app` → Add → approve the system extension if asked → **reconnect**.

## Verify after
```
# local address of the tunnel daemon's edge sockets: 192.168.x.x = bypassed, 10.14.0.2 = still in VPN
for p in $(pgrep -f "Cloudflared.app/Contents/MacOS/cloudflared tunnel"); do lsof -a -p $p -i -nP | grep ESTABLISHED; done
ping -c 6 ssh-pro.eugenechantk.me          # expect tens of ms, not 400+
grep -c "Registered tunnel connection" ~/.cloudflared/lfg-air.err.log   # should stop climbing
LFG_MOSH_NO_LAN=1 mosh-bridged pro         # remote-path feel; keystroke echo via remote `tr`
```
Baseline before Bypasser (09-10 18:00): both daemons bound to 10.14.0.2; edge RTT ~410 ms.

## Fallback if Bypasser rejects an ad-hoc-signed app
Website mode: add `ssh-pro.eugenechantk.me`, `ssh-air.eugenechantk.me`,
`region1.v2.argotunnel.com`, `region2.v2.argotunnel.com`. Or turn Surfshark off on the Pro
(it is a desk machine) — `scutil --nc stop "Surfshark. WireGuard®"`.

## Result (2026-09-10 18:05–18:10, after Eugene added Cloudflared.app in Bypasser on both Macs)
Daemons restarted (bootout/bootstrap) so they open fresh flows. `netstat -anv -p tcp | grep 7844`:
Air edge connections now from `192.168.0.14`, Pro from `192.168.0.183` — the app-side
`10.14.0.2 … CLOSED` rows are the intercepted stubs Surfshark's proxy leaves; `lsof -i` on the
daemon therefore looks wrong, use `netstat`. Both tunnels registered all 4 connections.

| Measure | Before (same day) | After |
|---|---|---|
| `ssh pro` full handshake from the Air | 8.8–10.0 s | 1.28–1.62 s |
| `ssh air` full handshake from the Pro | ~11 s (mosh start gap) | 1.09–1.43 s |
| `LFG_MOSH_NO_LAN=1 mosh-bridged pro -- true` | 22–34 s | 6.3 s |
| Ping to edge (not bypassed — ICMP from `ping` still rides the VPN) | 350–450 ms | unchanged, not a valid probe any more |

Flap baseline for tomorrow: "Registered tunnel connection" count today at 18:10 — Air 353,
Pro 208. If those barely move overnight the flapping is gone.

## Keystroke echo (true round trip, remote `tr a-z A-Z`, 20 samples each, 18:20)
Harness: `echo_rtt.py` (pty; sends letter+CR, waits for the uppercase — mosh prediction cannot
satisfy it). Same method as 2026-09-05.

| Path | 2026-09-05 median | now median | now p90 |
|---|---|---|---|
| mosh via Cloudflare | 364 ms (233–494) | **64 ms** (50–247) | 77 ms |
| ssh via Cloudflare (raw) | — | 60 ms | 106 ms |
| mosh via LAN | 41–51 ms | 53 ms | 119 ms |
| ssh via LAN (raw) | — | 19 ms | 29 ms |

The remote path is now within ~10 ms of the LAN path at the median. Remaining LAN jitter is
Wi-Fi power-save (p90 119 ms), as noted on 09-05.
