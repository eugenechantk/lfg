# Codex sessions look colour-shifted over ssh into another host — 2026-09-05

> **Round 2, same day:** the dim fix below was necessary but not the whole story. The
> missing **grey composer background** was a second, independent mechanism: codex probes
> the terminal's default colours (OSC 10/11, 100ms deadline) at startup and paints its
> input-field fill only when answered; mosh swallows those queries, so any codex *spawned*
> during a mosh-bridged session latched the no-fill fallback for its lifetime (locally
> spawned sessions painted `48;2;49;52;57`). Fixed by teaching the patched mosh emulator to
> answer OSC 10/11 from `MOSH_OSC_FG`/`MOSH_OSC_BG`, with `mosh-bridged` reading the real
> values from the local terminal at connect time. Full-chain verify: codex spawned through
> the bridge now paints `48;2;57;60;64` (derived from the supplied bg — proof the answer is
> consumed). Deployed both hosts. Details in `.claude/tools/mosh-faint/README.md`.
> Note: existing codex sessions keep their latched style; sessions started after a
> reconnect get the fill.

## Symptom

Codex (`codexy`) sessions viewed over the bridged connection to another host (`pro` / `prot` /
`air` / `airt`, i.e. `mosh-bridged` over Cloudflare ssh) show a colour difference compared to the
same UI viewed locally. Claude sessions look comparatively normal.

## What was ruled out (all verified live, 2026-09-05)

| Layer | State | Evidence |
| --- | --- | --- |
| `mosh-bridged -c` flag (the 2026-08-29 fix) | deployed on the Air, working | `scripts/mosh-bridged:66-73` passes `-c $colors` |
| tmux client TERM on the Pro | healthy | every attached client reports `xterm-256color` with `RGB` in `#{client_termfeatures}` |
| Codex pane environment on the Pro | healthy | pane + codex binary both carry `TERM=xterm-256color`, `COLORTERM=truecolor` |
| What codex emits | healthy | `capture-pane -e` shows a normal mix of truecolor (`38;2;…`) and ANSI-indexed SGR |
| Codex theme config | identical | no `theme`/`color` keys in `~/.codex/config.toml` on either host; both run codex-cli 0.146.0 |

## Root cause

**mosh's terminal emulator does not implement SGR 2 (dim/faint) and drops it silently.** Everything
else survives; dim does not, and codex's TUI is built on dim.

Loopback probe (mosh-server + mosh-client 1.4.0 on 127.0.0.1, output captured through a sized pty —
see Probe recipe below). Server-side app printed five styled tokens; mosh-client re-emitted:

| sent | received by the local terminal |
| --- | --- |
| `[2m` DIMTEX | **no SGR at all — dim dropped** |
| `[1m` BOLDTX | `[0;1m` preserved |
| `[3m` ITALIC | `[0;3m` preserved |
| `[38;2;200;100;50m` TRUCOL | `[0;38;2;200;100;50m` preserved |
| `[38;5;3m` IDX3TX | `[0;33m` preserved (normalised, same colour) |

mosh is a state-synchronising emulator, not a byte pipe: it keeps a framebuffer of cell attributes
and re-emits them locally. Its attribute model has no faint bit, so `[2m` vanishes at the emulator —
no flag, env var, or TERM setting can carry it through. (1.4.0 is the latest release, 2022.)

Why codex is the visible victim: one screenful of a live codex pane on the Pro contained 16×`[2m`
plus `[1;2m`/`[0;2m` combos — codex renders its entire secondary-text hierarchy (borders, hints,
timestamps, muted rows) as dim default-foreground text. Over mosh all of that renders at full
brightness, so the UI reads flatter/brighter and the visual hierarchy collapses. Claude Code uses
explicit truecolor greys (e.g. `38;2;128;128;128`) for much of its muted text, which survive the
hop — so the same loss is barely visible there.

## Fix (implemented 2026-09-05, same day)

Patched mosh itself. Upstream master already carries a `faint` bit in the `Renditions`
attribute enum but never wires it: `set_rendition` ignores SGR 2 and `sgr()` never emits it.
Two-spot patch in `src/terminal/terminalframebuffer.cc` (parse `2`, make `22` clear bold+faint,
emit `;2`) — kept with build/verify instructions in `.claude/tools/mosh-faint/`.

Deployed as `~/.local/mosh-faint/` on **both** hosts (stock Homebrew mosh untouched);
`scripts/mosh-bridged` now prefers those binaries on both ends and falls back to stock when
the prefix is missing. Verified end-to-end through the real bridge in both directions
(Air→Pro and Pro→Air): `[2m`, `[2;38;2;…m`, and `[1;2m` all arrive intact.

**To pick it up: reconnect** (`pro`/`prot`/`air`/`airt`). The loss was at view-time, so existing
codex sessions render correctly on the first patched connection — nothing needs restarting.
The initial "unfixable from outside" conclusion below the ruled-out table was wrong — it was
a 10-line patch away.

## Probe recipe (reusable)

`script -q` in a tty-less session gives mosh a 0×0 pty and it aborts with `Error: vector` before
connecting — that is a broken probe, not a mosh failure. Use a pty with an explicit winsize
(`pty.openpty()` + `TIOCSWINSZ` 24×80, then spawn `mosh-client` on it); harness kept at the session
scratchpad as `ptyprobe.py`. Loopback pair: `mosh-server new -i 127.0.0.1 -c 256 -- /bin/sh -c
'printf …; sleep 6'`, then `MOSH_KEY=<key> mosh-client 127.0.0.1 <port>` under the harness.
