# Diagnosis — "messages can't be sent to idle sessions"

## Symptom
Sending a message to an idle session hangs (UI stuck on the muted/"resuming…"
bubble) and never confirms. A new message does not kickstart the session.

## Root cause: `listSessions()` blocks the single Bun event loop for seconds

The server is one event loop (see project CLAUDE.md). **Every** mutating route —
`POST /api/sessions/:id/send`, `/resume`, `/model` — calls `await listSessions()`
to find the target. The send path *depends* on it (serve.ts:1419).

`listSessions()` enriches every live agent proc using **synchronous** subprocess
spawns (`Bun.spawnSync` → `ps`, `lsof`, `tmux`). `spawnSync` blocks the event
loop, so while one `listSessions()` runs, **no other HTTP request is serviced** —
including the send. The iOS client's 20s POST / 15s GET timeouts get hit under
contention, so the send appears to hang forever.

### Measured
- `/api/sessions` latency: **2.2s, 11s, 13s** across three back-to-back calls
  (highly variable → event-loop contention between overlapping requests).
- Live host: **38 sessions, 41 claude procs, 13 codex procs, 37 tmux panes.**

### The subprocess storm (per `listSessions()` call)
Per agent proc (~54 of them), synchronously on the event loop:
1. `cwdOf(pid)` → **`lsof`** (~30–80ms each) → ~41 lsof ≈ **1.2–3.3s** (dominant).
2. `tmuxTargetForPid(pid)` → `paneMap()` rebuilds **`tmux list-panes -a`** *every
   call* (6ms × 54 ≈ 320ms) **+** parent-chain walk of up to 12 × `ps -o ppid=`.
3. `startTimeMsOf` / `ppidOf` filter → more `ps`.

Hundreds of synchronous spawns per pass. `Promise.all` does **not** help —
`spawnSync` is blocking, so they serialize and freeze the loop regardless.

## Fix (three layers, no API/signature changes)
1. **`sessions.ts` — coalesce + TTL-cache `listSessions()`.** Concurrent callers
   (poll + send + resume) share one in-flight computation instead of each
   launching the storm; results reused for ~600ms.
2. **`tmux.ts` — memoize `paneMap()`** (short TTL). 54 `tmux list-panes` → ~1.
3. **`procinfo.ts` — batch `ppidOf` into one `ps -axo pid=,ppid=` snapshot;
   cache `cwdOf`/`startTimeMsOf` per pid** (immutable for a process's lifetime).
   Hundreds of `ps`/`lsof` spawns → a handful.

Net: `listSessions()` stops freezing the loop, so sends to idle sessions are
serviced promptly.
