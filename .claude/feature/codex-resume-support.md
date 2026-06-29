# Scope: Codex resume support (list + wake-up resume)

**Status:** Scoping
**Tier:** Product (shipping server + iOS app)
**Author:** session 2026-06-29

## Goal

Make reaped **codex** sessions first-class alongside claude: list them in the
resumable set, and resume them (the wake-up-on-send flow + an eventual "Closed"
browser) so a send to a closed codex session revives the conversation — same
muted → blue UX the claude path already has.

## Current state (claude-only)

Two hard gates, both Claude-specific:

1. **Listing** — `listResumable` (`src/sessions.ts:1215`) scans only
   `~/.claude/projects` (`PROJECTS_DIR`, line 28). Codex rollouts under
   `~/.codex/sessions/**` are never read. `ResumableSession` has no `agent` field.
2. **Resuming** — `resumeClosedSession` (`src/commands/serve.ts:~100`) rejects any
   transcript not under `/.claude/projects/` with *"only claude sessions can be
   resumed"* (line 121; the send-path gate at line 1431). It drives
   `claude --resume <id>`.

## What already exists for codex (reuse, don't rebuild)

The read side is largely done:

- **`codexThreads()`** (`src/sessions.ts:328`) parses every rollout's
  `session_meta` head line into `{ id, path, cwd, createdAt, updatedAt,
  firstUserText }` — exactly the fields a resumable row needs.
- **`codexRolloutFiles()`**, **`CODEX_SESSIONS_DIR`**, **`findCodexTranscriptById()`**.
- **`resolveTranscript()`** (`src/sessions.ts`) already falls back to
  `findCodexTranscriptById` — so transcript resolution for resume is codex-aware today.
- **`~/.codex/session_index.jsonl`** — a ready-made index (`{id, thread_name,
  updated_at}` per line), an optional fast path vs. scanning every rollout head.
- Rollouts live at `~/.codex/sessions/{YYYY}/{MM}/{DD}/rollout-{ts}-{uuid}.jsonl`;
  the `uuid` is the codex session id, also in `session_meta.payload.id`, with cwd
  in `payload.cwd`.

The CLI supports resume natively:

- **`codex resume <SESSION_ID> [PROMPT]`** — resume by UUID with an optional
  kickoff prompt (mirrors `claude --resume <id> -- <prompt>`).
- Accepts the flags lfg needs: `-s/--sandbox`, `-C/--cd`, `--add-dir`,
  `-m/--model`, and `--dangerously-bypass-approvals-and-sandbox` (the combined
  no-approval/no-sandbox posture matching `spawnManagedCodexSession`).

## Design

### A. Listing (`listResumable` + `/api/sessions/resumable`)

- Add `agent: "claude" | "codex"` to `ResumableSession` (server type + iOS
  `ResumableSession` model).
- After collecting claude candidates, also pull codex threads (via
  `codexThreads()` or the `session_index.jsonl` fast path), exclude live ids
  (already-running codex threads, codex-aisdk reserved ids), map each to a
  `ResumableSession` with `agent:"codex"`, title = `thread_name`/`firstUserText`,
  `lastActivityAt = updatedAt`.
- Merge claude + codex, sort by `lastActivityAt` desc, apply `limit`.
- Tag existing claude rows `agent:"claude"`.

### B. Resume (`resumeClosedSession`)

- Replace the claude-only transcript gate with an **agent branch** keyed off the
  resolved transcript path: `/.claude/projects/` → claude; `/.codex/sessions/` →
  codex. (`resolveTranscript` already returns the codex path.)
- **Claude branch:** unchanged (`spawnManagedSession` with `resume`, pidfile →
  new id).
- **Codex branch:** new spawn that runs
  `codex resume <id> [prompt] --cd <cwd> --add-dir <root>
  --dangerously-bypass-approvals-and-sandbox [--model <m>]` in a managed tmux
  pane. Add a `resume?: string` arg to `spawnManagedCodexSession` (or a sibling
  `spawnResumedCodexSession`).
  - cwd comes from the codex thread (`codexThreads().cwd`), not
    `cwdForTranscript` (which reads claude's per-line `cwd`; codex keeps it in
    `session_meta.payload.cwd`). Add `cwdForCodexRollout()` or read it off the
    already-loaded thread.
  - Register in the managed registry with `agent:"codex"`.
