# Delegation Brief: fix codex session → rollout transcript binding

## Goal

A tmux-spawned `codex` session must bind to its rollout transcript so `/api/sessions`
returns a non-null `sessionId` / `transcriptPath`. Today every prompt-launched codex
session binds to nothing, so the iOS client's transcript fetch 404s with
`no transcript found for that session` and no messages ever appear.

## Evidence (reproduced on this machine, codex-cli 0.145.0)

Two live codex sessions (`lfg-4e7b91`, `lfg-bb8957`, pids 9535 / 10344, cwd
`/Users/eugenechan/dev/personal/lfg`) both return from `curl 127.0.0.1:8766/api/sessions`:

```
"sessionId": null,
"transcriptPath": null,
```

Their rollouts exist and are actively written:
`~/.codex/sessions/2026/07/31/rollout-2026-07-31T20-21-09-019fb81f-0a99-7490-9082-4b4cf3849db3.jsonl`
`~/.codex/sessions/2026/07/31/rollout-2026-07-31T20-21-23-019fb81f-3dd5-7fe0-ab68-fa81255055ad.jsonl`

Binding goes through `pickCodexThread()` in `src/sessions.ts`, prompt mode:
`samePrompt(thread.firstUserText, procPrompt)`. Both sides of that comparison are
currently wrong. Either bug alone breaks the bind.

### Bug A — `firstUserTextFromTop()` returns codex's injected instructions, not the prompt

`src/sessions.ts:378` returns the FIRST user-role message in the rollout. Current codex
injects an instructions block as a synthetic first user message, so it returns:

```
# AGENTS.md instructions\n\n<INSTRUCTIONS>\n# About Eugene\n...
```

The real prompt is the SECOND user message. Verified order in the rollout above:

1. `response_item` / `message` role=user → the `# AGENTS.md instructions` blob
2. `response_item` / `message` role=user → `Does lfg work for codex?\n\nIf so, ...` (the real prompt)
3. `event_msg` / `user_message` with `message` = the real prompt

So `firstUserText` never equals the launch prompt for any repo that has an AGENTS.md
(or a global `~/.codex/AGENTS.md`) — i.e. effectively always.

### Bug B — `ps` octal-escapes newlines, so multi-line prompts can never match

`procinfo.ts` snapshots processes with `ps -axo pid=,ppid=,lstart=,command=`. macOS `ps`
renders embedded newlines in argv as the literal 4-character sequence `\012`. The API's
`cmd` field confirms it:

```
... --model gpt-5.5 -- Does lfg work for codex?\012\012If so, can we update the model selectors ...
```

`codexPromptFromCmd()` (`src/sessions.ts:389`) returns that string verbatim, and
`samePrompt()`'s `\s+ → " "` normalization does not undo `\012` (it is a backslash plus
three digits, not whitespace). So the process-side prompt keeps literal `\012` while the
rollout side has real newlines — no multi-line prompt can ever match.

## Constraints

- **Only touch `src/sessions.ts` and `src/codex-bind.test.ts`** (plus a test fixture file
  if you add one). Two other codex sessions are concurrently editing `web/src/App.tsx` —
  do not touch `web/` at all.
- Do not restart, kill, or re-serve the running lfg server, and do not kill any tmux session.
- Runtime is Bun. Follow existing file style (the codebase uses explanatory comments above
  non-obvious heuristics — match that density).
- Keep `pickCodexThread()`'s exported signature stable; `src/codex-bind.test.ts` depends on it.

## Spec

### Fix A — resolve the real launch prompt from a rollout

Change the "first user text" extraction so it yields the user's actual prompt, not codex's
injected preamble. Requirements, in plain English:

- Prefer the authoritative signal: the `event_msg` payload of type `user_message`, whose
  `message` field is the raw prompt with no injected wrapper. If one exists in the scanned
  prefix, use it.
- Fall back (older rollout formats / prefix truncation) to scanning `response_item` user
  messages in order and skipping any that are clearly injected context rather than a typed
  prompt. Treat a message as injected when its leading text begins with a known wrapper
  marker — at minimum `# AGENTS.md instructions`, `<INSTRUCTIONS>`, `<user_instructions>`,
  `<environment_context>`. Return the first message that survives the filter.
- If everything in the scanned prefix is injected context, return null (no bind) rather
  than returning the preamble — a wrong bind is worse than no bind.
- Keep the existing bounded read (currently a 256 KB prefix). The instructions blob can be
  large, so confirm the window is still big enough to reach the real prompt after it; if
  not, raise it to a still-bounded size and say what you chose and why.

### Fix B — make the process-side prompt comparable

`codexPromptFromCmd()` must undo `ps`'s escaping so the returned prompt is the real string.
Decode backslash-octal escapes (`\012` → newline, `\011` → tab, `\015` → carriage return,
and the general `\NNN` form) before returning. Note the value is also used for display
elsewhere, so decoding at the source — not only inside the comparison — is the right layer.

Leave `samePrompt()`'s whitespace collapsing as-is; after decoding it does the right thing.

### Behavior that must not regress

- Promptless (interactive) binding, cwd filtering, the `CODEX_BIND_SKEW_MS` /
  `CODEX_BIND_WINDOW_MS` guards, and the `claimed` set must all behave exactly as today.
  The existing 133-line `src/codex-bind.test.ts` must stay green unmodified except for
  additions.
- Two concurrently-running codex sessions launched with the IDENTICAL prompt in the same
  cwd (exactly the live case here) must bind to two DIFFERENT rollouts — the `claimed`
  set already handles this; add a regression test proving it.

## Verification (run these; paste real output in your report)

1. `cd /Users/eugenechan/dev/personal/lfg && bun test src/codex-bind.test.ts` — all green,
   including new cases for: injected-AGENTS.md skipping, `\012`-escaped multi-line prompt
   matching, and the two-identical-prompts-two-rollouts case.
2. `bun test` (whole suite) — no new failures vs. before your change.
3. **Real-data proof.** Write a throwaway script under `/tmp` (not in the repo) that imports
   the fixed helpers and, against the two real rollout paths listed above plus the real
   `cmd` strings from `curl -s 127.0.0.1:8766/api/sessions`, prints the resolved prompt and
   the bind result. It must show the resolved text is `Does lfg work for codex?...` (NOT the
   AGENTS.md blob) and that each of the two processes binds to a distinct rollout id.
   If a helper isn't exported, export it — that's an acceptable change.
4. `bunx tsc --noEmit` (or the repo's typecheck script if one exists) clean.

Do NOT restart the lfg server to test end-to-end — Claude will do that separately with
Eugene's OK.

## Definition of done

- [ ] Fix A implemented; injected instruction messages never returned as the prompt
- [ ] Fix B implemented; octal escapes decoded at the source
- [ ] New tests cover both bugs + the identical-prompt collision case
- [ ] `bun test` green; typecheck clean
- [ ] Real-data script output proves correct prompt resolution and distinct binds
- [ ] Nothing under `web/` touched; no server or tmux session restarted

## Report back

Files changed, the exact verification output (test summary + real-data script output),
the read-window size you settled on and why, and anything you left incomplete.
