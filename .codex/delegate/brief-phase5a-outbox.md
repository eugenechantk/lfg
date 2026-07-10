# Delegation Brief: phase5a — outbox on the store, resolved by delivered acks (ADDITIVE)

**Goal:** sends survive app death with exactly-once semantics, end to end: every message
send writes an `outbox` row (keyed by `clientId`) before transport; the server's Phase 3
journal ack `queue {kind:"delivered", clientId, userTurnId}` resolves the row AND the
optimistic bubble BY IDENTITY. On launch, unresolved outbox rows are retried — safely,
because the server dedupes by clientId. **ADDITIVE ONLY:** the existing reconcile-by-text
machinery stays fully intact and running (its deletion is a later phase, after soak).

**Repo:** worktree of `lfg`. Allowed: `ios/LFGCore/**` (client protocol + decode + store
helpers, with tests), `ios/LFG/SessionStore.swift`, `ios/LFG/BackgroundSender.swift`
(only if the body needs clientId plumbed). Do NOT touch `src/` (server is DONE — Phase 3
landed the acks), views, project.yml, HostLink, push files.

## Context (read first)

- Phase 3 server behavior (already on this branch): POST /api/sessions/:id/send accepts
  `clientId`; duplicates return `{duplicate: true, msg}`; response always carries
  `clientId`. Delivery journals a session event type `queue` with payload
  `{"kind":"delivered","clientId":…,"msgId":…,"userTurnId":…}` (or `kind":"failed"`).
  See `src/sendq.ts` journalDelivered/journalFailed for exact shapes.
- `ios/LFGCore/Sources/LFGCore/SSEParser.swift` + wherever `LiveEvent` decodes `queue`
  frames today — the new ack payload rides the SAME event type; the decoder must surface
  it (lenient: a queue event without `kind` is the legacy queue-list shape and must keep
  decoding as today).
- `ios/LFGCore/Sources/LFGCore/LFGStore.swift` — the `outbox` table exists (schema:
  clientId PK, sessionId, hostId, text, state, createdAt, updatedAt) with NO methods yet.
- `ios/LFG/SessionStore.swift` — `dispatchSend` (composer path via BackgroundSender),
  `retryPending`, `pendingSends` bookkeeping, `mutatePending`. Read how a send currently
  resolves (response msg → confirmed) and how failures mark bubbles.
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift` — `sendMessage`, `sendMessageRequest`.

## Spec

1. **clientId on the wire:** `sendMessageRequest`/`sendMessage` gain an optional
   `clientId: String?` included in the POST body. `PendingSend` (or the dispatch path)
   generates a UUID clientId per send and threads it through composer + retry paths.
2. **LFGStore outbox methods (+tests):** `enqueueOutbox(clientId:sessionId:hostId:text:)`
   (state "pending"), `markOutbox(clientId:state:)` (sent/delivered/failed),
   `pendingOutbox()` (non-terminal rows), `deleteOutbox(clientId:)`. Terminal rows delete
   on delivered; failed rows persist for the retry UI.
3. **Dispatch integration (SessionStore):** on send: write outbox row (write-through
   style, but AWAIT this one before the transport fires — the row IS the crash-safety),
   then existing transport; on HTTP response: mark "sent" (row survives until the ACK
   proves delivery). Existing response handling unchanged.
4. **Ack consumption:** in the LiveEvent reducer (`apply`), on a queue event with
   `kind == "delivered"` and a clientId matching a pendingSend → resolve that bubble by
   identity (confirmed, same as today's resolution effect) and delete the outbox row.
   `kind == "failed"` → mark bubble failed + outbox row failed. Unknown clientId → just
   clean the outbox row if present (delivered elsewhere). This must also work via the
   background page sync (same reducer — verify it decodes there too).
5. **Launch reconcile:** on start, `pendingOutbox()` rows with no live pendingSend bubble:
   re-POST with the SAME clientId (server dedupes — safe), recreating a pending bubble so
   the user sees it resolve. Cap retries (attempts column or updatedAt age > 24h → mark
   failed). This is what closes the force-quit gap from Phase 2 Task C.
6. **No deletions**: reconcile-by-text, queue polling, `remap(from:to:)` all stay.

## Verification

1. `swift test` green (new: outbox round-trip, ack decode incl. legacy queue shape,
   identity-resolution reducer test if the reducer is LFGCore-testable; else state so).
2. Build for sim via flowdeck (if sandbox blocks, say so).
3. State the flows: (a) normal send with ack, (b) app killed after POST before ack,
   (c) app killed before POST fired, (d) duplicate ack for an already-resolved clientId.

## Definition of done
- [ ] Every send carries a clientId and has an outbox row before transport.
- [ ] Delivered/failed acks resolve bubbles + outbox by identity, live and via page sync.
- [ ] Launch reconcile retries unresolved rows with the same clientId; capped.
- [ ] Legacy queue-event decoding unbroken; zero deletions; suites green.

**Report back:** files changed, the four flows, test/build output, deviations.
