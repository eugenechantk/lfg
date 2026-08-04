# How `closed` is derived — analysis

Companion to `.claude/feature/hook-driven-session-state.md`. `closed` is the one tier
of the state ladder that layers 1–3 do not touch, and it is derived on a different
epistemic basis from every other state.

## The derivation today

Two stages, both **absence-based**.

**Stage 1 — server, `listResumable` (`src/sessions.ts:1604`).** Enumerate transcripts
on disk, exclude the ids that are live *on this host*, stamp `closed: true` on the rest.
The field's own doc comment is careful about scope: read it as *"closed here"*.

**Stage 2 — client, `MultiHost.reconcileResumable` (`ios/LFGCore/.../MultiHost.swift:64`).**
Dedupe by `sessionId` across hosts, then drop any id that is live on *any* host. The
result becomes `closedCache`, and `sessions = fresh + optimistic + closed`
(`SessionStore.swift:1519-1521`).

So, reduced to one line:

> **`closed` ≡ a transcript exists on disk and nothing currently claims the session is alive.**

That is the *absence of a positive signal* — epistemically identical to the pane scrape
we just spent this whole effort replacing ("I didn't see `esc to interrupt`, so it must
be idle"). Every other tier now rests on something the agent asserted; `closed` still
rests on nobody having said otherwise.

## Why the scope split is correct

The server genuinely cannot decide this alone, and the reason is worth preserving:
`~/.claude/projects` is **synced** between hosts, and a server has no peer awareness
(hosts are client-side config). So host B enumerates host A's transcripts and would
happily call A's *running* session closed. Only a client, which polls every host, holds
the cross-host live set. That filter cannot move server-side without giving servers peer
awareness. This part of the design is right and should not be "simplified".

## Failure modes that follow structurally

**1. A host going offline marks its running sessions closed.** This is the important one.
`SessionStore.swift:1504` correctly refuses to read closed pages *from* a down host
(`okHosts` filter) — but that does not help, because the transcripts are synced: the
**live** peer enumerates the **down** host's transcripts and stamps them closed, and the
down host's live ids are (by definition) missing from `liveIds`, so nothing contradicts
it. A dozen sessions still running on the unreachable machine render as ended.

This is the same shape as memory `offline-host-read-routing` and is the mechanism behind
sessions "disappearing" when a host drops.

**2. It cannot distinguish why a session is absent.** Deliberately exited, crashed, host
unreachable, `/clear` rolling the id over inside a still-running process, or simply not
enumerated yet — all produce identical evidence. The UI presents all of them as "closed".

**3. Startup race.** A session whose transcript exists but which has not yet been
enumerated as live reads closed for the intervening poll.

## What the hook layer now makes available

`SessionEnd` is a **positive assertion** that a specific session id terminated, and it
carries `reason` — captured as of this session's change to `scripts/lfg-agent-hook.py`,
verified against a live run:

```
  hook_event_name   SessionEnd
  reason            other
  session_id        b28543c7-0e48-4716-979c-066ec6732ded
  transcript_path   /Users/eugenechan/.claude/projects/…/b28543c7-….jsonl
  cwd               /private/tmp/endprobe/wd
```

`reason` separates the cases absence cannot:

| reason | meaning for `closed` |
| --- | --- |
| `prompt_input_exit`, `logout`, `other` | genuinely gone → closed |
| `clear`, `resume` | id rolled over inside a live process → **not** a dead host |
| *(no record at all)* | no assertion — fall through to the absence inference |

Crucially, **an unreachable host produces no `SessionEnd`.** So a hook-first `closed`
abstains exactly where the current derivation is most confidently wrong.

## Proposed layering (mirrors what busy now does)

1. **Hook `SessionEnd` with a terminal `reason`** → closed. Positive, host-local,
   authoritative for sessions that have hooks.
2. **Absence inference** (today's two-stage derivation) → fallback, unchanged.
3. **Guard:** do not let absence alone close a session whose owning host is not
   currently reachable. Today the peer's synced enumeration silently overrides that.

Same invariant as the busy stack: a layer may add certainty, never silently manufacture
a terminal state. Note the direction of the asymmetry — for `busy`, the dangerous error
was latching **running**; for `closed`, it is asserting **ended** about a session that is
alive on a machine you merely cannot reach.

## CORRECTION — what `closed` is actually for

The framing above ("absence-based, epistemically weak like the pane scrape") overstates
the problem, and the reason is the feature's PURPOSE:

> `closed` exists so that closing a tmux session does not make the conversation
> disappear — the transcript outlives the process and can be relaunched on demand.

For that purpose **absence is the correct question.** "No live process owns this
transcript" is not an inference about what an agent is doing; it is a fact about process
ownership, and it is exactly the precondition `claude --resume` requires. This is
unlike `busy`, where absence-of-evidence was standing in for a state the agent could
have asserted directly.

The round trip already exists and is more careful than the analysis above assumed:

| Capability | Where |
| --- | --- |
| Closed session stays visible | `listResumable` reads transcripts, stamps `closed` |
| Relaunch in a fresh tmux pane | `POST /api/sessions/resume` → `claude --resume <id>` |
| Send to a reaped session auto-resumes it | `resumeClosedSession`, shared path |
| Don't double-spawn on THIS host | `listSessions()` check → `alreadyLive` |
| Don't double-spawn across hosts | **lease file** (`leases.ts`, `foreignFresh`) → 409 |
| Old row disappears after resume | `resumedIds` in `MultiHost.reconcileSessionList` |

The cross-host case — the one flagged as the serious failure above — is guarded by a
LEASE (hostId + freshness, synced alongside the transcript), not by peer polling. That
is the right mechanism for synced storage, and it means the dangerous outcome (two live
processes writing one transcript) is already prevented. The residual offline-host
problem is **display-only**: a down host's running sessions render as closed on its
peer. Annoying, not corrupting.

## Where hooks actually help, given that purpose

Not "replace the derivation" — it is sound. Four concrete gaps:

1. **Tell a real close from an id rollover.** `/clear` ends the old session id inside a
   still-running pane. Today that old id becomes a resumable row, and resuming it spawns
   a second pane for a conversation you deliberately cleared. `reason: "clear"` names it.
2. **Latency.** `closed` currently appears only once `listResumable` re-enumerates and
   the id drops out of the live set. `SessionEnd` fires the moment the session exits, so
   closing a tmux pane could reflect immediately instead of on the next poll.
3. **Deliberate close vs crash.** Identical evidence today. `prompt_input_exit` vs
   `other`-with-no-record separates "you closed this" from "this died", which is exactly
   the context you want when deciding whether to resume.
4. **Suppress the display-only offline-host phantom.** An unreachable host emits no
   `SessionEnd`, so a hook-first rule abstains rather than asserting closed.

## How to reconcile it — ONE rule

Earlier drafts of this section stacked signals (polled liveness + lease + hook events).
That was the same mistake the `busy` ladder made. There is one rule:

> ### `closed` ≡ there is no fresh lease.

One reader, agent-agnostic, host-agnostic. Everything else is a WRITER that keeps the
lease honest.

### Why the lease and not Claude Code's own registry

Claude Code maintains `~/.claude/sessions/<pid>.json` — richer than our lease
(`pid`, `procStart`, `cwd`, `status`, `version`) and maintained by Claude Code itself.
It is the better evidence. It cannot be the mechanism, for two measured reasons:

1. **Codex has no equivalent.** `~/.codex/thread-writer-locks/` holds only a 0-byte
   `.coordination.lock`; no per-session file appears while a codex session runs.
   (`state_5.sqlite` is unexplored.)
2. **It is host-local.** No `hostId`/hostname in its key set, and `~/.claude/sessions/`
   carries 0 sync-conflict files while `~/.claude/` root carries 12 — it does not sync.
   A peer's pid checked against local pids would be meaningless.

So the registry becomes the best INPUT for claude sessions, and the lease stays the
common currency both agents and both hosts can read.

### Write side — one path, fed by the best evidence available per agent

Driven by the same local enumeration that already produces `listSessions`, so a session
cannot be missed by forgetting to acquire:

| agent | liveness evidence | lease action |
| --- | --- | --- |
| claude | `~/.claude/sessions/<pid>.json`: pid alive AND `procStart` matches | acquire/renew |
| codex | process + pane liveness (today's check) | acquire/renew |
| both | hook `SessionEnd` with a terminal `reason` | `releaseLease` → immediate |
| both | explicit close | `releaseLease` (already wired, `serve.ts:2344`) |
| both | host dies or goes unreachable | heartbeat stops → expires in 90s |

The hook release is agent-agnostic — both Claude Code and codex emit `SessionEnd` with
`reason`, verified this session. So the immediacy win applies to both without branching.

`procStart` is what makes the claude path trustworthy: it defeats pid recycling, the
exact failure that had `lfg-5c7ed4` reading "running" for 25 days.

### What this buys

- **One reader.** `closed` is a single predicate; no per-agent branching at the read site.
- **Cross-host for free**, because the lease is in the synced tree and carries `hostId` —
  the peer awareness the repo CLAUDE.md says servers cannot otherwise have.
- **No acquire-on-first-sight bug.** The writer projects from enumeration rather than
  remembering to acquire, so the 7-of-16 gap cannot recur.
- **One clock.** `LEASE_FRESH_MS` (90s), the same constant `foreignFresh` already uses to
  gate resume — display and safety can no longer disagree about whether a session is
  takeable.

### Failure direction

A missing lease on a host whose lfg server is DOWN will expire and read closed. That is
acceptable: lfg cannot drive those sessions anyway. But the write path must be robust
enough that a leaseless-yet-running session never happens on a HEALTHY host — that is the
dangerous direction (hiding a live agent and offering a resume that would double-spawn).
Driving the writer from enumeration, rather than from spawn events, is what secures it.

### Build order

1. Lease writer driven by enumeration, both agents, with a test that every session in
   `listSessions` ends up leased.
2. Switch the reader to `closed ≡ no fresh lease`; `MultiHost.reconcileResumable`
   degenerates to a dedupe.
3. Hook `SessionEnd` → `releaseLease` for immediacy, and `reason: clear|resume` to
   suppress the rolled-over id entirely.

## Built this session — the shared record

**Superseded decision.** `.claude/feature/hook-driven-session-state.md` Phase 1 put hook
state in `~/.lfg/agent-state/<sid>.json`, arguing the hook "must not depend on the server
being up". That reasoning was right, the location was wrong: the LEASE path is equally
server-independent AND lives in the synced tree, so hook-written state crosses hosts. The
hook's payload already carries `session_id` + `transcript_path`, which is exactly
`leasePathForTranscript`'s input — no server, no config, no lookup.

**The bug this nearly shipped with.** `renewLease` read-modify-writes through
`parseLease`, which rebuilt a bare 4-field record. Every heartbeat — every tick — would
have silently erased hook-written state, and only in production where both writers run.
`parseLease` now carries hook fields through, and validates them loosely so a malformed
value from the other writer cannot invalidate LIVENESS (liveness gates resume).

**Field ownership**

| writer | fields | mechanism |
| --- | --- | --- |
| lfg (`leases.ts`) | `hostId`, `pid`, `acquiredAt`, `heartbeatAt` | atomic RMW, preserves hook fields |
| hook (`lfg-agent-hook.py`) | `state`, `stateAt`, `stateEvent`, `endReason` | atomic RMW, preserves lfg fields |

**Verified**

- `bun test` → **273 pass / 0 fail**, `tsc` clean. Includes a regression test that
  `renewLease` preserves hook state while advancing the heartbeat — the one that would
  have caught the destroyer.
- 6 new tests drive the REAL hook script against a real lease, covering the merge, the
  no-lease-yet case, and the no-transcript fallback.
- **Live:** a real Claude session wrote its own lease next to its transcript —
  `{"state":"ended","stateAt":…,"stateEvent":"SessionEnd","endReason":"other"}`.
- **Live co-writer:** firing the hook at a running session's real lease added
  `state: running` while `hostId`, `pid` and `heartbeatAt` survived untouched.

**NOT verified — deploy gap.** The running server (started Aug 4 19:27:35) predates the
`parseLease` fix (Aug 5 02:41), so it still holds the record-stripping version. Whether
an lfg heartbeat preserves hook state in production is proven by unit test but not yet
observed live; it needs a `serve` restart. Until then the old server will strip `state`
on its next renew of any lease a hook has written.

### RESOLVED — codex lease keying (this session)

Fixed by deriving the lease filename from the TRANSCRIPT rather than from lfg's session
key: `sessionIdForTranscript` reads the id off the file both parties already agree on
(`<uuid>.jsonl` for claude, `rollout-<ts>-<uuid>.jsonl` for codex, anchored to the end so
a rollout's timestamp can't be mistaken for the id). Identical for claude; convergent for
codex; falls back to the session id for an unparseable name.

Proved against a REAL codex session, not fixtures — the hook wrote the file, then lfg's
reader was given a DIFFERENT session id and asked where to look:

```
transcript id  : 019fce1d-71c4-7d72-a3d1-654c8ae63f3f
lfg session id : 3f8dfe1e-2ff0-4a1b-9c3d-aaaaaaaaaaaa
reader resolves: …/019fce1d-….lease.json
hook wrote     : …/019fce1d-….lease.json
CONVERGE       : true | file exists: true
```

Six new unit tests cover the derivation and the convergence. Full suite **279 pass**.

### (historical) the gap this replaced — codex keyed the lease filename differently

The lease encompasses the state store's function for CLAUDE sessions (verified live).
For codex it does not yet, and the reason is an id mismatch, not a missing field:

```
lfg   sessionId = 3f8dfe1e-…   ← what acquireLease/hookState key the filename on
codex threadId  = 019f03aa-…   ← what the codex hook sees as its own session_id
```

`resolveTranscript` already maps lfg's sessionId → threadId to FIND a codex rollout, but
`leasePathForTranscript(sessionId, …)` is still handed lfg's sessionId. So for one codex
session the hook writes `<threadId>.lease.json` while lfg reads `<sessionId>.lease.json`
— two files in the same directory, and the hook's state is never found.

**Fix:** key the lease filename on the TRANSCRIPT's id, for both agents. The lease path
is already derived from the transcript; its name should be too. Identical for claude
(the ids are the same), correct for codex. Existing codex leases orphan and expire.

**Also unconfirmed:** the `~/.lfg/agent-state/` fallback exists for payloads lacking
`transcript_path`. Every payload observed so far carries one, so that branch may be dead
code. It should be either exercised by a real case or deleted — not left as untested
insurance.

## Built: items 2–4

**2. Enumeration-driven lease writer.** `ensureLease(sessionId, pid)` replaces the
`renewLease` call in serve.ts's loop. `renewLease` no-opped unless the lease was already
ours, so adopted sessions never got one (7 of 16). `ensureLease` renews ours, acquires
when absent or stale, and **refuses to steal a fresh foreign lease** — the mutual
exclusion the lease exists for. `acquireLease` also had the record-stripping bug and now
preserves hook fields across a takeover. The boot delay dropped 30s → 1s so there is no
window where a live session has no lease. 5 new tests.

**3. Reader switched to the lease.** `listResumable` asked `foreignFreshAt` (is a PEER on
it) and leaned on `excludeIds` for local liveness. It now asks `anyFreshAt` — is ANY host
on it — which is the single definition: **closed ≡ no fresh lease**.

**4. `SessionEnd` releases.** A terminal reason unlinks the lease, so `closed` resolves
immediately instead of after the 90s window — using the one rule rather than adding a
second thing to check. `clear`/`resume` deliberately do NOT release: those roll the id
over inside a process that is still alive, and releasing would report a running agent as
closed. 3 new tests.

Full suite **286 pass / 0 fail**, `tsc` clean.

### `excludeIds` removed — one way, made safe rather than merely tidy

First attempt at removing it broke a real invariant, so the second attempt fixed the
cause instead of restoring the second reader: **`listResumable` now guarantees its own
precondition.** Before filtering it enumerates live sessions and makes each lease
current, so "a live session is never returned as closed" no longer depends on a
background loop having run. The parameter is gone from the signature and from serve.ts.

That is the whole point — one input, and the read is responsible for that input being
true. Not hot: this backs the resumable page, not the session list.

Both tests were rewritten to assert the invariant through the ONE mechanism, in both
directions: a session with a fresh lease is never returned as closed, and one whose lease
has gone stale IS. The pagination test now excludes its session by writing a lease rather
than by passing an id.

**Live verification**

```
live sessions          : 16
resumable rows returned: 60
LIVE SESSIONS LEAKED AS CLOSED: 0 (none)

live sessions with a FRESH lease: 15   stale: 0   missing: 2   (was 7 of 16 leased)
```

The 2 without a lease have no resolvable transcript. That is not a hole: the lease path
is derived from the transcript, and `listResumable` enumerates transcripts — a session
with none is never a candidate, so it cannot be returned as closed either.

Full suite **287 pass / 0 fail**, `tsc` clean.

### (historical) the first attempt, and why it failed

To make the reader literally singular I removed the `exclude.has(id)` checks. Two tests
went red — `listResumable closed flag > a live session is never returned as closed` and
the pagination test — and they were right. Without `exclude`, that invariant holds only
if the lease-writer loop has already run, and the failure direction is the bad one:
hiding a LIVE agent and offering a resume that would double-spawn.

Reverted. The honest framing is that `exclude` is not a competing ANSWER — it is the same
fact as the lease, read synchronously and for free on the host that owns the session,
while the lease carries it to hosts that cannot see the process. One rule, two scopes,
one of which has a free local source. Collapsing further would trade a real safety
property for tidiness.

## Agent coverage — VERIFIED, and one real gap

| capability | Claude Code | codex |
| --- | --- | --- |
| Layer 1 hooks → turn state | ✅ live | ❌ **inert — no trusted_hash** |
| Layer 2 transcript → turn state | ✅ `turn_duration` | ✅ `task_started`/`task_complete`/`turn_aborted` |
| Layer 3 pane fallback | ✅ | partial (different TUI chrome) |
| `ensureLease` liveness | ✅ | ✅ (lfg-driven, agent-agnostic) |
| Lease path convergence | ✅ | ✅ proved on a real rollout |
| `SessionEnd` → immediate release | ✅ | ❌ falls back to the 90s expiry |
| Display ladder | ✅ | ✅ agent-agnostic |

**The gap, measured.** Every codex hook verification in this work passed
`--dangerously-bypass-hook-trust`. Run WITHOUT it, codex completes normally (exit 0,
rollout written) and **no hook fires** — no lease, no state. `~/.codex/config.toml`
confirms why: `[hooks.state]` carries `trusted_hash` entries only for `pre_tool_use` and
`post_tool_use` (atuin, flowdeck guard). The three entries the installer added have none.

So in production today codex gets: transcript-derived turn state (which is actually
STRONGER than claude's — an interrupted turn writes `turn_aborted` instead of leaving the
turn to look open), lease-based `closed` via lfg's enumeration, and close detection
bounded by the 90s lease window rather than immediate.

**FIXED (option 2).** `--dangerously-bypass-hook-trust` is now passed from both places a
codex session can start, so hand-started and lfg-started sessions behave identically:

- `managedCodexSessionArgv` (src/tmux.ts) — covers create AND resume; 2 tests pin it.
- `codexy` in `~/.zshrc` — the source is home-manager (`~/.zshrc` is a read-only nix
  symlink), so the edit went to `dev/dotfiles/home-manager/home.nix` and was applied with
  `nix run home-manager/release-24.05 -- switch --flake ./home-manager#home`
  (generation 12). Verified in the regenerated file.

Trusting these is defensible precisely because lfg AUTHORED the hook file being trusted.

**Verified live, production config, no CODEX_HOME override:**

```
hook: UserPromptSubmit
hook: Stop
→ 019fce33-….lease.json  next to  rollout-2026-08-05T03-15-31-019fce33-….jsonl
  {"state":"ended","stateAt":…,"stateEvent":"SessionEnd","endReason":"other"}
```

So the codex column above now matches the claude column on every row.

## Status

Analysis + reconciliation design. No behavior change — no behavior change. The `reason` capture in the hook (tested,
reinstalled to `~/.lfg/bin`) is the groundwork; none of the four items above are built.
