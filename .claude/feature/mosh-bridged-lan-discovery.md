# mosh-bridged: LAN peer discovery (2026-09-10)

## Problem
The LAN fast path pins DHCP addresses per peer. The router (Three HK ZTE MC888) offers no
MAC→IP binding, and its 24h lease moves whenever a Mac spends a day away. A stale pin fails
the 1s probe and every session silently rides Cloudflare instead (9x slower keystroke echo,
measured 2026-09-10: 0.2s vs 9–10s per ssh handshake).

## Design
Candidates in order: last discovered address (cache) → pinned list → subnet sweep.
The sweep runs only when all candidates failed, only on a /24 behind a non-VPN default
route, at most once per 120s. It probes TCP/22 on every host in parallel (~1–2s), then
`ssh-keyscan`s the responders and accepts only the host presenting the peer's pinned
ed25519 key (`direct_hostkeys`). A match is written into known_hosts (replacing any stale
entry for that address) so `StrictHostKeyChecking=yes` stays on, cached under
`~/.cache/mosh-bridged/<peer>.lan`, and prepended to the carrier cascade.

Not covered: a lease change mid-session while at home (the carrier cascade is a fixed
`/bin/sh -c` string). Next session start re-discovers.

## Success criteria
| # | Criterion | Test |
|---|-----------|------|
| 1 | Stale pins, peer on LAN → session uses discovered address, rc=0, log "LAN discovered" | test copy with bogus pins, sized pty, `-- /bin/true` |
| 2 | Second run hits the cache: no sweep, LAN path, faster start | rerun, log shows no "discovered", cache file present |
| 3 | A LAN host with sshd but the wrong key is never selected | test copy with wrong hostkey → "found no host", tunnel fallback |
| 4 | `LFG_MOSH_NO_LAN=1` skips probe and sweep | env set → no LAN log lines |
| 5 | Sweep rate-limited to once per 120s | fresh stamp + bogus pins → no sweep |
| 6 | Real `pro` from the Air and real `air` from the Pro still take the LAN path | live runs, rc=0 |

## Evidence
(filled in below after verification)

## Evidence (2026-09-10, Air 192.168.0.14 → Pro 192.168.0.242, both on Surfshark)
Test copies: `mb-A` = pins replaced by a bogus 192.168.0.250; `mb-B` = mb-A plus the Air's key
in place of the Pro's. Runs under a pty with `-- /bin/true`; log lines from
`~/Library/Logs/mosh-bridge.log`.

| # | Result | Log / observation |
|---|--------|-------------------|
| 1 | PASS rc=0, 8.2s total | `LAN discovered eugenechan@192.168.0.242 by sweep of 192.168.0.0/24 (host key matched)` → `LAN fast path via …242`; cache file written |
| 2 | PASS rc=0, 4.4s | no sweep line; `LAN fast path via …242` straight from cache |
| 3 | PASS rc=0 via tunnel | `sweep of 192.168.0.0/24 found no host with pro's key`; no cache entry; another LAN host with sshd (192.168.0.43) correctly rejected |
| 4 | PASS rc=0 via tunnel | no LAN lines, no cache dir created |
| 5 | PASS rc=0 via tunnel | fresh `pro.sweep` stamp → no sweep line; first attempt hit a Cloudflare tunnel flap (bootstrap failed, rc=1), rerun clean |
| 6 | PASS | Air→Pro `pro -- /bin/true` rc=0 4.5s via LAN; Pro→Air `air -- /bin/true` rc=0 7s via `LAN fast path via …14` |

Standalone sweep cost: 1.4–1.6s for the /24 (2 responders, 1 keyscan each).
Bugs found and fixed during verification: zsh `local a="$1" b="${m[$a]}"` expands `$a` before
assignment (function died under `set -u`); `ssh-keyscan` prints its `# host` banner on stdout.
Not verified: a lease change mid-session (documented limitation).
