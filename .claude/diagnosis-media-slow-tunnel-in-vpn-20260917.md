# Diagnosis: images and videos barely load on the phone — 2026-09-17

## Symptom
Images and videos referenced in transcripts take tens of seconds to minutes, or never finish.

## Ground truth (all measured 2026-09-16 16:25–16:45 UTC from the Pro)

| Probe | Result |
|---|---|
| `GET /api/file` 50 MB range, `127.0.0.1:8766` | 0.017 s (disk speed) |
| Same file through `https://lfg-pro.eugenechantk.me` (Access service token) | **44–91 KB/s**, 20 MB request died at 10.9 MB when the tunnel connection dropped |
| Raw upload, default route (Surfshark utun4) → speed.cloudflare.com | 1.04 MB/s |
| Raw upload bound to `en0` (bypasses VPN) | 4.17 MB/s |
| Raw download via VPN / via `en0` | 1.55 MB/s / 11.25 MB/s |
| RTT to Cloudflare tunnel edge (198.41.200.43) via VPN / via `en0` | **420 ms / 25 ms** |
| RTT to 1.1.1.1 and to `lfg-pro.eugenechantk.me` via VPN | 412 ms / 413 ms |
| VPN exit / direct exit (`cdn-cgi/trace`) | SG (151.240.33.15) / HK (124.217.188.60) |
| `Registered tunnel connection` in `lfg-pro.err.log` today | **207** re-registrations |
| `cloudflared` edge sockets (`netstat -anv -p tcp \| grep 7844`) | all from `10.14.0.2` = inside the VPN |

What the agents actually emit: recent sim recordings are 200–440 MB `.mov`/`.mp4`; PNG screenshots
p50 94 KB, p90 418 KB, max 9.3 MB (n=6086, last 14 days under `~/dev`).

At 50–90 KB/s: a p90 screenshot = 5–8 s, the 9 MB one ≈ 2–3 min, a 235 MB video ≈ 45 min — and
the client downloads a video **completely** before it will play it (`FileViewerSheet.load`).

## Root cause
The Pro's `cloudflared` daemon is running **inside Surfshark again**, and the Surfshark path adds
~400 ms RTT to everything (HK → SG exit, yet 410 ms; a healthy HK→SG hop is ~35 ms). cloudflared's
http2 transport is RTT-bound (per-stream flow-control window ÷ RTT), so 400 ms RTT caps a stream
at well under 100 KB/s, and the same path flaps the TCP connection every few minutes.

This is a **regression of the 09-10 fix** (`.claude/feature/cloudflared-surfshark-bypass.md`):
Bypasser + `~/Applications/Cloudflared.app` took the edge RTT from ~410 ms to tens of ms and the
keystroke echo from 364 ms to 64 ms. What happened since, from
`.claude/diagnosis-desktop-open-bounds-of-missing-value-20260916.md` and the Surfshark prefs:

1. This morning the bypassed app was black-holed on the Pro — Surfshark's Kill Switch firewall
   (`[KS] enabling firewall for connected server` in its log, pref says off) drops bypassed
   traffic. The Air, without `[KS]` lines, still works.
2. The 13:21 interim: LaunchAgent `dev.omg.lfg-cloudflared` → `/opt/homebrew/bin/cloudflared`
   (backup `dev.omg.lfg-cloudflared.plist.bak-20260916-bypass`), i.e. back through the VPN.
3. Now: `vpn_isBypasserOn = false` in Surfshark's prefs, the Bypasser entry for
   `Cloudflared.app` (`dev.omg.cloudflared`) is still there, kill switch pref off, connected to
   the SG cluster since 2026-09-14T13:37Z.

So the phone's transport is exactly the pre-09-10 state, and media is where it hurts most.

## Two independent fixes

### A. Transport (the 10–50× lever) — needs the Surfshark UI, i.e. Eugene
1. Surfshark → Settings → VPN settings → **Kill Switch off** (and confirm the log stops printing
   `[KS] enabling firewall` on the next connect).
2. Bypasser **on**, entry `~/Applications/Cloudflared.app` present.
3. Reconnect (or pick a Hong Kong server — 410 ms to a Singapore exit is not normal either).
4. Restore the agent to the bundle and restart it — `scripts/cloudflared-restore-bypass.sh`
   does it and refuses to proceed if the bundle path still carries no packets.
5. Verify: `netstat -anv -p tcp | grep 7844` shows `192.168.0.x` sources; a 3 MB range through
   Access runs at MB/s, not KB/s; the `Registered tunnel connection` count stops climbing.

If Bypasser keeps black-holing on the Pro, the doc's fallback stands: the Pro is a desk machine —
turn Surfshark off there, or use website-mode bypass for `region1/2.v2.argotunnel.com`.

