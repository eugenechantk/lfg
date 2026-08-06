# Diagnosis — answering a prompt takes 5–10s

**Date:** 2026-08-06
**Host:** eugenes-macbook-pro-2 (49 sessions, 48 tmux panes, 93 `claude` procs, 1217 total procs)
**Symptom:** Tapping an option in the iOS prompt panel spins for 5–10s before it clears.

## Measured, not theorized

```
$ for i in 1..5; curl -w %{time_total} /api/sessions
3.80s   0.83s   3.70s   95.37s   3.17s
```

`POST /api/sessions/:id/answer` (`serve.ts:2272`) does `await listSessions()` **before** it
touches the pane. `answerPrompt` itself (`tmux.ts:1062`) is cheap — one `capture-pane` (70ms)
+ 60ms per arrow key + 120ms + Enter, well under 500ms. **The entire wait is the session scan.**

The client has no optimistic UI: `Components.swift:238` sets `answering = option.index`, awaits
the POST, and `.disabled(answering != nil)` holds the panel until it returns. So the user sees
the full server latency as a spinner.

## Root cause: a self-reinforcing scan pile-up

Four compounding factors, in order of impact.

### 1. `primeProcSnapshot` has no in-flight coalescing (`procinfo.ts:131`)

```ts
export async function primeProcSnapshot(): Promise<void> {
  if (procSnap && now - procSnap.at < PROC_SNAP_TTL_MS) return;   // reads cache
  const rows = parsePsRows(await spawnTextAsync(["ps","-axo",PS_FORMAT]));
  procSnap = { at: Date.now(), rows };                             // writes cache AFTER
}
```

The cache is written only after the spawn returns. A full-box `ps -axo` over 1217 processes
costs **0.5–3.8s** here. Every caller that arrives during that window sees a stale cache and
spawns *its own* `ps`. Observed live:

```
$ pgrep -P 31132 -l   # sampled 20x, same pids every time
10 × ps    # ten concurrent full-box ps snapshots, all alive for seconds
$ ps -eo %cpu,command | sort -rn
69.2 ps -axo pid=,ppid=,tty=,lstart=,command=
68.2 ps -axo pid=,ppid=,tty=,lstart=,command=
```

Classic thundering herd — each concurrent `ps` makes the others slower.

### 2. TTLs are shorter than the scan they guard

`PROC_SNAP_TTL_MS = 600` and `LIST_TTL_MS = 600`, but the scan takes ~3.7s.

- **Overlapping scans:** `listSessions` coalesces only within 600ms, so a brand-new scan starts
  every 600ms while ~6 earlier ones are still running. Each redoes the full fan-out.
- **Mid-scan expiry → blocking sync spawns:** the cache goes stale *during* the scan it primed.
  The per-pid accessors (`listProcs`, `ppidOf`, `ttyOf`, `commOf` — `procinfo.ts:191,249,316,338,358`)
  then fall through to the **synchronous** `psSnapshot()` (`procinfo.ts:119`), which fires
  `Bun.spawnSync(["ps","-axo",…])`. That freezes the single Bun event loop for 0.5–4s *per call*,
  across 93 candidate pids. This is what produces the 95s outlier — every HTTP request on the
  box stalls behind it.

### 3. tmux fan-out is a hard serial floor

```
single capture-pane:  ~70ms
48 panes serially:    1033ms
```

~1s of unavoidable serial tmux work per scan, before any of the above.

### 4. A rogue duplicate server has been running for 6.5 hours

```
PID    PPID   STARTED              ELAPSED   %CPU  COMMAND
31132  1611   Thu Aug 6 18:40:17   47:02     110   bun run src/cli.ts serve   ← holds :8766
66597  87565  Thu Aug 6 12:53:14   06:34:05   13   bun run src/cli.ts serve   ← orphan
```

`66597`'s parent is a `codex --yolo` process — a codex agent started a second `serve` at 12:53
that never got the port. Only `31132` is `LISTEN`ing. The orphan contributes no scans (no `ps`
children observed) but burns ~13% of a core continuously.

## The fix

