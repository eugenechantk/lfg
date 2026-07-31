# Scope: Codex resume + fork

**Status:** Scoping
**Tier:** Product (shipping server + iOS app)
**Author:** session 2026-07-31
**Supersedes:** `.claude/feature/codex-resume-support.md` (2026-06-29) — that doc scoped
resume only and predates the discovery that `codex fork` exists.

## Definitions (confirmed)

- **Resume** — bring a *closed* session back to life. Its pane was reaped (box reboot,
  host restart, user closed it) but the transcript survives on disk. Resuming continues
  the same conversation. In lfg this is both an explicit action and the **wake-up-on-send**
  path: sending to a closed session revives it (`serve.ts:2087`).
- **Fork** — branch an existing session into a **new** session that inherits the
  conversation up to the branch point, after which the two are fully independent: the
  fork does not write to the original, and further turns in the original do not reach
  the fork.

Two clarifications on top of those:

1. **Fork is not limited to closed sessions.** lfg's existing `forkSession` only refuses
   when the session is live *on another host* (`serve.ts:200`). Forking a session running
   on this box is allowed and is the common case — branch a conversation you're in.
2. **Codex resume is id-stable; Claude resume is not.** This is the single most important
   design fact below.

## Verified CLI semantics (measured 2026-07-31, codex-cli 0.145.0)

| | Original rollout | Rollout count | Resulting id |
|---|---|---|---|
| `codex fork <id> <prompt>` | byte-identical (112035 → 112035) | 31 → **32** | **new** id, inherits full history |
| `codex resume <id> <prompt>` | grew 73298 → **114124** | 32 → 32 | **same** id, continues in place |

Both were run in tmux the way lfg spawns sessions, and both carried prior context
correctly. Compare with Claude, where **both** `--resume` and `--resume --fork-session`
mint a fresh id and a fresh transcript (`serve.ts:166`, `tmux.ts:245-248`).

**Consequence:** codex resume needs none of the new-id machinery Claude resume requires —
no id remap, no client-side navigation swap, no `applyResume` propagation. The closed card
simply becomes live again under the id it already had. Codex resume is *simpler* than the
Claude path it will sit next to.

**A forked codex rollout records its parent.** `session_meta.forked_from_id` on the new
rollout equals the source session id (verified). Fork binding can therefore be exact
rather than heuristic — see Design.

## Current state — five claude-only gates

| # | Gate | Location | Effect |
|---|---|---|---|
| 1 | `listResumable` scans only `~/.claude/projects` | `sessions.ts:1483` | closed codex sessions never appear in the resumable list |
| 2 | `resumeClosedSession` rejects non-claude transcripts | `serve.ts:155` | explicit resume → 400 "only claude sessions can be resumed" |
| 3 | same gate on the send path | `serve.ts:2087` | a send to a closed codex session can't revive it |
| 4 | `forkSession` drives the claude CLI only | `serve.ts:205` | fork is server-side claude-only |
| 5 | `canFork` hides the UI for the codex family | `SessionDetailView.swift:455` | Fork button absent on codex sessions |

Gate 5's comment is now factually wrong. It reasons that codex rollouts aren't
claude-shaped so `claude --resume --fork-session` can't read them — true, but it concludes
fork is impossible, when codex has its own native fork.

Model validation is a sixth, smaller gate: both `resumeClosedSession` and `forkSession`
validate `opts.model` against `CLAUDE_MODELS` (`serve.ts:142`, `serve.ts:198`), which would
reject any codex model slug.

## What already exists and should be reused

