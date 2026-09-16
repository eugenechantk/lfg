# Diagnosis — desktop "Open" fails with `Can't get bounds of missing value` (2026-09-16)

## Symptom

Opening a session from the desktop app shows an alert:

```
iTerm2 scripting failed: 379:385: execution error: Can't get bounds of missing value. (-1728)
```

No iTerm window appears.

## Mechanism (confirmed by repro)

`Opener.runInNewITermWindow` asks iTerm for
`create window with default profile command "<attach command>"` and then reads
`bounds of w`. iTerm's default profile has *Close Sessions On End* = true, so if
the command exits immediately, the session and window are gone before the script
continues and `create window` hands back `missing value`. Character offset
379:385 in the error is exactly `bounds of w`.

Reproduced on demand:

```applescript
tell application "iTerm"
  set w to (create window with default profile command "/opt/homebrew/bin/tmux attach -t no-such-session-xyz")
  set b to bounds of w   -- → Can't get bounds of missing value. (-1728)
end tell
```

The same script with a live local session (`cy-000530-4099`) returns a window,
so the local attach path was fine.

## Root cause on the day

The Air was unreachable over the Cloudflare tunnel:

```
$ ssh -o ConnectTimeout=5 air 'tmux ls'
websocket: bad handshake
Connection closed by UNKNOWN port 65535
```

The desktop app itself showed "Unreachable: Air". Opening an Air row ran
`mosh-bridged … air …`, whose bootstrap ssh died at once → mosh-bridged `exit 1`
→ iTerm closed the window → AppleScript crashed on the vanished window. The
actual reason (bad handshake) died with the window; only the AppleScript noise
survived.

Any stale local `tmuxName` produces the same symptom (`can't find session`).

## Fix (`desktop/LFGSessions.swift`)

1. **`Opener.holdOnFailure`** wraps every window command:

   ```sh
   /bin/sh -c "<command>; s=$?; if [ $s -ne 0 ]; then
       stty sane </dev/tty 2>/dev/null; tput rmcup 2>/dev/null;
       printf '\n[lfg] command exited with status %s. Press Return to close this window.\n' $s;
       read _ </dev/tty; fi"
   ```

   Success paths are unchanged (a clean detach exits 0 and the window closes as
   before). The quoting is already POSIX, so `';'` still reaches tmux as its own
   argument. Remote commands' inner double quotes get one more escape level for
   iTerm's tokenizer (`itermDoubleQuoted`).

2. **`stty sane` + `tput rmcup` before the wait are load-bearing.** In the first
   live run the window *still* closed: `~/Library/Logs/mosh-bridge.log` showed
   `mosh-client EXIT rc=1` at the exact second. An abnormally exiting mosh-client
   leaves the tty raw with VMIN=0 (and on the alternate screen), where `read`
   returns EOF immediately. Simulated with `stty raw min 0 time 0; printf
   '\033[?1049h'; false`: the plain hold vanished, the reset version held.

3. **`missing value` backstop** in the AppleScript: returns a marker instead of
   crashing, and the alert now reads "iTerm2 closed the new window as soon as it
   opened — the command exited immediately. Run it by hand to see why: <cmd>".

4. **`lfg --attach-command <host> <tmux> [transport] held`** prints the wrapped
   command the window is actually handed, so the window-side quoting can be
   exercised against a real iTerm via osascript without clicking a row.

5. `desktop/build.sh` now signs with `--timestamp=none`: a timestamp-server
   hiccup ("A timestamp was expected but was not found") otherwise leaves the
   app ad-hoc signed, which resets the iTerm automation TCC grant.

## Evidence

| Case | Command under wrapper | Result |
| --- | --- | --- |
| A | `ssh -o ConnectTimeout=5 air true` | window held: `websocket: bad handshake` … `[lfg] command exited with status 255` |
| C | `mosh-bridged … no-such-host-xyz.invalid` | window held: bootstrap failed … `exited with status 1` |
| D1 | simulated raw-tty crash, plain `read` | window vanished (reproduces the residual bug) |
| D2 | same, with `stty sane` + `</dev/tty` | window held |

`--desktop-feature-test`: 133 tests pass (4 new). Installed to
`/Applications/lfg.app`, signed with the Developer ID, relaunched (pid 41605).

## Still open