| # | Change | File | Effect |
|---|---|---|---|
| 1 | Coalesce `primeProcSnapshot` — store the in-flight `Promise` and return it to concurrent callers, same shape as `listSessions`' `listCache` | `procinfo.ts:131` | 10 concurrent `ps` → 1. Biggest single win |
| 2 | Never `spawnSync` a full-box `ps` from a per-pid accessor — serve the stale snapshot instead and let the async prime refresh it | `procinfo.ts:119` | Removes the event-loop freeze / 95s outlier |
| 3 | Raise `LIST_TTL_MS` / `PROC_SNAP_TTL_MS` above the real scan duration (~2–3s), or make the TTL adaptive to the last measured scan | `sessions.ts:1126`, `procinfo.ts:60` | Stops unbounded scan overlap |
| 4 | Don't `await listSessions()` on the answer path — resolve `tmuxTarget` from a lightweight per-session lookup (or serve it from `lastGood`) | `serve.ts:2272` | Answer latency drops to ~300ms independent of scan health |
| 5 | Kill orphan `66597`; guard `serve` startup so a second instance that can't bind exits instead of lingering | runtime + `serve.ts` boot | Frees a core |

(4) alone fixes the reported symptom. (1) and (2) fix the underlying instability that also makes
the list view and sends slow. Both are worth doing — (4) is a targeted patch, (1)+(2) are the
real repair.

---

## Applied — the real repair (1, 2, 3 + completion-stamped TTL)

Shipped 2026-08-06 19:39, server pid 15143. Item (4), the targeted `/answer` patch, was **not
needed** — see results.

### Changes

- **`src/sessions.ts`** — `listCache` now tracks `startedAt` + `settledAt`. An **in-flight** scan is
  shared by every caller with no TTL (two scans of one host can only slow each other); a **settled**
  scan is served for `LIST_TTL_MS` measured from settle, not start. `LIST_TTL_MS` 600 → 1500ms.
  Added `LIST_INFLIGHT_MAX_MS = 15s` so a wedged scan can't block callers forever.
- **`src/procinfo.ts`** — `primeProcSnapshot` coalesces on an in-flight promise. `psSnapshot()` no
  longer `spawnSync`s a full-box `ps` when a stale snapshot exists: it serves the stale rows and
  kicks an async refresh, with a 30s ceiling as a correctness backstop for non-scan callers.

`tsc --noEmit` clean; `bun test` 351 pass / 0 fail.

### Results

| Probe | Before | After |
|---|---|---|
| `/api/sessions` p50 | ~3.7s | **0.002s** |
| `/api/sessions` p90 | — | **0.49s** |
| `/api/sessions` max | **95.4s** | **0.53s** |
| answer path (`listSessions` portion) | ~3.7s | p50 0.002s, max 0.68s |
| concurrent full-box `ps` | **10** (2 at ~69% CPU) | **0–1**, transient |

Scan cost itself fell ~3.7s → ~0.5s once the blocking sync `ps` storm was removed. Data unchanged:
50 sessions, 49 with `tmuxTarget`.

Expected answer latency = cached scan (~2ms typical / ~0.5s worst) + `answerPrompt`'s ~300ms of
capture + keystrokes ≈ **0.3s typical, under 1s worst case**, down from 5–10s.

### Verification caveat

Measured at the API layer. The answer route was timed with a nonexistent session UUID so it runs
the same `await listSessions()` then 404s — real code path, zero side effects, since answering a
live prompt would have hijacked another agent's session. The `answerPrompt` keystroke portion is a
known ~300ms constant (one `capture-pane` + arrow keys + Enter) and was not re-measured.
**Unverified by tapping in the iOS app.**

### Still outstanding

- Orphan `serve` pid `66597` (parent: a `codex --yolo` from 12:53) still running, ~13% CPU, not
  the listener. Not killed — awaiting the go-ahead.
- No guard yet against a second `serve` instance lingering when it can't bind the port.
- `LIST_TTL_MS = 1500` is a judgment call. The in-flight sharing is what removes the pile-up; the
  TTL only trades data freshness for cache-hit rate and can be tuned either way.
