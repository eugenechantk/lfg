# Feature: Desktop — mosh-bridged transport for Cloudflare hosts

## User Story

As Eugene clicking a remote session in the lfg desktop app, I want the iTerm window
to be a **mosh** session (predictive local echo, survives roaming) even though the
host is only reachable over Cloudflare Access ssh, so typing into a Pro session from
the Air doesn't feel 120–180 ms laggy — and so the window stops closing itself.

## User Flow

1. Desktop lists sessions from `hosts.json` (Pro + Air, Cloudflare URLs, ssh aliases).
2. A remote tmux-backed row shows a `mosh` badge (not `ssh`).
3. Click → iTerm window runs `mosh-bridged --server=… --ssh=… <alias> -- /bin/sh -c "…tmux attach…"`:
   mosh-client locally, mosh-server loopback-bound remotely, datagrams carried inside `ssh <alias>`.
4. Typing is instant (local echo); a Wi-Fi drop or sleep is a blip, not a closed window.
5. Hosts that can carry real mosh UDP (LAN / Tailscale-era entries, `transport` omitted) keep
   the existing mosh-or-ssh behaviour; `"transport": "ssh"` still forces plain ssh.

## Success Criteria

- [x] SC1: `RemoteTransport` gains `.moshBridged` (`"mosh-bridged"` in hosts.json); it decodes,
      encodes, and round-trips. — **Verify by:** `--desktop-feature-test` assertions on decode/encode.
- [x] SC2: `Opener.remoteAttachCommand` for a `.moshBridged` host runs the `mosh-bridged` binary
      with the same `--server=`/`--ssh=`/`target -- /bin/sh -c …` shape as mosh. — **Verify by:**
      `--desktop-feature-test` string assertions + running the emitted command headless against the Pro
      (tmux `list-clients` on the Pro shows the new client; typed marker echoes back).
- [x] SC3: Bundled Pro/Air entries default to `.moshBridged`; an existing hosts.json entry for a
      bundled URL that still says `"transport":"ssh"` is read as `.moshBridged` (migration), while
      `"ssh"` on any other URL still forces ssh. — **Verify by:** `--desktop-feature-test`.
- [x] SC4: Row badge / host-settings detail text say `mosh` / `mosh (bridged)` for such hosts. —
      **Verify by:** `--desktop-feature-test` on `remoteTransportLabel` + detail text helper.
- [x] SC5: `mosh-bridged` missing locally → falls back to plain ssh (never a dead window). —
      **Verify by:** `--desktop-feature-test` with `availableMoshBridgedPath: nil`.
- [~] SC6: "Window opens then closes itself" — root cause identified with evidence, and the
      shipped transport verifiably does not exhibit it. — **Verify by:** headless repro log of the
      old command (`.claude/et-over-cloudflare/close-repro.log`) + a ≥5 min soak of the new command.
- [x] SC7: Build clean (`desktop/build.sh`), `--desktop-feature-test` green, app relaunched on
      the Air with the new build. — **Verify by:** command output.

## Platform & Stack

- **Platform:** macOS desktop (`desktop/LFGSessions.swift`, swiftc via `build.sh`, headless test hooks)
- **Language:** Swift (+ zsh/Python for `scripts/mosh-bridged`, `scripts/mosh-bridge`)
- **Transport binaries:** `~/.local/bin/mosh-bridged` → `scripts/mosh-bridged` (both Macs, Syncthing)

## Steps to Verify

1. `cd desktop && ./build.sh && build/lfg.app/Contents/MacOS/lfg --desktop-feature-test`
2. `build/lfg.app/Contents/MacOS/lfg --remote-attach-command pro lfg-xyz` (existing hook, line ~4438)
   → run the printed command under expect against a throwaway tmux session on the Pro.
3. Relaunch the app; click a Pro row; confirm iTerm title `[mosh] …` and `tmux list-clients` on the Pro.

## Implementation Phases

### Phase 1: transport enum + opener + tests
- Scope: `RemoteTransport.moshBridged`, `Opener.moshBridged` resolution, `transportCommand(for:)`,
  `remoteAttachCommand` variants, badge/detail text, bundled defaults + load-time migration, tests.
- SC: 1–5, 7
### Phase 2: root-cause the self-closing window; soak the new transport
- SC: 6

## Decision Log

- **Bridged mosh is a new enum case, not a change to `.ssh`.** `.ssh` keeps meaning "plain ssh" so a
  user can still force it; `.automatic` keeps meaning real mosh-or-ssh for hosts with a UDP path.