- **The Air is up but both lfg Cloudflare tunnels are dead at the edge** (follow-up
  the same day). The Air is awake on the LAN at `eugenechan@192.168.0.76`, its lfg
  server listens and cloudflared runs, yet `cloudflared tunnel list` shows zero
  CONNECTIONS for lfg-pro and lfg-air (treehole-gbrain on the Pro has four). A
  restarted Pro agent loops on `edge discovery: … lookup
  _v2-origintunneld._tcp.argotunnel.com … i/o timeout`: every direct DNS query
  (VPN resolvers, 1.1.1.1, `+tcp`, the LAN router) times out on BOTH Macs while
  HTTPS through the system resolver works — Surfshark is dropping raw port-53
  traffic. `--edge ip:7844` still does the SRV lookup; `GODEBUG=netdns=cgo`
  changes nothing. Needs a Surfshark-side decision (Bypasser for Cloudflared.app,
  or toggling the VPN). See memory [[cloudflare-tunnel-quic-flaps-under-vpn]].
- **Air tunnel restored 12:22 (Eugene restarted its agent; the Air's Surfshark already
  bypasses Cloudflared.app) — four edge connections, API 200 via Access. The Pro's
  tunnel is still down for the DNS reason above; that is why the phone reaches the
  Air but not the Pro.** `ssh air` from the Pro also still fails: the ProxyCommand is
  the Pro's own cloudflared client, stuck on the same blocked DNS.
- **mosh-bridged to the Air dies for an unrelated reason:** the Air's `/usr/bin/python3`
  prints the Xcode license error instead of running (`checkFirstLaunchStatus` exit 69),
  and the remote bridge half runs under it → `carrier exited 255` loop. Fix on the Air:
  `sudo xcodebuild -license accept`. See memory [[xcode-license-kills-mosh-bridge]].
- **Pro tunnel, 13:20 update: Surfshark's Bypasser on the Pro black-holes the bypassed
  app.** Bypasser is on, the entry is correct (`~/Applications/Cloudflared.app`, signing
  id `dev.omg.cloudflared`), kill switch off, TransparentProxy extension active — the
  same as the Air, where it works. But a `dig` copied *inside* the bundle times out to
  every server over UDP and TCP while `/usr/bin/dig` answers, and cloudflared's precheck
  hard-fails on DNS + API 443. Swapping in the Air's cloudflared 2026.6.1 (kept; wrapped
  via `scripts/cloudflared-app-wrap.sh`) changed nothing, and `--dns-resolver-addrs`
  can't help when the path carries no packets. The Pro's TransparentProxy (the
  component that implements Bypasser) appears wedged. Not fixable from the CLI:
  toggle Bypasser off/on (or remove the Cloudflared entry — through the VPN the
  tunnel ran for days until this morning), then restart `dev.omg.lfg-cloudflared`.
- **13:30 — root cause of the Pro black hole: Surfshark's Kill Switch firewall.** The Pro's
  Surfshark log shows `[KS] enabling firewall for connected server` on every connect (pref
  says off); the Air's log has no `[KS]` lines at all. Bypassed apps leave via en0 and the
  KS firewall drops them. Through the VPN the Pro tunnel registers but churns
  (`connection with edge closed` ~every 30s; Access 502/530), so it is not a fallback today.
  Interim: agent plist → `/opt/homebrew/bin/cloudflared` (backup `.bak-20260916-bypass`);
  ssh proxy script gained a per-host override (`~/.cloudflared/lfg-client-cloudflared` →
  Homebrew binary) and `ssh air` works again from the Pro. Pending Eugene: Kill Switch
  off on the Pro, then restore the plist to the bundle and restart the agent.
- **14:00 — RESOLVED for the phone.** After Eugene quit/relaunched Surfshark and reconnected
  (Singapore), the Pro tunnel run by the **Homebrew** cloudflared (through the VPN) stopped
  churning: 4 stable edge connections, 200s from the Air through Access, thousands of 200s
  in the tunnel's own metrics. The bypassed bundle path is STILL black-holed (Bypasser reads
  off; a dig inside the bundle times out), so the plist stays on `/opt/homebrew/bin/cloudflared`.
  What fixed what: Surfshark relaunch → churn gone; plist → Homebrew binary → tunnel not in the
  black hole; ssh proxy override → `ssh air`/`ssh pro` from the Pro. The 2026.6.1 binary swap
  and the resolver/edge flags changed nothing. Probing lfg-pro *from the Pro itself* times out
  (VPN out, tunnel back) — probe from another machine.
- A remote tmux session that no longer exists still closes the window silently:
  mosh reports `[mosh is exiting]` with status 0 after the far-side `can't find
  session`, so the hold does not trigger. Only the ssh transport surfaces it.
- `desktop/LFGSessions.swift` and `.claude/CLAUDE.md` carry other sessions'
  uncommitted work; these edits are additive and uncommitted.
