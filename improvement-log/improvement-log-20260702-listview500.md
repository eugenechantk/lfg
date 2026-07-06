# Improvement Log — Session 20260702-listview500

## Tracker

- [x] 2026-07-02 — Flakey 500 on iOS list view root-caused to spawn-storm RangeError escaping listSessions(); fixed with last-good fallback + error boundary + spawn reduction
- [x] 2026-07-02 — Deeper root cause (spawn storm) fixed + deployed to main (c0d5058→ed479ee): batched ps/lsof snapshots (26→3 spawns/scan, byte-identical output), async capturePane off the loop, AND async ps/lsof snapshots. Cold-storm event-loop starvation gone: 238,553ms+21 ECONNRESET → 221ms/80-of-80-200. 0 RangeErrors/segfaults/500s under load.
- [ ] 2026-07-02 — LESSON: don't declare "done" before testing the cold path under load. First "done" report missed that psSnapshot/primeCwds were still spawnSync; a background stress run (overlapping storms on a cold server) surfaced 238s stalls. Test cold-start + concurrency, not just warm steady-state, before claiming an event-loop fix is complete.

## Log

### 2026-07-02 — Flakey list-view 500 = spawn-storm RangeError

**What happened:** User reported increasingly frequent 500s on the iOS list view. Ground truth from `/tmp/lfg-serve.log`: `RangeError: Maximum call stack size exceeded` thrown by `Bun.spawnSync` inside `spawnText` (procinfo.ts:20), propagating uncaught through `listSessions()` to the `fetch` handler (serve.ts:1152 → 538) → bare Bun 500. 1998 occurrences + 28 segfault panics in the log.

**Root cause:** `listSessions()` enrichment fans out dozens of synchronous `Bun.spawnSync` calls (ps/lsof), and the per-SSE-connection poll intervals (700ms/1s) each call `capturePane` (spawnSync tmux) per pane. Many pollers + a list request landing on the single event loop at once drives spawnSync to its stack limit. At the stack limit the RangeError escapes `spawnText`'s own try/catch (JSC can't reliably run the catch frame), so the whole scan rejects and — with no error boundary in `fetch` — surfaces as a 500. "More frequent lately" = more concurrent sessions = bigger storm.

**Fix (3 layers):**
1. `listSessions()` last-known-good fallback (sessions.ts) — on reject, serve the previous good result instead of propagating. Converts the transient 500 into a 200 with slightly-stale data.
2. Bun.serve `error()` handler (serve.ts) — backstop so no route ever returns a bare unstructured 500; logs the stack.
3. `procStartMatches` reuses the cached `startTimeMsOf` instead of spawning a fresh `ps -o lstart=` per proc per pass (procinfo.ts) — removes ~1 spawn per claude proc per scan, shrinking the storm.

**Verification:** Restarted serve (had to chase the pid — it segfaulted+respawned twice during the session; confirmed fresh pid mtime > edit mtime). Realistic load (SSE stream open + list poll every 0.3s × 40): 40/40 → 200. Extreme load (60 concurrent): 49×200, 11×curl-000 (event-loop saturation, NOT 500, NOT segfault) — the deeper issue below.

**Lesson:** Went straight to ground truth (the server log) instead of theorizing — the project hazard note "previously-fixed bug = deploy gap" and memory `[[ground-truth-before-hypothesizing]]` both paid off. The restart-pid chase is known lfg friction: the process segfaults on its own, so the `ps` pid ≠ the one you saw a minute ago — always re-check pid mtime vs source mtime right before AND after restart.

### 2026-07-02 — Deeper root cause: synchronous spawnSync storm (open)

**What happened:** Even after the fix, 60-concurrent load produced 11 connection drops (curl 000), and the log shows 28 historical segfaults. Both trace to the same architecture: `Bun.spawnSync` blocks the single event loop, and Bun's spawnSync is unstable under heavy reentrant load (stack overflow → segfault).

**What better looks like:** Move the hot introspection spawns (`ps`, `lsof`, `tmux capture-pane`) from `Bun.spawnSync` to async `Bun.spawn` with a small concurrency limiter, OR throttle/serialize them behind a single shared queue. This is the real cure for the "flakey connection" (segfault-driven restarts) — proposed to Eugene as the next step; not landed blind because it's a broader, riskier refactor.

### 2026-07-02 — Premature "done" before cold-path load test

**What happened:** After the batching + async-capturePane, I reported the work complete and "nothing left open." A background stress run (that I'd kicked off earlier and forgotten) then completed and showed round-0 taking 238,553ms with 21 ECONNRESETs — real event-loop starvation. Root cause: `psSnapshot()` and `primeCwds()` were still `Bun.spawnSync`, so a cold scan under a concurrent pile-up blocked the loop. Warm steady-state (what I'd tested) was fine (5–70ms), which masked it.

**Why this was wrong:** I verified the warm path and the crash counters (0 RangeErrors) but not the COLD path under concurrency — the exact condition that starves the loop. "Byte-identical output + 0 crashes" isn't "no event-loop stalls."

**What better looks like:** For any event-loop/latency fix on this single-process server, always include a cold-start-under-load test (restart, then immediately storm) before declaring done — not just warm steady-state. Fixed by making the two heavy spawns async via the same cache-priming trick (`primeProcSnapshot` awaited up front; sync `psSnapshot` reads the primed cache → zero ripple). Result: 238s → 221ms cold.
