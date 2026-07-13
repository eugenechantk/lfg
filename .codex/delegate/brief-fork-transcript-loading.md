# Delegation Brief: fix indefinite "Connecting to live transcript…" after forking a session

**Goal:** After forking a claude session, the fork's detail view must render the copied
history immediately (served from a fork-point snapshot of the source transcript) and
hand off cleanly to the fork's real transcript file once its first turn materializes it.

**Working directory:** `/Users/eugenechan/dev/personal/lfg-fork-fix` (git worktree,
branch `fork-transcript-loading`). Work ONLY here — do not touch
`/Users/eugenechan/dev/personal/lfg` (other agents are active there).

**Full spec (read first):** `.codex/delegate/spec-fork-transcript-loading.md` — it is
the authoritative design: root cause, fix shape (4 parts), no-duplication analysis,
success criteria. Implement exactly that design.

## Summary of the four parts

1. **Fork lineage** (`src/commands/serve.ts` `forkSession`, `src/managed.ts`):
   snapshot the source transcript's byte size before spawning; after the pidfile
   resolves the fork's new id, patch the fork's managed record with optional fields
   `sessionId`, `forkedFrom`, `forkSourceBytes`. Persisted in
   `data/managed-sessions.json` so it survives server restart.
2. **`/messages` fallback** (`serve.ts` messages handler, helper in
   `src/sessions.ts`): when `resolveTranscript(sid)` is null and a managed record
   with `sessionId === sid` + `forkedFrom` exists, serve messages from the SOURCE
   transcript capped at the first `forkSourceBytes` bytes (drop trailing partial
   line). Tag response `forkPending: true`. No record / source gone → 404 as today.
3. **Live-stream late-attach** (`serve.ts` `/api/live/stream`): unresolved sids
   enter a per-connection pending set ONLY if they have a fork lineage record
   (all other unresolved sids are dropped exactly as today). Retry resolution on a
   ~2 s timer (not the 700 ms pump). On attach: offset = current file size (never
   replay the file), begin busy/prompt/queue polling, emit one SSE control event
   `event: reset` / `data: {"sid": …}`. Pending set dies with the connection.
4. **iOS client** (`ios/LFG/SessionStore.swift`, `ios/LFG/SessionDetailView.swift`):
   handle the `reset` event in the store's live-stream handling — call
   `loadHistory(sid)` ONLY if `transcripts[sid]` is non-empty; otherwise no-op.
   Fix the stale comment at `SessionDetailView.swift` ~line 376–378 (the one
   claiming "its history is already copied server-side"). Optional: distinct
   empty-state copy "Starting branch…" when the session is a fresh fork.

## Constraints

- Match existing code style/idioms in each file; keep edits minimal and additive.
- Bun server, single event loop — no per-sid `setInterval` fan-out; one shared
  pending-retry timer per stream connection (see existing `iv`/`pi` pattern).
- Do not change how `claude --fork-session` is invoked (`src/tmux.ts` untouched).
- Do not restart or touch the running server on port 8766.
- TypeScript for server; Swift for iOS. No new dependencies.

## Verification (run these yourself; all must pass)

- `bun test` — full suite green, including your new tests:
  - managed-record lineage persistence (fields survive write/read round-trip)
  - snapshot-capped message read: cap mid-line drops the partial trailing line;
    cap ≥ file size serves everything
  - `/messages` fallback: fork sid with lineage + missing transcript → 200 with
    source-snapshot messages + `forkPending: true`; unknown sid → 404;
    fork sid whose source transcript is also missing → 404
  - stream pending→attach: pending sid gated on lineage record; on file
    appearance emits exactly one `reset` and does NOT replay file content;
    non-fork unresolved sid never enters pending
- `bun run typecheck` if the script exists (check package.json), else `bunx tsc --noEmit`.
- iOS: build must succeed — `cd ios && xcodebuild -project LFG.xcodeproj -scheme LFG
  -destination 'generic/platform=iOS Simulator' build` (or equivalent). Do NOT run
  simulators or UI tests — visual verification is done by the supervisor afterward.

## Definition of done

- [ ] All four parts implemented per spec
- [ ] New unit tests written and green; whole `bun test` suite green
- [ ] Server typechecks; iOS target builds
- [ ] No changes outside the named files + their test files (plus small type
      touch-ups where imports require)
- [ ] Committed on branch `fork-transcript-loading` with a clear message

## Report back

Files changed, test output summary (counts), any deviations from the spec and why,
anything left incomplete.