- **Load-time migration for bundled URLs only.** The existing hosts.json on both Macs says
  `"transport":"ssh"` for the Cloudflare entries — a value only `bundledHosts` ever wrote. Reading it
  as `.moshBridged` for those two URLs is the intent; the file is not rewritten ("existing host files
  are never silently rewritten"). Any other URL with `"ssh"` is untouched.
- **`mosh-bridged` CLI mirrors mosh's flags** so `remoteAttachCommand` stays one function with one
  shape; the binary is resolved via the login shell like `mosh` is.
- **Scripts live in `lfg/scripts/`** (synced to both Macs by Syncthing) with `~/.local/bin` symlinks,
  not in `~/.local/bin` alone — the desktop app depends on them, so they version with it.

## Verification Evidence

| SC | Method | Result | Artifact |
|----|--------|--------|----------|
| SC1 | `--desktop-feature-test` decode/encode/round-trip of `.moshBridged` | PASS | 117/117 assertions `{"ok":true,"tests":117}` |
| SC2 | test string assertions + emitted command run headless vs Pro | PASS | attach cmd = mosh cmd with `mosh-bridged` binary; T1/T2 markers echoed back over a real Pro attach |
| SC3 | `--desktop-feature-test` migration cases | PASS | bundled URL `"ssh"`→`.moshBridged`; other URL `"ssh"` stays `.ssh`; bundled default `.moshBridged` |
| SC4 | `--desktop-feature-test` on `remoteTransportLabel` + `transportDetail` | PASS | badge `mosh`/`ssh`-fallback; detail "mosh (bridged over ssh)" |
| SC5 | `transportPath(... availableMoshBridgedPath: nil)` | PASS | falls back to ssh, never raw mosh UDP |
| SC6 | headless repro of old vs new command + 30-min soaks + live use | PARTIAL (mechanism identified; mosh-bridged immune + in live use; spontaneous close not force-reproduced) | `.claude/et-over-cloudflare/{close-repro,blip-*,soak30-*}.log` |
| SC7 | `build.sh` + `--desktop-feature-test` + relaunch | PASS | clean build, Developer-ID signed (same identity → iTerm TCC grant preserved), installed to /Applications, running pid confirmed |

### SC6 — the self-closing window

**Could not force a spontaneous close in headless testing.** Ran the exact command the
old desktop emitted (`ssh -t … tmux attach`) under four conditions:
- idle attach, 420 s — stayed attached.
- Wi-Fi off 20–25 s mid-session — survived (ssh keepalive `ServerAliveInterval 20`
  × `ServerAliveCountMax 6` = 120 s tolerance rides a short blip).
- Surfshark stop/start (full path + IP change) 30 s — survived on *both* the old ssh
  command and the new mosh-bridged command.
- 30-min idle soak, attempt 1 — the ssh window exited at 117 s, but with **exit
  status 0** (`rtype exit-status reply 0`): a *self-inflicted* clean close — a
  cleanup step killed the tmux session server-side while the soak was attached,
  which makes the tmux client exit normally. NOT a network close.
- 30-min idle soak, attempt 2 (untouched session `soakbox`) — **still attached at
  1800 s**, no close. So a spontaneous close does not occur on an idle home
  network in a 30-min window; it needs the longer-stall / hard-reset conditions
  above (real roaming, sleep, edge reconnect) which did not arise here.

**Real-world use:** during verification, two of Eugene's own sessions
(`cy-112025-52233`, `lfg-b5eb89`) were attached over `mosh-bridged` on the Pro —
the shipped transport is in live use, not just tested.

**Mechanism (high confidence) even without a forced repro:** the old attach is a single
long-lived TCP stream over the Cloudflare tunnel. When that stream is stalled longer than
ssh's keepalive budget, or reset outright (tunnel edge reconnect, Access token refresh, a
long sleep), ssh exits and iTerm closes the window — matching "opens, then closes itself
after a while". The Pro's `sshd-session` USER/DEAD log confirms sessions do end at varied
lifetimes with no clean client-initiated detach.

**Why the shipped transport fixes it regardless:** `mosh-bridged` makes the ssh stream a
*disposable carrier* — `mosh-bridge` respawns it with backoff on exit (observed:
`carrier exited 255; respawn in 4s` during the Wi-Fi drop), and mosh-server holds the
session and replays the gap, so the iTerm window sees an uninterrupted mosh session across
a carrier death. The failure mode that closes the ssh window cannot close a mosh-bridged
window; it can only cost a few seconds of reconnect.

## Bugs

- Reported 2026-08-23: clicking a remote host session opens an iTerm window that closes itself
  after a while. Investigation in Phase 2.