- `codexThreads()` parses every rollout's `session_meta` head into `{id, path, cwd,
  createdAt, updatedAt, firstUserText}` — exactly the fields a resumable row needs.
- `codexRolloutFiles()`, `findCodexTranscriptById()`, and `resolveTranscript()` are already
  codex-aware, so transcript resolution for resume works today.
- `~/.codex/session_index.jsonl` is a ready-made index (`{id, thread_name, updated_at}`),
  a faster path than scanning every rollout head.
- The create-path bind-and-wait built on 2026-07-31 (14s budget + single-candidate
  fallback) is the pattern fork needs.

## Design

### Resume

Spawn `codex resume <sessionId> [prompt]` in tmux with the house flags
(`--sandbox danger-full-access --ask-for-approval never`), then **bind directly to the
id we asked for** — do not run the prompt-matching heuristic. We know the id; the rollout
already exists; resume appends to it.

Return the *same* sessionId as `newId`, with `resumed: true`. On the client this means
`remap(old, new)` is a no-op — the `guard old != new` added on 2026-07-31 already short
-circuits it — and the session's transcript, read state, and navigation are all unchanged.

`listResumable` must additionally enumerate codex rollouts and tag each row with its
agent, so the Closed browser can show and correctly route both families.

### Fork

Spawn `codex fork <sourceId> [prompt]`, then bind by scanning for the rollout whose
`session_meta.forked_from_id == sourceId` and whose `createdAt` is at/after the spawn.
This is an exact match, so fork does **not** need the prompt-matching heuristic or the
single-candidate ambiguity guard — even two forks of the same parent started seconds apart
are distinguishable, provided the scan also excludes already-claimed ids.

Budget the wait like create (~14s): a forked codex session writes `session_meta` at launch
but takes seconds to assemble context, and the client's POST times out at 20s.

Server returns the new id; the client navigates to the fork and leaves the original alone.

### The non-obvious risk

`pickCodexThread` filters candidate rollouts with `createdAt >= startedAt - 30s`
(`CODEX_BIND_SKEW_MS`). **A resumed session's rollout was created long ago**, so if resume
falls through to the normal binding path the skew filter rejects it and the session lands
with a null sessionId — reintroducing exactly the bug fixed on 2026-07-31.

Resume must therefore bypass `pickCodexThread` entirely and bind by known id. The same
applies to the periodic re-scan in `refreshWatchSet`/`listSessions`: a *running* resumed
codex process must keep resolving to its pre-existing rollout, which means the live-session
enumeration needs to prefer an explicit resume binding (e.g. recorded in the managed-session
registry at spawn time) over the proximity heuristic. This is the main piece of design work
and the most likely source of a subtle regression.

## Work items

**Server**
1. Teach `listResumable` to enumerate codex rollouts (reuse `codexThreads()` or the session
   index) and add an `agent` field to `ResumableSession`.
2. Branch `resumeClosedSession` on transcript family: claude → today's path; codex →
   `codex resume`, id-stable, bind by known id.
3. Same branch on the send-path revive (`serve.ts:2087`) so wake-up-on-send works.
4. Branch `forkSession`: codex → `codex fork`, bind via `forked_from_id`.
5. Record the intended binding (resumed id / forked-from id) in the managed registry at
   spawn so live enumeration doesn't re-derive it heuristically.
6. Relax the model allowlist per agent family in both lanes.

**iOS**
7. `canFork` to include the codex family; correct the stale comment.
8. Closed/resumable browser to show codex rows and route resume by agent.
9. Handle the id-stable resume response (`resumed: true` with an unchanged id) — verify
   nothing assumes an id change.

**Adjacent, already known**
10. The model picker offers codex models on codex sessions but `/model` returns 409
    (`serve.ts:2157`) — fix or hide while in this code.

## Verification

- Unit: binding tests for resume-by-known-id and fork-by-`forked_from_id`, including two
  forks of one parent, and a resumed rollout whose `createdAt` long predates the process
  (the skew-filter trap).
- Integration, against a live server: close a codex session → it appears in the resumable
  list → send to it → it revives under the **same** id with history intact. Fork a live
  codex session → new id, source's rollout byte-identical, fork replays history then
  diverges.
- Client: both flows driven from the iOS app on a simulator, since the create-path bug of
  2026-07-31 was only visible there.

## Open decisions

- **Fork a *closed* codex session?** `codex fork` reads a rollout, so it should work
  without reviving the parent. Worth supporting, but it's extra surface — confirm before
  building.
- **Does resume reuse the session's last model, as the claude path does**
  (`modelAliasForTranscript`)? Codex records `model_provider` in `session_meta`, but the
  model slug may need reading from elsewhere in the rollout.
