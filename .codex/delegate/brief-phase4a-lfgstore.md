# Delegation Brief: phase4a — LFGStore (GRDB persistence layer, no UI integration)

**Goal:** the client-side durable store the UI will later render from (Track B Phase 4,
proposal §7.1): a GRDB/SQLite `LFGStore` in LFGCore holding hosts, sessions, messages
(bounded), cursors, and read-state — with upsert-by-id ingestion, ValueObservation, and a
full test suite. **This phase is the LAYER ONLY**: no SessionStore/UI changes, no data
migration off UserDefaults, no outbox worker (the `outbox` TABLE ships now, unused).

**Repo:** worktree of `lfg`. Work ONLY in `ios/LFGCore/` (Package.swift + Sources + Tests).
Do NOT touch `ios/LFG/` (app target), `ios/project.yml`, or `src/`. Swift 6 strict
concurrency. The package must keep passing `swift test` on macOS (GRDB is cross-platform).

## Context (read first)

- `ios/LFGCore/Package.swift` — add GRDB.swift (github.com/groue/GRDB.swift, latest 7.x)
  as a package dependency of the LFGCore target.
- `ios/LFGCore/Sources/LFGCore/Models.swift` — `Session`, `Message` API types (lenient
  Codable). The store's records mirror the FIELDS THE UI NEEDS, not the whole API type.
- `ios/LFGCore/Sources/LFGCore/HostConfig.swift` — `Host` (url identity, hostId, names).
- `ios/LFGCore/Sources/LFGCore/HostEvents.swift` — `HostLinkPolicy.cursorKey` (UserDefaults
  cursors today; the store's `cursors` table replaces this in Phase 4b — same semantics:
  one Int64 seq per host url).
- Proposal §7.1 (`.claude/brainstorm/multihost-first-rearchitecture.md`) — the table list.

## Spec

1. **`LFGStore`** (`Sources/LFGCore/LFGStore.swift` + a Records file): actor or
   `Sendable` class wrapping a GRDB `DatabaseQueue`/`DatabasePool` (file path injected;
   in-memory supported for tests).
2. **Schema (migrations via GRDB DatabaseMigrator, v1):**
   - `hosts(id TEXT PRIMARY KEY /* url */, hostId TEXT, name TEXT, displayName TEXT,
     isDefault BOOLEAN)`
   - `sessions(sessionId TEXT PRIMARY KEY, hostId TEXT /* host url */, title TEXT,
     cwd TEXT, agent TEXT, model TEXT, closed BOOLEAN, busy BOOLEAN, assignedUser TEXT,
     lastActivityAt REAL, lastMessageId TEXT, lastMessagePreview TEXT, lastMessageRole TEXT)`
   - `messages(id TEXT, sessionId TEXT, role TEXT, kind TEXT, text TEXT, ts REAL,
     json TEXT /* full lenient payload for rich rendering */, PRIMARY KEY(sessionId, id))`
   - `outbox(clientId TEXT PRIMARY KEY, sessionId TEXT, hostId TEXT, text TEXT,
     state TEXT, createdAt REAL, updatedAt REAL)` — schema only this phase.
   - `cursors(hostId TEXT PRIMARY KEY /* host url */, seq INTEGER)`
   - `readState(sessionId TEXT PRIMARY KEY, lastSeenMessageId TEXT, openedAt REAL)`
3. **Ingestion API (all upsert-by-id, idempotent):**
   - `upsertHosts([Host])`, `upsertSessions([Session], hostId:)` (maps API type → record;
     absent fields keep existing values — partial updates must not null-out columns),
   - `appendMessages(sessionId:, [Message])` with per-session bound: keep the newest ~200
     by ts (delete older within the same write transaction),
   - `setCursor(hostId:seq:)` monotonic (never decreases), `cursor(hostId:)`,
   - `markSeen(sessionId:lastSeenMessageId:)`, read-state fetch.
4. **Observation:** `ValueObservation`-based publishers/async sequences for (a) the session
   list (joined with read-state, ordered by lastActivityAt desc) and (b) one session's
   messages. Deliver on MainActor for UI use later.
5. **Concurrency:** GRDB types don't cross actor boundaries; expose async methods.
   Everything public is documented. Match LFGCore's lenient/defensive house style.

## Verification (run all; paste output)

1. `cd ios/LFGCore && swift test` — new suite covering: migration on fresh db; upsert
   idempotency (ingest same batch twice = identical row state); partial-update non-nulling;
   message bounding at the cap; cursor monotonicity; read-state round-trip; observation
   emits on relevant writes (async expectation).
2. All 108 existing tests still green.
3. Note: first `swift test` fetches GRDB — if the sandbox blocks network, report it and the
   delegator will run resolution.

## Definition of done
- [ ] GRDB dep added to LFGCore only; package builds + tests on macOS.
- [ ] Schema v1 via migrator; all tables above.
- [ ] Idempotent upsert ingestion incl. partial-update semantics; bounded messages.
- [ ] Observation streams for list + transcript.
- [ ] No app-target, project.yml, or src/ changes.

**Report back:** files changed, test output, any GRDB version/API notes, deviations.
