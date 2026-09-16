# Diagnosis — codex resume dies silently, message shows "delivered", session vanishes (2026-09-06)

## Symptom (Eugene, iOS, 17:56 HKT)
Sent a message to the closed codex session `01a07207-b399…` (fiftyworkout / FiftyStrong iOS build).
Row flipped to running, back to idle with the message "queued", then the row disappeared from the list.
"Happens on codex sessions quite often."

## Trace
| t (UTC) | evidence | meaning |
|---|---|---|
| 09:56:13.205 | `~/.lfg/managed-sessions.json` row `lfg-8a4427` `{agent: codex, sessionId: 01a07207…, cwd: fiftyworkout}` | send-to-closed path (`serve.ts` `/message` → `resumeClosedSession`) spawned `codex … resume <id> "<message>"` on the Pro |
| 09:56:13 | `journal.db` sendq row `5a023e4e…` status `delivered`, attempts 0 | handler called `recordImmediateMessage` — "delivered" means "handed to argv", never confirmed |
| 09:56:14 | journal events `prompt:null`, `busy:false`, `queue:[]` for the sid | pump baseline; no `busy:true` was ever emitted by the pump |
| 09:56–09:58 | `~/.codex/logs_2.sqlite`: zero rows from any new TUI process (every healthy start logs `terminal startup probes completed` in its first second) | codex exited during bootstrap |
| 09:59 | `tmux ls` shows no `lfg-8a4427` | pane died → tmux session gone → row vanishes from `/api/sessions` |
| — | `/tmp/lfg-serve.log`, `sendq.log` | nothing: neither the spawn nor the death is logged anywhere |

## Reproduction (the decisive step)
Replaying the exact `managedCodexSessionArgv` output by hand died the same way. Only after
`tmux set -g remain-on-exit on` did the pane keep codex's stderr:

```
Error: Failed to resume session from ~/.codex/sessions/2026/09/05/rollout-2026-09-05T22-45-02-01a07207-….jsonl:
thread/resume failed during TUI bootstrap: thread/resume failed: failed to deserialize stored thread item
subagent-completed-01a0720b-…: unknown variant `completed`, expected one of `started`, `interacted`, `interrupted` (code -32603)
```
Exit status 1, ~3s after spawn, no keypress needed when a prompt is on argv.

## Root cause — codex version skew between Eugene's shell and lfg
- The thread's `session_meta` says `originator: codex-tui, cli_version: 0.153.4`; `state_5.sqlite` `threads.cli_version = 0.153.4`, `history_mode = paginated`.
- Eugene's shell: `which -a codex` → `~/.bun/bin/codex` (0.153.4, installed 2026-09-05 21:38 by codex's own "Update now → bun install -g") then `/opt/homebrew/bin/codex` (0.146.0). `cy`/`codexy` write threads with 0.153.4.
- lfg server PATH has no `~/.bun/bin`; `codexBin()` takes `Bun.which("codex")` → `/opt/homebrew/bin/codex` = **0.146.0**, which cannot deserialize a 0.153 rollout (`subagent-completed` item variant).
- Every codex thread Eugene starts from the terminal is unreadable by the codex lfg resumes it with. Hence "quite often".

## Compounding lfg bugs (fixed in `.claude/feature/codex-resume-fails-loudly.md`)
1. `resumeClosedSession` (codex) returns ok on `tmux new-session` exit 0 and never checks the pane survived. The message is recorded `delivered`, the client is told `resumed: true`.
2. The pane runs codex bare, so its stderr dies with it — nothing to read after the fact.
3. iOS `resumedIds` suppresses the closed row for a resumed id for the rest of the app run; when the revived pane dies the session is neither live nor closed → invisible until relaunch. Same for a codex session that resumes fine and is later ended.
4. `codexBin()` prefers whatever is first on the server's PATH — no awareness that a newer codex exists elsewhere on the box.

## Ruled out
- Shell quoting / zsh `nomatch` on the `?` in the prompt: tmux 3.6b `execvp`s multi-arg commands directly (probe: redirect arg not interpreted).
- codex CLI contract: `codex resume [SESSION_ID] [PROMPT]` is valid on 0.146 and 0.153.
- Update selector: appears for this cwd but is bypassed when a prompt is on argv; it is not what killed the pane.
- Server env / binary path: same tmux server, same binary as the by-hand replay.
- The Air: `~/.lfg` is not synced; the sendq row and managed row are the Pro's.

## Fixes applied
- Env: `npm i -g @openai/codex@0.153.4` → `/opt/homebrew/bin/codex` is 0.153.4 (the Air still needs the same check — unreachable at `eugenes-macbook-air` during this session).
- Code: see the feature doc.

## Lesson (memory + CLAUDE.md)
A managed pane that dies silently: replay the exact argv under `tmux set -g remain-on-exit on` FIRST.
It is one command and it printed the answer; the hour before it was spent on hypotheses the dead pane could have refuted instantly.

## Addendum — what the fix taught (2026-09-06, later)
- codex 0.153.4 draws the composer (`› …`) ~250ms after spawn, BEFORE `thread/resume` resolves; the status line (`model · cwd`) appears only once the thread loaded. The composer is not a success signal; composer + status line + 1s dwell is.
- With a prompt on argv, the fatal `Error:` line's first wrapped fragment is lost to the alternate screen; only the continuation + `Pane is dead` remain. Parse the block above the trailer.
- The 18MB thread takes >6s to fail under load (the fork of it fails in 1–3s): a fixed watch window silently passes big threads. Watch until settled-or-dead, cap 30s.
- A codex that dies in `thread/resume` writes nothing to `~/.codex/logs_2.sqlite` — absence of a TUI process in that DB is itself the fingerprint.
- codex 0.153 ignores unknown items in a rollout, so an unreadable-thread fixture cannot be crafted by editing one; use an older binary in a scratch npm prefix + `LFG_CODEX_BIN`, and `codex fork <id>` for a copy of the thread with no active writer.
