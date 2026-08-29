# mosh over Cloudflare ssh renders the wrong colours — 2026-08-29

## Symptom

Sessions reached with `pro` / `prot` (i.e. `mosh-bridged` over Cloudflare Access ssh) show a
different colour scheme from the same tmux session viewed locally, and some colours are missing
entirely — notably the light-grey background behind Claude Code's user messages.

## Root cause

`scripts/mosh-bridged` never passed mosh-server's `-c COLORS` flag.

mosh has no in-band colour negotiation. `mosh-server` decides the remote `TERM` **solely** from
that flag:

| `-c` value | remote TERM       |
| ---------- | ----------------- |
| 256        | `xterm-256color`  |
| anything else / absent | `xterm` (8 colours) |

The stock `mosh` wrapper supplies it by asking the local client to count colours
(`mosh-client -c` → `256` here) and passing `-c 256` on the bootstrap command line
(`/opt/homebrew/bin/mosh` line 314/379). `mosh-bridged` reimplements that bootstrap and omitted it,
so every bridged session's shell got `TERM=xterm`.

That one variable cascades. Pro's tmux config carries `terminal-overrides[1] *256col*:Tc` — tmux
enables 24-bit output only for clients whose TERM matches `*256col*`. With `TERM=xterm` the
attaching client missed the glob, so tmux flattened every pane's 24-bit output down to the 8 ANSI
colours: the theme shifts, and subtle RGB backgrounds (the grey user-message block) have no
8-colour equivalent, so they vanish.

Nothing was wrong on the pane side — panes already inherit `COLORTERM=truecolor` from the tmux
server's global environment, so Claude Code was emitting correct 24-bit SGR the whole time.

## Fix

`scripts/mosh-bridged`: count the local terminal's colours with `mosh-client -c` and pass
`-c $colors` on the bootstrap, exactly as upstream `mosh` does. Non-numeric or missing output
(e.g. `TERM` unset → rc=1; `TERM=dumb` → `-1`) falls back to `8`.

`-l` is not an alternative route. Its `NAME=VALUE` pairs are documented as locale-related and
mosh-server **silently drops everything else** — verified: a bootstrap carrying
`-l COLORTERM=truecolor` (confirmed present in the `zsh -x` trace) produced a session whose
`printenv` had no `COLORTERM`, and even `-l LC_ALL=…` was normalised away.

## Evidence

Probe: `mosh-bridged pro -- /bin/sh -c 'printenv > ~/probe.txt; sleep 2'`, run under `script` for a
pty, then read back over ssh.

| run | remote `TERM` |
| --- | --- |
| pre-fix script (`mosh-bridged.bak`) | `xterm` |
| fixed script | `xterm-256color` |

Corroborating: every currently-live mosh session on Pro (started before the fix) shows `TERM=xterm`
in `ps eww` of its session shell. And with the fixed client attached, tmux reports the client's
feature set as `256,…,RGB,…` — 24-bit enabled end to end (mosh 1.4.0's own emulator emits
`;48;2;%d;%d;%d`, so the RGB survives the last hop to iTerm).

## Applying it

Detach and reconnect (`prot` / `pro`, or reopen from the desktop app). The tmux client's TERM is
what governs output depth, so a fresh attach is enough — the Claude Code processes in the panes do
not need restarting.
