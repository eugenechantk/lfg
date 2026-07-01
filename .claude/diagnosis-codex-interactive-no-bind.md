# Diagnosis — codex session "keeps loading" on iOS client

## Symptom
A codex session appears in the iOS session list but the detail view spins forever ("keeps loading").

## Ground truth
`GET /api/sessions` returns for the codex session:
```json
{
  "agent": "codex",
  "cmd": ".../bin/codex --yolo",
  "cwd": "/Users/eugenechan/dev/inbox",
  "sessionId": null,
  "transcriptPath": null,
  "tmuxTarget": "codexy-140436-8537:0.0"
}
```
`sessionId` and `transcriptPath` are **null**. The iOS detail view loads messages via
`/api/sessions/{id}/messages` and needs a 36-char id; with none it can never backfill,
so the view never leaves the loading state.

A valid rollout DOES exist on disk:
`~/.codex/sessions/.../rollout-2026-07-01T14-04-44-019f1c47-a1ef-7193-8233-f71165b4ac5a.jsonl`
- `session_meta.payload.cwd` = `/Users/eugenechan/dev/inbox` (matches the session cwd)
- created 14:04:44, process started 14:04:36 → rollout written ~8s after launch

## Root cause
`listSessions` in `src/sessions.ts` binds a running tmux `codex` process to its rollout
transcript only via one of:
1. a `resume`/`fork <uuid>` in the command line (line ~1032), or
2. `cwd + startedAt + first-user-prompt` match, gated on `if (!thread && cwd && prompt)`
   (line ~1035), where `prompt` = `codexPromptFromCmd(cmd)` (text after `-- `).

This session was launched **interactively**: `codex --yolo`, with **no resume id and no
`-- <prompt>`**. So `prompt` is null, the fallback block is skipped entirely, `sessionId`
stays null, and there is no binding path at all for a promptless interactive codex.

## Fix
Add a promptless fallback: when a codex process has no resume id and no inline prompt,
bind it to the freshest **unclaimed** rollout in the same cwd whose `createdAt` is near the
process `startedAt` (rollout created at/after launch, within a window). Pick the thread
whose `createdAt` is closest to `startedAt` so multiple codex sessions in the same cwd each
bind to their own rollout. Reuse the existing `claimedCodex` set so a rollout is never
double-bound.

Extracted the binding decision into a pure helper `pickCodexThread(...)` for unit testing.
