# Delegation Brief: codex resume + fork (server phase)

## Goal

Make **resume** and **fork** work for codex sessions the way they already work for claude
sessions, server-side only. The iOS client is a separate later phase — do not touch `ios/`.

Read `.claude/feature/codex-resume-and-fork.md` in this worktree first. It is the spec:
verified CLI semantics, the six claude-only gates with file:line, the design, and a trap
that will silently reintroduce a bug we just fixed. This brief adds the acceptance
criteria and constraints; it does not repeat the doc.

## Working directory

`/Users/eugenechan/dev/personal/lfg/.worktrees/codex-resume-fork` — a git worktree on
branch `codex-resume-fork`. Work only here. Do NOT touch the main checkout at
`~/dev/personal/lfg`, which has a live server running against it.

`node_modules` is symlinked to the main checkout; `bun test` works.

## Scope (server only)

1. **`listResumable`** (`src/sessions.ts:1483`) — enumerate codex rollouts in addition to
   `~/.claude/projects`, and add an `agent` field to `ResumableSession` so callers can
   route by family. Reuse `codexThreads()` or `~/.codex/session_index.jsonl`; do not write
   a third rollout scanner.
2. **`resumeClosedSession`** (`src/commands/serve.ts:134`) — branch on transcript family.
   claude keeps today's path exactly. codex spawns `codex resume <sessionId> [prompt]` with
   the house flags (`--sandbox danger-full-access --ask-for-approval never`, `--cd`,
   `--add-dir`), and returns the **same** sessionId, because codex resume is id-stable.
3. **Send-path revive** (`src/commands/serve.ts:2087`) — a send to a closed codex session
   must revive it through the same branch.
4. **`forkSession`** (`src/commands/serve.ts:191`) — branch on family. codex spawns
   `codex fork <sourceId> [prompt]` and returns the NEW id.
5. **Binding** — see "Two binding rules" below. This is the heart of the task.
6. **Model allowlist** — `CLAUDE_MODELS` is validated in both lanes (`serve.ts:142`,
   `serve.ts:198`) and would reject codex slugs. Validate per family: claude against the
   allowlist, codex by shape (the create path already does this).
   Do **not** pass `--model` on codex resume: `codex resume` restores the thread's own
   model, and overriding it would silently bump the conversation's model.

## Two binding rules (get these right or nothing works)

**Resume binds by known id.** We asked codex to resume `<id>`; it appends to that exact
rollout. Bind directly to it. It must NOT go through `pickCodexThread`, whose
`createdAt >= startedAt - CODEX_BIND_SKEW_MS` filter will reject a rollout created hours
ago — that yields a null sessionId and the session becomes invisible in every client,
which is precisely the bug fixed on 2026-07-31.

This applies to the **live re-scan** too, not just the spawn moment. `listSessions()` /
`refreshWatchSet` re-derive bindings periodically; a running resumed codex process must
keep resolving to its pre-existing rollout. Record the intended binding at spawn time
(the managed-session registry is the natural place) and prefer it over the heuristic.

**Fork binds by parent link.** A forked rollout's `session_meta` carries
`forked_from_id` equal to the source session id — verified on real data. Bind by scanning
for a rollout with `forked_from_id == sourceId` and `createdAt` at/after the spawn,
excluding already-claimed ids. This is exact, so fork needs neither prompt matching nor
the single-candidate ambiguity guard, and two forks of one parent stay distinguishable.

Budget the fork wait like the create path (~14s, `CODEX_CREATE_SESSION_BIND_POLLS`): the
rollout appears at launch but takes seconds to fill, and the client's POST times out at 20s.

## Constraints

- Only `src/` and its tests. Nothing under `ios/`, `web/`, or `desktop/`.
- Do not restart the lfg server or kill any tmux session. Do not run `git push`.
- Do not weaken or "simplify" the create-path binding landed on 2026-07-31
  (`pickCodexThread` tie-breaking, the 14s budget, the single-candidate fallback).
  If you believe you must change it, stop and say why instead.
- Match the file's comment style: these are subtle ordering/lifetime behaviors and this
  codebase documents *why* above such code.

## Verification (run these, paste real output)

1. `bun test` — full suite green (144 currently pass; no regressions).
2. `bunx tsc --noEmit` — clean.
3. New unit coverage, at minimum:
   - resume binds a rollout whose `createdAt` long predates the process start (the skew
     trap) — this test must fail against the heuristic path;
   - fork binds via `forked_from_id`, including **two forks of the same parent** binding to
     their own rollouts;
   - `listResumable` returns codex rows tagged with the right agent.
4. State clearly which parts you could NOT verify without a live server.

Do **not** start a server on port 8766 — it is in use by the live instance. If you want a
smoke test, run on a spare port via `LFG_PORT`, and shut it down afterwards.

## Definition of done

- [ ] Closed codex sessions appear in `listResumable`, tagged by agent
- [ ] Explicit resume and send-path revive both work for codex, returning the same id
- [ ] Fork works for codex, returning a new id, binding via `forked_from_id`
- [ ] Resume binding survives the periodic re-scan (not just the spawn moment)
- [ ] Model validation is per-family; no `--model` forced on codex resume
- [ ] `bun test` green, typecheck clean, new tests cover both binding rules

## Report back

Files changed, verification output, how you made the live re-scan prefer the recorded
binding, anything you could not verify without a live server, and anything left incomplete.
