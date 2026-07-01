# Killing the spawn storm — scoping & plan

**Branch:** `async-spawn` (worktree `../lfg-async-spawn`, based on `c0d5058` — the resilience fix)
**Goal:** Eliminate the synchronous `Bun.spawnSync` storm that causes `RangeError: Maximum call stack size exceeded` (1998× in the log) and 28 segfaults → the flakey list-view 500s and connection drops.

## The problem, precisely

`Bun.spawnSync` (a) blocks the single event loop for the duration of the child, and (b) is unstable under heavy reentrant load — at a deep JS stack it throws a stack-overflow `RangeError` that escapes even `spawnText`'s try/catch, and occasionally segfaults the process.

Two hot paths pile synchronous spawns onto the loop concurrently:

1. **`listSessions()` enrichment** — per claude/codex proc, per scan: `cwdOf` (lsof), `startTimeMsOf` (ps), `readPidSession`→`procStartMatches` (ps), `ppidOf` (ps snapshot). With ~13 procs that's dozens of `spawnSync` per `/api/sessions` hit.
2. **SSE poll loops** (`serve.ts` `pollOne`, 700ms/1s intervals per connected client) — `capturePane` (`tmux capture-pane`) per pane per tick.

When a list request lands mid-poll-tick, the two storms interleave on one stack → overflow.

## Call-site inventory (fan-out that makes brute-force async expensive)

| Function | sync? | call sites | notes |
|---|---|---|---|
| `capturePane` | sync | **16** | poll loop (async ctx) + sendq/tmux send flows (sync ctx) |
| `startTimeMsOf` | sync | 5 | cached 30s |
| `readPidSession` | sync | 3 | called in a `.map` |
| `ppidOf` | sync | 2 | called in a sync `.filter` (sessions.ts:982) |
| `cwdOf` | **async** | — | already async (lsof, cached 30s) |
| `procStartMatches` | sync | 1 | inside `readPidSession` |

`ppidOf`-in-`.filter` and `procStartMatches`-in-sync-`readPidSession`-in-`.map` are why "just add async" ripples badly.

## Two approaches

### A — Brute-force async threading (the "big work" Eugene flagged)
Convert `spawnText`→async (`Bun.spawn` + a global concurrency semaphore), make every hot fn async, thread `await` through all callers. Fixes both blocking and overflow, but:
- 16 `capturePane` sites + sync `.filter`/`.map` chains must be restructured.
- High blast radius across `procinfo.ts`, `tmux.ts`, `sessions.ts`, `sendq.ts`, `serve.ts`.

### B — Snapshot-batching + async-only-where-it-matters ✅ RECOMMENDED
Attack the *count* of spawns, not just their sync-ness. **Verified feasible:**
- `ps -axo pid=,ppid=,lstart=,command=` — ONE spawn yields pid+ppid+start+cmd for every proc. Collapses `listProcs`, `ppidMap`, `startTimeMsOf`, `procStartMatches` into one per-scan snapshot object.
- `lsof -a -p <pid1,pid2,...> -d cwd -Fn` — ONE spawn yields every proc's cwd (block-per-pid). Collapses per-pid `cwdOf`.

So `listSessions`' dozens-of-spawns storm → **~2 spawns per scan**, with the introspection fns reading from a snapshot passed into the scan (they stay *synchronous* → near-zero ripple).

Remaining hot spawn is `capturePane` in the poll loop. Its poll callers (`pollOne`) are already async, so:
- Add `capturePaneAsync` (async `Bun.spawn`) behind a small shared concurrency limiter (e.g. max 4–6 in flight), and use it **only** in the SSE poll loop + push watcher (the per-tick callers).
- Leave the synchronous `capturePane` for the low-frequency send/confirm flows in `tmux.ts`/`sendq.ts` (user-triggered, not a storm).

**Why B is better:** fewer, larger spawns = far less event-loop blocking *and* drastically fewer concurrent spawnSync frames (the overflow trigger), with a fraction of the blast radius. It also speeds up the list endpoint (2 spawns vs 30).

## Proposed plan (approach B)

1. **procinfo snapshot layer.** New `procSnapshot()`: runs the two batched spawns (ps-all, lsof-batched for the claude/codex pids), returns `{ byPid: Map<pid,{ppid,startMs,cmd}>, cwdByPid: Map<pid,string> }`. TTL-cache it (~600ms, aligned with `LIST_TTL_MS`).
2. **Rewire `listSessionsUncached`** to build the snapshot once and have `cwdOf`/`startTimeMsOf`/`ppidOf`/`procStartMatches` read from it (overloads that accept the snapshot; keep per-pid fallbacks for non-scan callers).
3. **Async capture for the poll loop.** Add `capturePaneAsync` + a `Semaphore(n)` limiter in `tmux.ts`; swap the `serve.ts` poll-loop + `push/watcher.ts` call sites to it. Leave send-flow `capturePane` sync.
4. **Verify:** re-run the 60-concurrent + SSE-open load tests → expect 0×500, 0×curl-000, 0 new RangeError, 0 segfault; confirm spawn count per scan dropped (instrument `spawnText`/`Bun.spawn` with a counter behind an env flag).
5. Keep the resilience fix (last-good + error boundary) as defense-in-depth.

## RESULTS (implemented — commit `a07385c`)

Step 1–2 (procinfo snapshot batching) done, zero-ripple via cache-priming:
- `psSnapshot()` — one `ps -axo pid=,ppid=,lstart=,command=` feeds `ppidOf`, `startTimeMsOf`, `commOf`, and both `listProcs` calls.
- `primeCwds(pids)` — one batched `lsof` pre-fills `cwdCache`; `cwdOf` keeps its signature and hits cache.

**Measured (worktree, live host):**
- Spawns per scan: **~26 → 3 cold / 1 warm** (ps + batched lsof + one tmux list-panes).
- Correctness: `listSessions()` output **byte-identical** to the running main server — 20/20 sessions, 0 cwd/title/startedAt diffs.
- Resilience: **360 concurrent scans + 2,880 capturePane calls → 0 RangeErrors, 0 throws.**

**Step 3 (capturePaneAsync) — deferred, with rationale.** The RangeError was triggered by the *coincidence* of a 26-spawn list burst with the poll loop's capturePane. Removing the burst eliminated the overflow in stress testing, so async-capture is no longer needed to stop the *crash*. It remains a worthwhile *latency* optimization for many-simultaneous-clients steady state (N phones × M panes × ~1.4 Hz of blocking spawns), but that's a separate, lower-risk change to make only if event-loop stalls persist after this deploys. Not landing it blind.

## Open questions for Eugene
- OK to go with **B** (snapshot-batching) over the full async rewrite? (Recommended — smaller, faster, safer.)
- Concurrency-limiter ceiling for `capturePaneAsync` — start at 4?
- Want an eng-review pass (`/plan-eng-review`) on this before implementing, or just build it?