- **Resolve the live id:** trivial — codex resume is **id-stable** (verified
  below), so the live id IS the input id. After spawn, just confirm the running
  codex proc is bound to that id (the existing `listSessions` cmd-line
  `resume <uuid>` match), then return the SAME id. No new-id/pidfile dance.
- Open the **send-path gate** (`serve.ts:1431`) to also accept codex transcripts.

### C. iOS

- `ResumableSession` gains `agent`. The wake-up muted→blue UI needs **no
  change** — it keys off the server's `resumed:true`, agent-agnostic.
- (When the "Closed" browser lands) each row shows an agent badge; tapping a
  codex row opens detail and sends → codex resume.

## Verified behavior (test run 2026-06-29)

Tested with `codex exec resume <id> "<prompt>"` (codex v0.141.0) against a fresh
throwaway session:

- ✅ **Id is STABLE on resume.** `codex resume <id>` continues under the SAME
  session id and **appends to the same rollout file** — it does NOT fork a new id
  like claude's `--resume`. (Confirmed: one rollout file, both turns present, same
  uuid reported by the resumed proc.)
- ✅ **Full memory continuity** — the resumed session recalled the codeword set in
  the original turn.
- **Implication — simpler than claude:** `resumeClosedSession`'s codex branch can
  **return the input id unchanged** — no pidfile poll, no new-id resolution. The
  iOS `applyResume`/`remap` is already a no-op when `new == old`, so the client
  needs zero codex-specific re-pointing.
- **Flag placement:** for `codex exec resume`, global flags
  (`--dangerously-bypass-approvals-and-sandbox`) go BEFORE the `resume`
  subcommand; `exec resume` does NOT accept `--cd` (inherits process cwd). The
  **interactive** `codex resume <id> [prompt]` (what lfg's tmux path uses) DOES
  accept `--cd`/`--sandbox`/`--add-dir` per its `--help`.

## Open questions — verify before/while building

1. **Interactive (tmux) parity:** the test used `codex exec resume`; lfg spawns
   the interactive `codex resume <id> <prompt>` in a tmux pane. Confirm the
   interactive path is also id-stable (almost certainly — same resume engine) and
   that `listSessions` binds the running proc to the id via its cmd-line
   `resume <uuid>` (the existing `(?:resume|fork)\s+(UUID)` match). Since the id
   is stable, "resolve the new live id" reduces to "confirm the same id is live."
2. **Flag posture:** confirm interactive `codex resume` with
   `--dangerously-bypass-approvals-and-sandbox` behaves like the fresh-spawn
   `--sandbox danger-full-access --ask-for-approval never` (the resume subcommand
   lacks `--ask-for-approval`).
4. **codex-aisdk vs. tmux codex:** resuming should target the **tmux codex TUI**
   path (interactive), not the codex-aisdk headless harness. Make sure reserved
   codex-aisdk threadIds are excluded from the resumable list (the
   `claimedCodex` set already does this in `listSessions`).

## Risks

- Codex CLI version drift (`cli_version` in rollouts spans 0.128.x): resume flag
  names could change across versions — pin behavior to the installed `codexBin()`.
- Title quality: some rollouts have no `thread_name`/first user text → fall back
  to cwd basename (claude path already does this).
- Performance: scanning all rollout heads is O(files); prefer
  `session_index.jsonl` for the list and only read a rollout head when needed.

## Phasing

- **P1 — Listing:** `agent` field + codex rows in `listResumable`. Low risk,
  immediately visible via the API and the future browser. No resume yet.
- **P2 — Resume:** codex branch in `resumeClosedSession` + codex resume spawn +
  live-id resolution + open the send gate. The load-bearing piece.
- **P3 — Browser UI:** the shared "Closed sessions" list (separate feature) with
  agent badges; codex rides the `agent` field for free.

## Test plan (real seams, per memory)

- **List:** create a codex tmux session, reap its pane, confirm it appears in
  `/api/sessions/resumable` with `agent:"codex"` and correct title/cwd.
- **Resume (the real seam — don't mock the CLI):** from a reaped codex session,
  POST `/send`; confirm `codex resume` actually spawns, the conversation
  continues (prior context present), the returned id is live, and the iOS bubble
  goes muted → blue. Verify in the simulator (open codex session → reap → send).
- **Negative:** codex-aisdk and opencode closed sessions still 404 on resume
  (out of scope) with a clear message.
