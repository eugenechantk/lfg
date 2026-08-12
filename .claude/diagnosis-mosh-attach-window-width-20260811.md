# Diagnosis — remote sessions attach at the wrong width (no wrap) from the desktop app

**Date:** 2026-08-11 · **Host:** Eugenes-MacBook-Pro · tmux 3.6b
**Symptom:** clicking a session on another host in the desktop app opens an iTerm/mosh window
whose content is the wrong width — long lines run off the right edge instead of wrapping.
Only *some* sessions.

## Root cause

`ensurePaneRows` (`src/tmux.ts:61`) keeps detached panes at 120×200 so a question's preamble is
still on screen when the pump scrapes it. It does that with `tmux resize-window`.

From `man tmux`, `resize-window`:

> This command will automatically set **window-size to manual** in the window options.

`window-size manual` means the window no longer follows the attached client — and **nothing ever
sets it back**. So every session the pump has ever resized is permanently pinned to a 120×200
window. When you attach (mosh or plain ssh or locally), tmux keeps the window at 120×200 and your
terminal just shows a *viewport* onto it:

- terminal narrower than 120 cols → everything past your width is off-screen; lines look unwrapped/truncated
- terminal wider than 120 → text wraps at 120 with a dead right margin
- 200 rows into a ~30–60 row terminal → you also only ever see a slice vertically

## Evidence

Live inventory on this host (`tmux list-windows -a -F '… #{window-size} …'`):

```
cy-135425-91017   120x200  window-size=manual  attached=0    <- pump-resized, will attach wrong
lfg-47c582        120x200  window-size=manual  attached=0    <- same
cy-133259-2195     79x79   window-size=latest  attached=1    <- never resized (skipped while attached)
lfg-ef54f9        120x200  window-size=latest  attached=0    <- created at 120x200, never resize-window'd; attaches fine
```

Global default is `window-size latest`, `aggressive-resize off` — so the pinning is per-window,
not config.

Controlled repro (throwaway session, pty client forced to 90×30):

```
created:            window=120x200 size-opt=latest
client 90x30    ->  window=90x29   size-opt=latest     # correct: window follows client
after pump resize:  window=120x200 size-opt=manual
client 90x30    ->  window=120x200 size-opt=manual     # BUG: window ignores client
```

## Why only some sessions, and why it reads as "remote-only"

`ensurePaneRows` deliberately skips attached sessions, so a session you're already sitting in
(`cy`/`cx` in iTerm) is still `window-size=latest` and attaches correctly. Sessions on *another*
host are by definition ones you're not attached to → detached → that host's pump has stamped them
`manual`. Nothing about mosh or the network is involved; a local `tmux attach` to a pump-resized
session misbehaves identically.

## Fix

Flip the option back on the way in — the desktop's attach command becomes:

```
tmux set-option -w -t <name> window-size latest \; attach-session -t <name>
```

in `Opener.remoteAttachCommand` (`desktop/LFGSessions.swift:2082`, the `attach` string at :2083)
and the local branch of `Opener.open` (:2041).

Verified: same throwaway session, `manual` at 120×200, attach with the option flip →
`window=90x29 size-opt=latest`.

Self-healing, so pane capture is not sacrificed: on detach the window keeps the client's small
size (< 200 rows), so the pump's next tick re-runs `ensurePaneRows`, restores 120×200 and re-stamps
`manual`. Manual while detached (server's need), latest while attached (human's need).

## Shipped 2026-08-11

`Opener.attachCommand(tmuxCommand:tmuxName:)` in `desktop/LFGSessions.swift`, used by both the local
branch of `Opener.open` and `Opener.remoteAttachCommand`. The `;` between the two tmux commands is a
single-quoted argument, not `\;` — iTerm tokenizes the command line itself with no shell in the loop.

`resumeLocally` (`tmux new-session -A`) is deliberately untouched: the session may not exist yet, and
a leading `set-option` against a missing target would fail the whole command sequence.

Deployed to `/Applications/lfg.app` on **both** hosts (built once on the Pro with the Developer ID
identity, `ditto`'d to the Air per [[air-desktop-adhoc-signing]]; previous bundle backed up to
`~/.lfg/backup/lfg.app.prev` on each). The Air's app was running and was quit/relaunched; the Pro's
was not running and was left that way.

### Verification

| Check | Result |
| --- | --- |
| `--desktop-feature-test` (74 tests, incl. 4 new attach-sizing ones) | ok, both hosts |
| Pro → Air, real mosh, installed binary, pty client 90×30 | `window=90x29 size-opt=latest` |
| Air → Pro, real mosh, installed binary, pty client 100×28 | `window=100x27 size-opt=latest` |
| Self-healing on a **real** pump-watched session (`cy-152210-86216`) | attach → `90x29 latest`; detached → pump restored `120x200 manual` within 20s |
| Signature after `ditto` to the Air | `codesign --verify --strict` OK, Developer ID retained |

Harness note: the remote probes must `export TERM=xterm-256color` — mosh exits with "TERM
environment variable not set" from a non-interactive ssh, which looks exactly like the fix failing.

**Caveat:** with `window-size latest` and more than one client attached, the newest client wins and
any other terminal on that session gets a mismatched view. That is standard tmux behaviour and is
what already happens for non-pump sessions; adding `-d` to the attach would instead kick the other
client off, which is probably worse for a remote session someone else may be watching.
