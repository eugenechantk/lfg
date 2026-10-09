# Diagnosis: lfg-started codex panes lose the composer's gray background

2026-10-09, Pro (`Eugenes-MacBook-Pro`), tmux 3.6b, codex 0.159.2 (Homebrew) and 0.156.1 (bun).

## Root cause

When codex starts, it asks the terminal for its default colours once, with
OSC 10 (foreground) and OSC 11 (background). It uses the answers to compute
every tint: the composer's gray band, the user-message background, and so on.

lfg starts codex with `tmux new-session -d`. At that moment the session has
**no client attached**. tmux can only answer OSC 10/11 from an attached
client's terminal, or from an explicit pane style. Here it has neither, so the
queries get no reply. Codex then draws without any tint. It **never asks
again**: attaching a client, resizing, and a focus-in event all leave the
composer plain.

Eugene's own `cx`/`codexy` sessions start inside an attached iTerm client.
iTerm answers through tmux, so those panes get the tint. That explains the
"sometimes": it depends on who started the pane, not on the codex version.

## Evidence

All probes ran on a private tmux socket (`-L probecolour`) and were killed
afterwards. No existing session was touched except read-only `capture-pane`.

| Probe | Composer row (`capture-pane -e`) |
|---|---|
| Real `lfg-b328f7` (lfg fork, detached at start) | `ESC[1m›ESC[0m ESC[2m…` — no `48;` |
| Real `codexy-104937-75992` (shell alias, attached) | `ESC[48;2;49;52;57m` |
| Probe: codex 0.159.2 detached | `ESC[1m›ESC[0m ESC[2mAsk Codex to do anythingESC[0m` — no bg |
| Probe: codex 0.159.2, fake terminal attached before start | `ESC[48;2;57;57;60m` (fake bg `#1e1f22`) |
| Probe: codex 0.156.1 detached / attached-first | no bg / `ESC[48;2;57;57;60m` |
| Probe: fake terminal answering iTerm's dark bg `#15191f` | `ESC[48;2;49;52;57m` — identical to the real codexy pane |
| Detached pane, then attach + `resize-window` + focus-in (`ESC[I`) | still no bg |

OSC probe (a small Python script that sends `ESC]11;?` and waits 2 s):

- Detached pane: reply `b''`.
- Pane with a client whose terminal answers: `ESC]11;rgb:1e1e/1f1f/2222ESC\`.
- Detached pane with `window-style bg=#15191f`: OSC 11 is answered
  (`rgb:1515/1919/1f1f`), but **OSC 10 is not** (`10=> ''`).
- A detached codex with `window-style 'bg=#15191f'` only: **still no tint**.
  Codex needs both answers.

The codex binary contains `terminal startup probes completed`,
`default_colors`, and `initial cursor position probe timed out`. I found no
re-query path in its strings, which matches the behaviour above.

Not a factor:

- **`COLORFGBG`.** `15;0` was already set in the probe panes' environment, and
  the detached composer was still plain.
- **Version skew.** Both 0.159.2 and 0.156.1 behave the same.

iTerm default profile: separate light and dark colours. Dark is fg `#dcdcdc`
on bg `#15191f`; light is `#101010` on `#fafafa`. macOS is currently in Dark
mode.

## Affected spawn paths

Every lfg codex pane goes through `managedCodexSessionArgv`
(`src/tmux.ts:744`) via `spawnManagedCodexSession`:

1. `POST /api/sessions/new` with `agent: codex`, including handoff / "Switch to
   Codex" (`src/commands/serve.ts:2569`).
2. Resume a closed codex session (`serve.ts:314`).
3. Fork, codex CLI path: `codex fork <id>` (`serve.ts:444`).
4. Fork of an external (desktop app) thread: app-server fork, then resume
   (`serve.ts:413`).
5. WhatsApp agent session (`src/commands/whatsapp.ts:413`).

Not affected: the desktop "Resume locally" path, which runs inside a new iTerm
window, so a client is attached from the start.

## Recommended fix (proven on a probe pane)

1. In `managedCodexSessionArgv`, chain a pane style onto the same tmux
   invocation, so it exists before codex can send its probe:

   ```
   tmux new-session -d … <codex argv> ; set-option -w -t <name> window-style 'fg=#dcdcdc,bg=#15191f'
   ```

   In the argv array, pass `";"` as its own element. One tmux command queue
   runs both, so there is no race with codex's startup.
2. Once codex has settled, unset it: `tmux set-option -u -w -t <name>
   window-style`. Then the pane paints on the real client's background. The
   resume and external-fork paths already wait in `awaitCodexBootstrap`. The
   new and fork paths poll for the session id. A plain ~10 s timer after the
   spawn also works, because codex has cached the colours by then. Leaving the
   style set is harmless in dark iTerm but paints a dark block in light mode.
3. Colours: default to the iTerm dark pair (`#dcdcdc` / `#15191f`). Optionally
   pick the light pair when `defaults read -g AppleInterfaceStyle` is not
   `Dark`, and allow an env override (for example
   `LFG_CODEX_PANE_COLOURS=fg,bg`).

Proof (probe `probe-colour-fix2`, codex 0.159.2, zero clients at start):

```
detached-with-style composer: ['48;2;49;52;57m']
after-unset         composer: ['48;2;49;52;57m']
after-attach        composer: ['48;2;49;52;57m']
after-resize        composer: ['48;2;49;52;57m']
```

`49;52;57` is byte-identical to the composer of Eugene's real attached codexy
pane.

Already-running lfg codex panes, such as `lfg-b328f7`, cannot be fixed in
place. Codex only re-reads the colours when the process restarts, for example
on a resume.

## Side finding: a trailing `;` in a spawn argv element

tmux treats **any argv element ending in `;`** as a command separator, not only
a bare `;`. Probe: `new-session … 'fix the bug;' 'tail'` returned `unknown
command: tail`, and the command never ran. Today the prompt is the last
element, so a prompt ending in `;` only loses that character. Once a `;
set-option …` is chained on, it matters more. Escape it: `x.endsWith(";") ?
x.slice(0, -1) + "\\;" : x`. That round-trips: `'fix the bug\;'` arrived as
`'fix the bug;'`. This applies to the claude `managedSessionArgv` too.

## Leftovers

The 7 codex probes each wrote an empty rollout under
`~/.codex/sessions/2026/10/09/`: 23,867 bytes, cwd lfg, 0 user messages,
created between 11:08 and 11:12. They do not appear in lfg's
`/api/sessions/resumable`. No probe processes or tmux sessions remain.

## Fix applied (2026-10-09)

`managedCodexSessionArgv` chains `; set-option -w -t =<name>: window-style <style>` onto
new-session; `spawnManagedCodexSession` unsets it after 15 s. Style is iTerm's pair for the
macOS appearance (`codexPaneStyle`), overridable with `LFG_CODEX_PANE_STYLE`. Prompts go
through `tmuxLiteral`, which escapes a trailing `;` (both spawners).

Live check through the real `spawnManagedCodexSession`, detached, zero clients: composer row
`ESC[48;2;49;52;57m` (identical to the attached codexy pane); style `[]` after the hold, tint
kept after a resize. Takes effect for new codex panes after the next server restart.
