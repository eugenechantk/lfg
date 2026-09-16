# Diagnosis — `air` alias "stopped working" (2026-09-08)

## Symptom
`air` (= `mosh-bridged air`) failed from the Pro around 21:07 HKT. Plain `ssh air`
worked when probed a few minutes later. Pro was on an iPhone hotspot (172.20.10.x),
so the LAN fast path was unavailable and everything went through Cloudflare Access.

## What was actually wrong
**Both `cloudflared tunnel` daemons were on QUIC, and QUIC over the Surfshark
WireGuard `utun` was flapping every ~60s.** Tunnel logs on both hosts:

| host | quic-timeout errors/day | tunnel re-registrations/day |
|------|-------------------------|-----------------------------|
| Pro 09-06 | 75 | 29 |
| Pro 09-07 | 1378 | 498 |
| Pro 09-08 (to 13:17Z) | 1232 | 489 |
| Air 09-07 | 813 | 228 |
| Air 09-08 (to 13:18Z) | 1511 | 501 |

Error text: `failed to dial to edge with quic: timeout: no recent network activity`,
`failed to accept QUIC stream: timeout`, and on the Pro also
`sendmsg: no route to host` toward the edge on UDP/7844. TCP/7844 and TCP/443 to the
same edge IPs succeeded from both hosts. So: UDP through the VPN was broken/lossy,
TCP was fine.

Every ssh-through-Access connection rides a tunnel connection; each flap killed the
mosh-bridged carrier (`carrier exited 255; respawn`) and made the bootstrap /
`Connection closed by UNKNOWN port 65535`. A plain `ssh air` in a 60s good window
looks fine — that's why the quick probe passed.

## Fix
`protocol: http2` in `~/.cloudflared/lfg-pro.yml` and `~/.cloudflared/lfg-air.yml`
(backups `*.bak-20260908-quic`), then `launchctl kickstart -k gui/501/<label>`.
Air restart done with a 3-min dead-man revert (`.http2-commit` touch) so a bad
config could not strand the host.

## Result
- Pro: 489 re-registrations in 13h before → 16 in the following 3h. Remaining ERRs
  are `network is unreachable` bursts (hotspot ↔ LAN moves) and client-cancelled
  HTTP requests.
- Air: still ~40 re-registrations/hr for the first 3h on http2 (`connection with
  edge closed`, `client disconnected`), then silent from 16:00Z. Not fully
  explained — watch it. If it recurs, next suspects: Surfshark on the Air, and
  `cloudflared` 2026.6.1 on Air vs 2026.3.0 on Pro.
- `ssh pro` from the Pro itself gets `Permission denied (publickey)` — the Pro's
  own key isn't in its own authorized_keys. Harmless; not touched.
- Verification: `LFG_MOSH_NO_LAN=1 mosh-bridged air` held 100s with no carrier
  respawn; Air → `ssh pro` works.

## Cleanup done
Two dead `mosh-bridged pro` sessions on the Air (from 09-05) whose carriers had
been respawning every few seconds against the Pro tunnel for 3 days were killed.

## Lessons
- **A tunnel that "works" on a one-shot probe can still be flapping once a minute.**
  Count `Registered tunnel connection` per day in `~/.cloudflared/lfg-*.err.log`
  before declaring the tunnel healthy; >20/day is a flap.
- The Pro's own `air` verification must use `LFG_MOSH_NO_LAN=1` — at home the LAN
  fast path silently bypasses the tunnel under test.
- Local `air` binary in `~/.local/bin` (the port forwarder) shadows the alias in
  any non-interactive shell (`zsh -c`, scripts). Only interactive shells get the
  mosh alias. Not the cause here, but it bit the first repro attempt.
