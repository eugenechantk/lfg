# Fork detail view: fix indefinite "Connecting to live transcript…"

**Status:** spec — ready to delegate
**Verified repro:** 2026-07-13, iOS sim (evidence: `.claude/feature/evidence-fork-verification/`)

## Problem

Forking works end-to-end, but `claude --resume <id> --fork-session` does not write
the fork's transcript file (`~/.claude/projects/<proj>/<newId>.jsonl`) until the
fork's **first turn completes**. In that window the client deep-links into the new
session and hits two server seams that both assume the transcript file exists:

1. `GET /api/sessions/:id/messages` (`serve.ts:1843`) — `resolveTranscript` returns
   null → **404** → client has no history → empty-state spinner.
2. `GET /api/live/stream` (`serve.ts:2084`) — sids whose transcript doesn't resolve
   at connect are **dropped from the pane list permanently**; the SSE never delivers
   for that sid even after the file appears.

Net effect: the fork's detail view shows "Connecting to live transcript…" forever
until the user blind-sends a first message. The comment in
`SessionDetailView.swift:376-378` ("its history is already copied server-side") is
wrong at navigation time.

## Fix shape

Server-side fallback + late-attach (all clients benefit: iOS, desktop, web), plus a
one-event client change. No change to how claude forks.

### 1. Record fork lineage at fork time (`serve.ts` `forkSession`, `managed.ts`)

- Before spawning, snapshot the **byte size of the source transcript**.
- After the pidfile resolves `newId`, patch the fork's managed record
  (`data/managed-sessions.json`, keyed by tmuxName) with three new optional fields:
  `sessionId` (the fork's id), `forkedFrom` (source id), `forkSourceBytes`
  (snapshot size). Persisting means the fallback survives a server restart.

### 2. `/messages` fallback: serve the fork-point snapshot of the source

In the messages handler, when `resolveTranscript(sid)` is null:

- Look up a managed record with `sessionId === sid` and a `forkedFrom`.
- If found, resolve the **source** transcript and serve messages from it, reading
  only the first `forkSourceBytes` bytes (drop any trailing partial line). This is
  exactly the history the fork copied; the cap prevents turns the source runs
  *after* the fork from leaking into the fork's view.
- Tag the response `forkPending: true` (informational; client may ignore).
- No record / source transcript gone → 404 exactly as today.

The byte snapshot can lag claude's own copy moment by a second or two; any
divergence is reconciled by the reset in (3) once the real file exists.

### 3. `/api/live/stream` late-attach: stop dropping unresolved sids

- **Entry gate (fork-only):** an unresolved sid goes into the pending set ONLY if
  a managed record with `sessionId === sid` and `forkedFrom` exists — i.e. it is a
  known fork awaiting its first-turn transcript. Every other unresolved sid
  (deleted transcript, garbage id, non-fork) is dropped exactly as today. This
  keeps the pending set from accumulating unrelated sessions by construction.
- **Retry cadence:** re-attempt `resolveTranscript` for pending sids on a slower
  timer (~2 s), not the 700 ms pump tick — each attempt is a filesystem scan of
  `~/.claude/projects`.
- **Lifecycle/cleanup:** the pending set is per-connection state (like the
  offsets map) and dies with the SSE connection; the client already churns and
  reopens this stream constantly as its watched-id set reranks, so nothing
  outlives a connection. A sid leaves the set the moment it attaches.
- When a pending sid's transcript appears: set its offset to the **current file
  size** (do not replay the file), move it to the active pane list, start
  busy/prompt/queue polling for it, and emit a new SSE control event:
  `event: reset`, `data: {sid}`.
- Setting offset to file-size + client refetch (below) sidesteps all duplicate-
  message reconciliation — the stream never replays copied history.

### 4. iOS client (minimal)

- `SessionStore` live-stream handler: on `reset {sid}` → call `loadHistory(sid)`
  **only if `transcripts[sid]` is non-empty** (i.e. the fork's detail view was
  opened during the fork window and is holding snapshot-fallback history —
  whether or not it is still on screen). Otherwise no-op: nothing stale is
  cached, and the detail view's `.task` (`SessionDetailView.swift:109`) already
  calls `loadHistory` on every open, which by then resolves the real fork file.
  Note the live stream is store-owned (one per host, 24-id cap,
  `SessionStore.swift:135`), so resets can arrive while the user is elsewhere —
  this gate is what keeps background resets free. Unknown/unwatched sids: ignore.
- Fix the stale comment in `SessionDetailView.swift:376-378`.
- Optional polish: if messages are empty AND the session is a fresh fork, show
  "Starting branch…" instead of "Connecting to live transcript…". With (2) in
  place history should render immediately, so this is a degraded-path nicety only.

Desktop client: out of scope here; it inherits (2) and (3) automatically, `reset`
handling can follow later.

## Why the snapshot→real-file handoff cannot duplicate messages

Verified against the 2026-07-13 fork pair (`48bf8358` → `9f7597da`): every
uuid-bearing conversation entry (user/assistant/system) in the source is copied
into the fork transcript **with its uuid preserved**; the only new uuids are the
fork's own new turns. (The entry-count difference between the files is metadata
line types — `mode`, `bridge-session`, `last-prompt`, etc. — which carry no uuid
and aren't rendered as messages.)

On the client, message identity is `stableID` (`Models.swift:112`) = the entry
uuid when present, and history loads go through `ensureHistory`
(`SessionStore.swift:1202`), which **merges by stableID** into the existing
array rather than appending. So the sequence is:

1. Snapshot-served history renders (uuids A, B, C — read from the source file).
2. `reset` fires → client refetches `/messages`, which now reads the fork file:
   same A, B, C plus new turn D. Merge upserts A/B/C in place, adds D.
3. Live deltas after attach are only bytes written after the attach offset (E,
   F, …) — the stream never re-sends history.

No step introduces a second copy of any entry.

## Success criteria

1. Fork an **idle** claude session from iOS → detail view renders the full copied
   history within ~2 s of navigation, **before any message is sent**.
2. Send the first message to the fork → history stays, the new turn streams live,
   **no duplicated messages** after the reset/reload.
3. Fork a **busy** (mid-turn) session → fork view shows only turns flushed at fork
   time; turns the source completes after the fork never appear in the fork view.
4. Restart the lfg server inside the fork window (fork created, no first turn) →
   reopening the fork still renders snapshot history.
5. Regressions: non-fork sessions stream exactly as before; `/messages` for an
   unknown id still 404s; a fork whose source transcript was deleted degrades to
   today's spinner (no crash, no wrong-session content).
6. Unit tests (`bun test`): managed-record lineage persistence; snapshot-capped
   message read (incl. truncated-final-line handling); stream pending→attach emits
   `reset` and does not replay the file.

## Verification plan

- Unit suite per criterion 6.
- LIVE E2E on the session simulator (criteria 1–3): repeat the 2026-07-13 manual
  run — fork idle session, screenshot pre-first-message history; send message,
  screenshot no-dupes; fork this working session itself for the busy case.
- Criterion 4 via curl against a restarted dev server on a scratch port (not the
  long-lived :8766 process).

## Files

- `src/commands/serve.ts` — forkSession lineage patch; messages fallback; stream
  pending set + reset event
- `src/managed.ts` — optional fields on `ManagedSession`
- `src/sessions.ts` — snapshot-capped transcript read helper (near
  `recentMessages`/`messagePage`)
- `ios/LFG/SessionStore.swift` — handle `reset` SSE event
- `ios/LFG/SessionDetailView.swift` — comment fix, optional empty-state copy
- tests: `src/*.test.ts` alongside touched modules