### B. Client/server (helps at any RTT) — implemented in `.claude/feature/media-fast-path.md`
- **Downscaled images**: `GET /api/file?path=…&w=1200` returns a cached JPEG rendition via
  `sips` (9.3 MB PNG → 228 KB in 88 ms; p90 PNG → 73 KB). Inline transcript images use 1200,
  the full-screen viewer 2400.
- **Streaming video**: the viewer no longer downloads the whole file first. An
  `AVAssetResourceLoader` delegate forwards AVPlayer's byte-range requests through the
  authenticated transport (Access refuses the `CF_Authorization` cookie alone — verified 403 —
  so headers must be injected per request). Playback starts after the first few hundred KB.
- **Caching**: rendition responses carry `ETag` + `max-age=86400`; the app's `URLCache` is
  sized so scrolling back to an image doesn't refetch it.

## Status at hand-off (2026-09-17 01:30 HKT)
- Fix B is implemented, tested and **deployed on the Pro** (server restarted 01:02; app build on the
  iPhone 17 Pro sim; not yet on TestFlight). Evidence: `.claude/feature/media-fast-path.md`.
- Fix A is waiting on the Surfshark UI. `scripts/cloudflared-restore-bypass.sh --dry-run` currently
  refuses with `bundle still exits via 151.240.33.15 (the VPN)` — the correct answer while
  Bypasser is off. Once Bypasser is on and the VPN reconnected, run it without `--dry-run`.
- Live check after A: `Registered tunnel connection` count in `~/.cloudflared/lfg-pro.err.log`
  (207 today by 16:27 UTC) should stop climbing, and a range curl through Access from the Air
  should run at MB/s.

## Verify-innocent checks run
- Bun server is not the bottleneck: loopback 50 MB in 17 ms.
- Not Access: TTFB through Access is 2.6 s (RTT-bound), throughput is what fails.
- Not the phone's downlink: irrelevant while the Mac's side is at 90 KB/s.
- Not Cloudflare edge distance: `en0` reaches the same edge in 25 ms.

## Resolution 2026-09-18 00:22 HKT — Fix A done without Surfshark, via `--edge-bind-address`

Eugene reported "cloudflared is bypassed already"; probing showed that was the **Air** (bundle binary,
sockets from `192.168.0.76`). The Pro was still `/opt/homebrew/bin/cloudflared` via `utun4`:
`vpn_isBypasserOn = false`, `[KS] enabling firewall` on every connect, 360 ms edge RTT vs 29 ms on
`en0`, 2660 `Registered tunnel connection` lines that day.

**Measured cap is per tunnel, not per stream**: one 2 MB range through Access ran at 37 KB/s; four in
parallel totalled 45 KB/s. So no client-side trick (parallel ranges, buffering) could have helped —
the sim recordings need 330–610 KB/s (1290×2796 @ 30 fps, 2.6–4.9 Mbps, `moov` at the end).

Fix: cloudflared has `--edge-bind-address` (`$TUNNEL_EDGE_BIND_ADDRESS`, cloudflared ≥ 2023.x), and
macOS scopes a socket's route to the interface owning its bound source address, so binding to the
Wi-Fi IP leaves via `en0` regardless of the VPN's default route — **no root, no Surfshark Bypasser,
and the kill-switch firewall does not touch it** (`curl --interface 192.168.0.182` already exited via
HK while Bypasser was black-holed). Canary: a second replica bound to `192.168.0.182` registered 4
edge connections in 25 s.

Wired as `~/.cloudflared/lfg-pro-run.sh` (repo copy `scripts/cloudflared-edge-bind-run.sh`): resolves
`ipconfig getifaddr en0` at launch, runs unbound if Wi-Fi has no address, and exits (launchd
`KeepAlive` respawns) if the address changes. LaunchAgent `dev.omg.lfg-cloudflared` now runs the
wrapper; previous plist at `dev.omg.lfg-cloudflared.plist.bak-20260918-edgebind`.

| Probe | Before | After |
|---|---|---|
| Edge socket source | `10.14.0.2` (utun4) | `192.168.0.182` (en0) |
| 2 MB range through Access, 1 stream | 37 KB/s | 548 KB/s (TTFB 0.5 s) |
| 4 × 2 MB parallel, aggregate | 45 KB/s | 2.0 MB/s |
| 20 MB range, 1 stream | (timed out at 10.9 MB on 09-16) | **3.7 MB/s**, 5.2 s |

A 197 MB / 631 s recording at 2.6 Mbps needs 0.33 MB/s; the tunnel now delivers 10× that, so the
streaming loader in TestFlight 202609171036 plays it in real time. Video renditions (server-side
transcode) are **deferred**: at these rates the originals play, and a rendition would only matter on
a slow cellular leg. Revisit if the phone still stalls on LTE.

Outage during the switch: ~40 s. `launchctl bootstrap` returned `5: Input/output error` right after
`bootout`; an immediate retry succeeded. `scripts/cloudflared-restore-bypass.sh` (the Bypasser-based
route) is superseded on the Pro; the Air keeps its bundle-based bypass.
