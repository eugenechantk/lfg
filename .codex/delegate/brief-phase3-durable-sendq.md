# Delegation Brief: phase3 — durable sendq + clientId idempotency + delivered acks

**Goal:** a server restart no longer drops queued/in-flight sends; duplicate send POSTs are
safe (client-generated `clientId` dedupe); and delivery confirmation is journaled as a
`queue` event `{clientId, delivered: true, userTurnId}` so clients can later swap optimistic
bubbles by identity (Phase 5 consumes this — do NOT build any client code now).

**Repo:** worktree root of `lfg`. Bun + TypeScript, `bun test`. Work ONLY in `src/` (+ tests).
Do NOT touch `ios/`, and do NOT change sendq's delivery/confirm mechanics (the tmux typing,
composer scraping, hold-in-lfg gating, redelivery logic in `src/sendq.ts` stay EXACTLY as-is
— only WHERE queue state lives and what gets emitted changes).

## Context (read first)

- `src/sendq.ts` — `QueuedMsg`, per-session queues (`Map`), `enqueue`/pump/delivery loop;
  note where a message transitions to `delivered` (transcript-growth confirm) and to
  `failed`. This is the persistence seam.
- `src/journal.ts` — bun:sqlite db at `PATHS.data/journal.db` (WAL). Journal.append shape:
  events are `{sessionId, type, payload}` where payload is the exact SSE data JSON string.
- `src/journal-pump.ts` — how other components journal (via the Journal instance handed
  around in `src/commands/serve.ts`).
- `src/commands/serve.ts` — `POST /api/sessions/:id/send` handler (find it; note the response
  shape `{ok, msg?, resumed?, sessionId?}` — must stay back-compatible), and where `journal`
  + sendq are wired in `cmdServe`.
- `src/sessions.ts` — `recentMessages` (used by the confirm loop; the delivered user turn's
  message id is discoverable there — that id is `userTurnId`).

## Spec

1. **Persist queue rows** (`src/sendq-store.ts`, new): a `sendq` table in the SAME journal
   db (accept the db handle or path; open with bun:sqlite WAL like journal.ts):
   `(id TEXT PRIMARY KEY, sessionId TEXT, clientId TEXT, text TEXT, status TEXT,
   error TEXT, attempts INTEGER, redeliveries INTEGER, createdAt INTEGER, updatedAt INTEGER)`
   + index on (sessionId, clientId). Write-through from sendq.ts: the in-memory Map stays
   the hot path; every status/attempt mutation upserts the row; terminal rows (delivered/
   failed) may be pruned on the same cadence sendq already trims in-memory lists.
2. **Boot recovery:** on first use after process start, load non-terminal rows
   (pending/sending/queued) into the in-memory queues — status "sending" downgrades to
   "pending" (the type-in-progress died with the old process; the existing delivery loop
   re-drives it; its confirm/redelivery logic already tolerates a duplicate landing —
   do not add new dedupe there).
3. **clientId idempotency:** POST /send accepts optional `clientId` (string ≤128 chars).
   - No clientId → server generates one (uuid) so every row has one.
   - Same (sessionId, clientId) seen again while a row exists (any status incl. terminal,
     within the retention window) → do NOT enqueue; return the existing row's state in the
     normal response shape plus `{clientId, duplicate: true}`.
   - Response gains `clientId` always. Existing fields unchanged.
4. **Journaled ack:** where sendq marks a message `delivered`, journal an event for that
   session: type `queue`, payload JSON `{"kind":"delivered","clientId":"…","msgId":"<queue
   row id>","userTurnId":"<message id of the confirmed user turn>"}`. Get `userTurnId` from
   the transcript-growth confirmation the loop already does (the newest user message it
   matched); if genuinely unavailable, journal with `userTurnId: null` rather than blocking
   delivery. Also journal `{"kind":"failed","clientId":…,"msgId":…}` on terminal failure.
   Wire the Journal instance into sendq via an injected setter from cmdServe (match the
   existing dependency-injection style; sendq must still work with no journal set — tests).
5. **No behavior change** for: hold-in-lfg gating, typing/confirm, redeliveries, queue API
   shapes (`/queue` listing), interrupt/stop paths.

## Verification (run all; paste output)

1. New tests (`src/sendq-store.test.ts` or extend existing): row round-trip; boot recovery
   incl. sending→pending downgrade; clientId dedupe (second enqueue returns existing);
   prune behavior; ack journaling (use a Journal on a temp db, assert the event row).
2. **Restart simulation test:** enqueue N messages into a temp-db-backed store, tear down
   the in-memory state (fresh module-level state or exported reset hook), re-init from the
   same db, assert the queue resumes with the same messages.
3. `bun test` — ALL suites green.
4. If you can bind ports: boot a scratch serve (`LFG_DATA=/tmp/codex-p3 LFG_PORT=8798`),
   POST /send twice with the same clientId to any session id, show the duplicate response.
   If sandbox blocks binding, say so — the delegator runs it.

## Definition of done
- [ ] Queue rows survive process restart; delivery resumes (test-proven).
- [ ] (sessionId, clientId) idempotent; response back-compatible + clientId.
- [ ] delivered/failed acks journaled as `queue` events; replayable via /api/events.
- [ ] Zero changes to delivery/confirm mechanics; all suites green.

**Report back:** files changed, test output, the restart-simulation evidence, curl output
(or sandbox limitation), any deviation.
