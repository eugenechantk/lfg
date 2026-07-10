# Delegation Brief: phase2a-server — events page endpoint + push payloads carry journal head

**Goal:** Background-wake support on the server: (1) a non-streaming JSON page endpoint over the
event journal, and (2) the existing APNs pushes gain `content-available: 1` plus `{hostId, seq}`
custom keys so the iOS app can delta-sync on wake.

**Repo:** you are in the repo root (a git worktree of `lfg`). Bun + TypeScript. Run everything
with `bun`. Do NOT touch `ios/` and do NOT touch `/api/events` (the SSE endpoint), `/api/live/*`,
or `src/journal-pump.ts`.

## Context you need (read these first)

- `src/journal.ts` — the event journal. You will use the existing `Journal` class:
  `journal.since(seq, limit)` (rows `{seq, ts, sessionId, type, payload}` where `payload` is a
  JSON **string**), `journal.head()`, `journal.canServe(since)`. Do not modify this file except,
  if needed, ADDING a method; do not change existing semantics.
- `src/commands/serve.ts` — HTTP handlers. The journal instance is created at the top of
  `cmdServe()` (`const journal = Journal.open(...)`). Find the existing `/api/events` handler to
  see the house style for handlers; add the new endpoint next to it. `startPushWatcher(...)` is
  called near the bottom of `cmdServe()`.
- `src/push/watcher.ts` — push watcher: `TickDeps` (dependency-injection type), `buildPayload()`
  (pure payload builder), `runPushTick()` (uses `deps`), `startPushWatcher()` (constructs the
  default deps). Follow the existing injection pattern.
- `src/push/apns.ts` — `ApnsPayload` type and `apnsBody(payload)` which serializes the APNs JSON
  body. Look at how `aps` is currently assembled.
- `src/hostinfo.ts` — `hostInfo()` returns `{ hostId, name, ... }` for this machine.

## Spec

### 1. `GET /api/events/page?since=<seq>&limit=<n>`

- Parse `since` like the `/api/events` handler does (non-negative integer, default 0). Parse
  `limit` as an integer, default 200, clamp to [1, 1000].
- If `journal.canServe(since)` is false → respond
  `{ events: [], head: <journal.head()>, canServe: false }` (HTTP 200 — the client treats this as
  "full refresh needed", it is not an error).
- Otherwise respond
  `{ events: [{seq, ts, sessionId, type, payload}, ...], head: <head>, canServe: true }` where the
  rows come from `journal.since(since, limit)` **and `payload` stays a raw JSON string** (do NOT
  parse/re-nest it — the iOS client reconstructs its SSE decode path from the string verbatim).
- Log one line per request in the same style as the `/api/events` connect log:
  `[events] page since=<since> limit=<limit> head=<head> served=<n>`.

### 2. Push payloads carry the journal head

- `TickDeps` gains two injected fields: `head: () => number` and `hostId: () => string`.
- `buildPayload(...)` (or the point where the APNs payload is finalized — choose the seam that
  keeps `buildPayload` pure and testable) includes in the payload:
  - `aps["content-available"] = 1` (alongside the existing alert — alert + content-available in
    one push is valid and intended), and
  - top-level custom keys `hostId: <hostId>` and `seq: <head>` next to the existing custom keys
    (look at how the payload carries session info today; keep that shape).
- `startPushWatcher(...)` needs access to the journal head + hostId. `startPushWatcher` is called
  from `cmdServe()` where `journal` exists: extend `startPushWatcher`'s signature to accept them
  (e.g. an optional deps-override argument consistent with how it builds `TickDeps` today), and
  wire `() => journal.head()` and `() => hostInfo().hostId` at the call site in `serve.ts`.
  Keep backward compatibility: if not provided, `seq`/`hostId` keys are simply omitted
  (`content-available` may still be set) so existing tests/uses don't break.

### 3. Tests (bun:test, colocated like the existing `src/push/*.test.ts`)

- apns/watcher: a test proving the built payload for a transition contains
  `aps["content-available"] === 1`, `hostId`, and `seq` when deps provide them, and omits
  `hostId`/`seq` (no crash) when they don't. Extend the existing watcher/apns test files in their
  style rather than creating new harnesses.
- journal page logic: if you put any non-trivial logic in a helper (e.g. param clamping), unit
  test the helper. The HTTP handler itself is covered by the live verification below.

## Verification (run these yourself; paste output in your report)

1. `bun test` — entire suite green.
2. Live endpoint check (uses a scratch data dir so nothing touches real state):
   ```
   LFG_DATA=/tmp/codex-p2a LFG_PORT=8798 bun run src/cli.ts serve &   # note the pid
   sleep 4
   curl -s 'http://127.0.0.1:8798/api/ping'
   curl -s 'http://127.0.0.1:8798/api/events/page?since=0&limit=5'          # expect events json, canServe true
   curl -s 'http://127.0.0.1:8798/api/events/page?since=999999'             # expect canServe false, events []
   kill <pid>
   ```
   Confirm: page payloads' `payload` fields are strings; `head` present; the `[events] page` log
   line appears in the server output.

## Definition of done

- [ ] `/api/events/page` behaves per spec incl. clamping + canServe:false shape (HTTP 200).
- [ ] Push payload carries content-available + hostId + seq when wired; omits gracefully when not.
- [ ] `bun test` fully green (no skipped/broken existing tests).
- [ ] No changes outside: `src/commands/serve.ts`, `src/push/watcher.ts`, `src/push/apns.ts`,
      `src/push/*.test.ts`, and (only if strictly needed, additive) `src/journal.ts`.
- [ ] Live curl verification performed with output captured.

**Report back:** files changed, test summary line, the three curl outputs, anything incomplete or
any spec ambiguity you had to resolve (state the choice you made).
