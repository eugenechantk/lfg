# Feature: Track B — Phase 3 (durable sends) + Phase 4a (LFGStore)

Tier: **product**. Spec: `.claude/brainstorm/multihost-first-rearchitecture.md` §6.2, §7.1, §10 Track B.
Worktree: `.claude/worktrees/track-b-reliability` (branch `worktree-track-b`).

## Scope & routing (Claude frames/verifies, Codex executes)

| # | What | Owner | Status |
|---|---|---|---|
| 3 | Server: sendq rows persisted in SQLite (journal db), `clientId` idempotency on POST /send, journaled `queue {clientId, delivered, userTurnId}` acks | Codex (brief: `.codex/delegate/brief-phase3-durable-sendq.md`) | delegated |
| 4a | Client: `LFGStore` (GRDB in LFGCore) — schema, upsert ingestion, observation, migrations, tests. NO UI integration yet. | Codex (brief: `.codex/delegate/brief-phase4a-lfgstore.md`) | delegated |
| 4b | SessionStore/UI renders from the store; cursors + read-state migrate off UserDefaults; airplane-mode cold launch gate | Claude-framed after 4a verified | pending |
| 5 | Outbox worker on the store driven by Phase 3 acks; delete reconcile-by-text stack | after 3+4 soak | pending |
| 6 | Leases | after 5 | pending |
| 7 | Legacy deletion sweep | last | pending |

## Pinned decisions

- **Persistence lib: GRDB** (proposal §11 recommendation; ValueObservation → SwiftUI).
- **LFGStore lives in LFGCore** so `swift test` covers it without a simulator.
- Phase 3 does NOT alter delivery/tmux confirm logic — only where queue state lives,
  request dedupe, and the ack event. Phase 5 (not now) consumes the acks client-side.
- The soak rule holds: nothing legacy is deleted in 3/4a (purely additive); the
  reconcile-by-text deletion waits for Phase 5 after acks prove out.

## Success criteria

- SC-3.1: server restart with queued sends → rows survive, delivery resumes (test simulates via module re-init from db).
- SC-3.2: duplicate POST /send with same clientId → single queue row, second response returns existing state.
- SC-3.3: delivery confirmation journals `queue` event carrying `{clientId, delivered, userTurnId}` visible on `/api/events` replay.
- SC-3.4: all bun suites green; endpoints back-compatible (clientId optional).
- SC-4a.1: LFGStore round-trips hosts/sessions/messages/cursors/readState with upsert-by-id idempotency (re-ingesting same data = no change).
- SC-4a.2: messages bounded ~200/session; ValueObservation emits on writes.
- SC-4a.3: `swift test` green incl. new store suite; app still builds (package dep added cleanly).

## Evidence (2026-07-10)

- **Phase 3 (Codex + Claude verify):** 106/106 bun tests incl. restart simulation
  (rows survive re-init, sending→pending downgrade). Live on scratch serve: duplicate
  clientId POST returned the same row with `duplicate: true` (exactly-once proven — 1
  user turn from 2 POSTs); `sendq` table persists rows in journal.db; delivered acks
  journaled with real `userTurnId` (`{"kind":"delivered","clientId":"ack-check-2",
  "userTurnId":"a561c185…"}`). Claude review found + fixed one ack gap: the
  pre-delivered resume path didn't journal (caught live, not by tests); a second
  redundant fix attempt in the pure reconcile core was reverted — the caller already
  acks promotions with userTurnId lookup.
- **Phase 4a (Codex + Claude verify):** 115/115 swift tests (7 new store tests).
  Claude fixed post-delivery: GRDB 7 async `read`/`write` awaits (Codex couldn't fetch
  GRDB in sandbox — fully unverified delivery), `Host` ambiguity vs Foundation, Swift 6
  sendability in the test stream probe (rewrote as buffering actor), and
  non-deterministic JSON re-encoding breaking byte-level upsert idempotency (fixed with
  `.sortedKeys` — the idempotency test caught a real semantic requirement).
- GRDB resolved at 7.11.1; dep confined to LFGCore; no app-target changes.
