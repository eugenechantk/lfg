# Track B (Reliability & Offline) — Pre-Merge Verification Evidence

**Date:** 2026-07-13
**Worktree:** `.claude/worktrees/track-b-reliability` (branch `worktree-track-b`, HEAD `1bb49ed`)
**Plan:** `.claude/brainstorm/multihost-first-rearchitecture.md` → Track B = Phases 3–6
**Status vs main:** 5 commits ahead, **9 commits behind** (divergent; not yet merged)

## What Track B is

The reliability/offline track of the multi-host rearchitecture — the phase *after*
Track A (connectivity, Phases 0–2, already merged to main). Covers:

- **Phase 3** — durable, idempotent server sends (`src/sendq-store.ts`, `src/sendq.ts`)
- **Phase 4** — client GRDB persistence (`LFGStore.swift`, `LFGStoreRecords.swift`) + SessionStore hydration
- **Phase 5** — outbox + delivered-ack identity resolution
- **Phase 6** — session leases / single-execution enforcement (`src/leases.ts`)

## Verification results

| Seam | Method | Result |
|---|---|---|
| Server full suite | `bun test src/` | **113/113 pass** |
| Durable sendq survives restart | existing test reopens real on-disk SQLite (`sendq-store.test.ts:192-204`) | ✅ real-seam |
| Idempotent send dedup | `enqueueMessage`→`duplicate:true`, `getMessageByClientId` (`sendq-store.test.ts:96-113`) | ✅ real-seam |
| Cross-host lease rejection (module) | two hostIds, real lease files (`leases.test.ts:81-142`) | ✅ real-seam |
| **Cross-host lease rejection (live HTTP)** | booted server :8799, planted fresh foreign lease, `POST /api/sessions/fork` | ✅ **409 + `liveOn` echoes planted hostId** (2 cases) |
| iOS `LFGCore` full suite | `swift test` | **124/124 pass** |
| **iOS on-disk persistence across reopen** | **added** `LFGStorePersistenceTests.swift` — write to file-backed store, drop, reopen same path | ✅ **passes** (host/sessions/transcript/cursor/read-state all survive) |

### Gap found & closed
Every pre-existing `LFGStoreTests` case used `LFGStore.inMemory()`, so the on-disk
persistence-across-launch path (the Phase 4b "SessionStore hydrates from disk on cold
start" promise) was **never exercised**. Added `LFGStorePersistenceTests.swift` to close
it — a real file-backed write → teardown → reopen round-trip. Passes.

### Live HTTP lease check (detail)
- `resolveTranscript` scans the real `~/.claude/projects` and requires a UUID, so a
  throwaway UUID transcript + lease was planted in a uniquely-named temp subdir there and
  removed on exit. The 409 fires **before** `spawnManagedSession`, so no real session was
  ever launched (verified: no process matched the test UUID).
- CASE 1 → `409 {"error":"session is live on another host","liveOn":"verifier-remote-peer"}`
- CASE 2 → `409 {... "liveOn":"eugenes-air-peer"}`
- The route echoes the exact hostId from the planted lease file → confirms serve.ts reads
  the real lease, not a generic rejection.

## Still UNVERIFIED (requires hardware — do before merge)

- **iOS outbox survives app-kill, end-to-end** (Phase 5): send → kill app mid-send →
  exactly-once delivery on relaunch. Needs a device; `simctl` can't drive background send.
- **Background push wake → delta sync** (Track A/B boundary): `simctl push` can't wake
  background `didReceiveRemoteNotification` — device-only.
- These are the plan's declared non-compressible **multi-day TestFlight soak**.

## Merge blockers (separate from verification)
1. Device soak of the outbox/background paths above.
2. **Divergence:** 9 commits behind main, touching hot files main has since changed
   independently (`sendq.ts`, `serve.ts`, `SessionStore.swift`, `LFGClient.swift`).
   A rebase/merge with conflict resolution is required before landing.

## Shipped to main + TestFlight (2026-07-13)
- Reconciled diverged `main`: merged Track B (`origin/main`) with a parallel session's
  unpushed fork-transcript-loading work (`local main`). One conflict in
  `serve.ts` `forkSession()` — kept BOTH post-fork actions (`patchManaged` + `acquireLease`).
- Combined tree verified: **server 133/133, iOS 132/132, no new tsc errors**.
- `main` is now `5e53740` (Track B + fork-detail). Pushed to origin.
- Restarted the production lfg server (pid 24110) on merged code — HTTP 200 verified.
- **TestFlight: build `202607132328` (v1.1.0) — DoD PASS: VALID, highest train,
  IN_BETA_TESTING.** Included the (still-uncommitted) sent-bubble caption per owner's call.
- The Phase 5 outbox/background device soak now runs live via this TestFlight build.

## Verdict
Track B's **logic is verified at the real seam** (durability, dedup, leases, on-disk
persistence — server + client). What remains before merge is the device soak of the
background/outbox paths and resolving the divergence with main. It is not
half-finished scaffolding — it is a complete, tested track awaiting soak + integration.
