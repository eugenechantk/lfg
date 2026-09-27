# Desktop: "Can't open session" resuming an Air codex session on the Pro — 2026-09-27

## Symptom
Clicking an Air codex session (`01a0e2ae…`, ai-weather-girl) in the Pro's desktop app:
"iTerm2 closed the new window as soon as it opened", command
`/opt/homebrew/bin/tmux new-session -A -s lfgd-01a0e2ae … '/opt/homebrew/bin/codex' … resume …`.

## Two bugs, stacked

1. **Wrong codex path.** `Opener.resolve` ran `zsh -lc 'command -v codex'`. A Finder-launched app
   has `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin`; a non-interactive login shell never reads
   `~/.zshrc`, which is where both Homebrew and `~/.bun/bin` get added. In the app's env it found
   none of tmux/claude/codex/mosh. tmux and claude worked only because their hardcoded
   `/opt/homebrew/bin` fallbacks happen to exist; codex's doesn't (Homebrew copy removed 2026-09-06,
   one codex per Mac = `~/.bun/bin/codex`). tmux then exits 0 when its pane dies, so `holdOnFailure`
   didn't hold and the window vanished.

2. **The session wasn't closed — it was live on the Air** (codex pid 56655, tmux `lfg-b35207`).
   The row the user clicked was a phantom:
   - The Pro's server hides a synced transcript only while its lease is fresh (<90s). The Air's
     lease reaches the Pro via Syncthing late; observed ages on the Pro 70s → 95s → 124s, and at
     ≥90s the Pro lists the session as closed.
   - The desktop drops that phantom only when the Air answers the same refresh. With the Air's
     tunnel serving `/api/sessions` in 0.5–5.7s (15 samples) and a **4s** request timeout, ~1 refresh
     in 4 lost the Air entirely (`hostsReachable` 2→1, live 40→15 in `--hidden-dirs-probe`).
   - Fixing only bug 1 would have made the click *start a second codex on a live thread* — two
     writers, Syncthing conflicts (a `.sync-conflict-20260927-230118` copy of this rollout already exists).

## Fix (desktop/LFGSessions.swift)
- `Opener.pickExecutable`: preferred dirs → login shell (absolute paths only) → known install dirs
  (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.bun/bin`). codex prefers `~/.bun/bin`.
  `resumeLocally` refuses a missing binary with a sentence instead of a vanishing window.
- **Boundary guard in `Opener.open`** before any resume: `resumeCheck` asks every configured host
  now (10s timeout, parallel). Live in tmux anywhere → attach there. Live without a pane → refuse,
  naming the host. A host that didn't answer → the synced lease decides: foreign, not ended,
  heartbeat < 15 min → refuse. A host that answered "not live" outranks its lease.
- Host fetch timeout 4s → 10s so the list stops dropping the Air.
- Probe: `lfg --resume-check <sessionId>` prints the decision and resolved binaries.

## Evidence
- `--desktop-feature-test`: ok, 144 assertions (binary resolution + 6 resume-decision cases).
- Installed app, Finder-like env, `--resume-check 01a0e2ae-…` →
  `attach {host: Air, tmux: lfg-b35207, ssh: air, transport: mosh-bridged}`, codex `~/.bun/bin/codex`.
- A genuinely closed codex session → `resume`.
- Not verified by me: the actual iTerm window from a click (Eugene was using the machine).

## Follow-ups (not done)
- Air tunnel latency (0.5–5.7s for 77KB) looks like the Pro's pre-edge-bind VPN problem — apply
  `scripts/cloudflared-edge-bind-run.sh` on the Air.
- Server side: a 90s lease window can't survive Syncthing lag, so each host keeps listing the other's
  live sessions as closed. Clients paper over it; the desktop now guards at open time.
- tmux exits 0 when its pane command dies, so `holdOnFailure` can't catch a dying resume; a
  `remain-on-exit` on the `lfgd-*` session would show the real error.

## Round 2 — "still can't open the Air session" (the real blocker)

The live Air row ("Street crossing video prompt", `lfg-b35207`, Air · mosh) takes the
remote-attach path, not resume. `~/Library/Logs/mosh-bridge.log` showed every desktop open since at
least 09-26 as `mosh-client start` → `EXIT rc=0` in the same second: the remote command ended at once.

- The bare attach command worked (scratch tmux pane; `script -q` inside iTerm).
- The app's exact held one-liner, launched through iTerm with argv dumped by a fake `mosh-bridged`,
  delivered `… -- /bin/sh -c PATH=/opt/homebrew/bin:…` — cut at the first space. iTerm 3.7.0's
  `command` tokenizer is not a shell and does not honour `\"` inside a double-quoted word, and
  `holdOnFailure` (09-16, `ca6760b`) nested the remote command's quotes one level deeper. The Air ran
  `sh -c 'PATH=…'`, exited 0, mosh ended cleanly, `s=0` → no hold → the window vanished silently.
  Broken for **every** remote attach from the desktop since 09-16; the test was string-only.

Fix: `Opener.windowLaunch` writes `holdOnFailure(command)` to `$TMPDIR/lfg-window-<uuid>.sh` (self-deleting)
and iTerm runs `/bin/sh '<path>'`. Commands are plain POSIX sh now (`shq` the remote command instead of
iTerm-style double quotes). Tests execute the script with fake `mosh-bridged` / `ssh` / `tmux` recording
argv (147 assertions). Live: `lfg --attach-command air lfg-b35207 mosh-bridged open` (the production
launcher) attached within 1s at 80x64; screenshot showed the Air codex session. Installed to /Applications.

Side finding: `tell application id "com.eugenechan.lfg-desktop" to activate` launched a stale copy at
`.codex/evidence/claude-codex-handoff/lfg.app` (LaunchServices had it registered). Launch by path.
