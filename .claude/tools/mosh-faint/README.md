# mosh-faint — patched mosh: SGR 2 (dim) + OSC 10/11 answers

Two fixes to stock mosh (1.4.0, and master as of `decd9b7`), both hit codex's TUI over
`mosh-bridged`. See `.claude/diagnosis-codex-mosh-dim-20260905.md`.

**1. Dim/faint (SGR 2) is dropped.** Mosh has a `faint` bit in its `Renditions` enum but
never parses SGR 2 into it and never emits it — dim text renders at full brightness.
`faint.patch` wires it up in `src/terminal/terminalframebuffer.cc`:

- `set_rendition`: `case 2` sets faint; `case 22` clears both bold and faint
  (normal-intensity per ECMA-48).
- `sgr()`: emits `;2` when the faint bit is set.

**2. OSC 10/11 default-colour queries are swallowed.** Mosh is a state-sync emulator,
not a byte pipe, so an app's `OSC 10;?` / `11;?` probe can never reach the real
terminal. Codex probes both with a 100ms deadline at startup and, with no answer,
skips painting its composer's grey fill (`default_bg()` → None; there is no env or
config fallback in codex). The patch makes `Dispatcher::OSC_dispatch`
(`src/terminal/terminalfunctions.cc`) answer those queries from `MOSH_OSC_FG` /
`MOSH_OSC_BG` env vars (sanitised, e.g. `rgb:1e1e/2222/2727`); `scripts/mosh-bridged`
learns the real values by querying the local terminal's `/dev/tty` at connect time
(350ms budget, best-effort) and prefixes them onto the remote `mosh-server` command.
Unset vars → queries ignored, stock behaviour.

## Where it's installed

`~/.local/mosh-faint/{bin,share}` on **both** the Air and the Pro (built 2026-09-05).
`scripts/mosh-bridged` prefers these binaries on both ends and falls back to stock
Homebrew mosh when the prefix is absent. Stock mosh is untouched.

## Rebuilding (either host)

```sh
git clone https://github.com/mobile-shell/mosh.git && cd mosh
git apply <this-dir>/faint.patch
brew install protobuf automake autoconf libtool pkgconf   # deps
./autogen.sh
./configure --prefix="$HOME/.local/mosh-faint" CXXFLAGS="-O2 -std=c++17"
make -j8 && make install
```

Binaries dynamically link Homebrew protobuf + abseil — rebuild after a major
protobuf/abseil upgrade if `mosh-client` starts failing to load, or if connections
degrade, delete `~/.local/mosh-faint` to fall back to stock instantly.

## Verifying

Loopback: `mosh-server new -i 127.0.0.1 -c 256 -- /bin/sh -c 'printf
"\033[2mDIMTEX\033[0m\n"; sleep 6'`, connect `MOSH_KEY=<key> mosh-client 127.0.0.1
<port>` through a pty with a real winsize (`pty.openpty()` + `TIOCSWINSZ`; `script -q`
without a tty gives mosh a 0×0 pty and it dies with `Error: vector`). The client's
output must contain `[0;2mDIMTEX`. Verified end-to-end both directions on 2026-09-05.

OSC: run the same loopback with `MOSH_OSC_BG=rgb:1e1e/2222/2727` on mosh-server and a
remote command that does `stty raw -echo < /dev/tty` then prints `\033]11;?\007` and
reads the tty — the reply must echo the value back. (Raw mode matters: in canonical
mode the newline-less reply sits invisibly in the line buffer.) Full-chain proof: spawn
`codex` in an attached tmux through mosh-bridged and capture-pane must show a
`48;2;…` grey fill under the input line. Both verified 2026-09-05. Throughput A/B vs
stock 1.4.0 (30k-line scroll, loopback): identical (0.37s vs 0.37s) — no perf cost.
