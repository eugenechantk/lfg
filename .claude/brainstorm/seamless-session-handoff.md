# What makes a seamless session handoff possible

*Goal: work on a Claude Code session continuously, moving it from Mac A to Mac B
with no loss of context. This doc outlines the properties that make that
possible — the "why it works," not the build steps.*

## The one principle

**A session's durable state is separable from the host it happens to run on.**

Every session is made of two halves:

| Half | What it is | Lifetime | Portable? |
| --- | --- | --- | --- |
| **Durable state** | the transcript JSONL + the working directory (repo files) | survives the process | ✅ this *is* the session |
| **Ephemeral state** | the running `claude` process, its tmux pane, pid, lfg's managed-session bookkeeping | dies with the process/host | ❌ reconstructed, never moved |

Seamless handoff works when the **durable half is made identical on both hosts**
and the **ephemeral half is reconstructable from it on demand**. Everything below
is a consequence of that split.

## The five enablers

### 1. The session is the transcript, not the process
Claude Code streams every turn to a durable file
(`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`) *as it goes*. The live
process is disposable — kill it and the conversation is fully preserved on disk.
This is what makes a session a *thing you can move* rather than a *process you'd
have to migrate*. You never migrate a running process across machines (hard);
you re-create one from a file (easy).

### 2. The transcript is self-describing
The JSONL records everything a resume needs — the full history, the model, and
crucially the **cwd**. So reconstructing the live agent requires no external
manifest: `resumeClosedSession` (serve.ts:104) reads the transcript, discovers
the cwd from it (`cwdForTranscript`), and relaunches there. The session carries
its own resume instructions.

### 3. Resume is a first-class primitive
`claude --resume <id>` rebuilds the live agent from the transcript, and lfg
already wraps it as an endpoint (`POST /api/sessions/resume`) plus an
auto-resume-on-send path. So "make this session live on this host" is a solved,
one-call operation. Handoff doesn't need new backend machinery — it *composes*
an existing primitive.

### 4. The two durable dependencies are identical on both hosts
Resume needs exactly two things present on the target: the **transcript** and the
**repo at the same absolute path**. A synced filesystem provides both for free —
the transcript under `~/.claude/projects` and the repo under its path are byte-
identical on Mac B the moment they're written on Mac A.
**Identical paths are load-bearing**, not a convenience: the project-dir name is
derived from the cwd (`cwd.replace(/[/.]/g,"-")`), and every tool/file reference
in the transcript is an absolute path. Same username + same repo location = the
encoding matches and every path in the history still resolves. Divergent paths
would require rewriting the transcript — the thing that would make it *not*
seamless.

### 5. The client is a stateless controller, not a state owner
The iOS app doesn't *hold* the session — `SessionStore` reduces server snapshots
+ SSE into a view; the source of truth is always host-side. Because the client
owns no authoritative state, it can re-point at a different host and immediately
see the same session (the durable state is shared/synced). The phone becomes a
*remote control* that can be aimed at whichever Mac should currently run the
work. Nothing has to "transfer through" the phone.

## The one thing sync does NOT give you for free — and why it matters

Enablers 1–5 make the *transfer* nearly free. But a whole-FS sync also drags
along the **ephemeral half**, which must stay host-local:

- lfg's runtime state lives at `<lfg-repo>/data` (config.ts:8) —
  `managed-sessions.json`, pidfiles, `sendq.log`. If both Macs run `lfg serve`
  over a synced tree, they write the same files concurrently → sync conflict
  copies / last-writer-wins corruption.
- pids and tmux pane names are meaningful only on the host that created them.

Two properties keep this mostly contained today, and one fix closes the rest:

- The **live** list is `pgrep`-based — each server sees only its *own* running
  processes, so a synced managed-file full of the other Mac's entries doesn't
  produce fake-live sessions.
- The **resumable** list is transcript-based — so both Macs correctly see the
  same resumable pool (exactly what handoff wants).
- **Fix:** make `data/` host-specific (`join(ROOT,"data",hostname())` or a
  `LFG_DATA_DIR` override) so two servers on a synced tree never write the same
  bookkeeping files. This is the boundary that keeps the ephemeral half from
  leaking across the sync.

## The mental model in one line

> **Sync the durable half (transcript + repo, identical paths); isolate the
> ephemeral half (pids + bookkeeping, per-host); resume rebuilds the live agent
> on whichever host you point the phone at.**

Continuous work across Macs falls out of those three clauses. Handoff = end the
process on A (clean, one writer), then resume on B (the durable state is already
there).

## Requirements checklist for "seamless"

- [ ] Whole-FS sync covers `~/.claude/projects` **and** the repo (durable state).
- [ ] Identical absolute paths on both Macs (same username, same repo location).
- [ ] `data/` isolated per-host so two servers don't clobber bookkeeping.
- [ ] Clean handoff (one live writer to a transcript at a time — no dual-live).
- [ ] Client can target either host and call resume (the UI feature).
