# Track B — post-soak deletion checklist (Phases 5b + 7)

**Gate to start any of this:** the Track B additive layer (Phases 3–6) has soaked on
TestFlight through days of real use — sends resolving by identity ack, offline launch
working, no outbox stuck-rows, no lease false-409s. Nothing below is deletable before its
replacement has proven out in the field. Source: proposal §9.

## 5b — client: the reconcile-by-text stack (replaced by clientId acks, Phase 5a)

- [ ] `reconcilePendingViaQueue` + `retryPending`'s text-matching branch (`matchText`)
- [ ] `reconcilePending` / `correlatePending` fuzzy-text matching in SessionStore
- [ ] The view-layer duplicate filter (transcript vs pending bubble text dedupe)
- [ ] The poll safety-net that re-checks pending sends against fresh queue snapshots
- [ ] `PendingSend.matchText`-driven resolution generally — bubbles resolve ONLY via
      `queue {kind: delivered, clientId}` acks + outbox rows after this
- Keep: `remap(from:to:)` (session-identity remap on resume is orthogonal), optimistic
  bubble RENDERING (only its resolution mechanism changes), failed-bubble Retry UI.

## 7 — the legacy sweep (server + client residue, per §9)

Server:
- [ ] Per-connection stream pumps + delta maps (superseded by journal + global pump)
- [ ] 40-message backfill + init sentinel + 24-id cap + `ids=` protocol remnants
- [ ] `lastGood` list cache (journal cursors made it redundant)
- [ ] In-memory-only sendq remnants (Map stays as hot cache — delete any code path that
      assumes rows can't outlive the process)

Client:
- [ ] 3s→60s poll: evaluate dropping the 60s reconcile to a much slower safety net once
      store hydration + events are proven (do not delete outright — it is the
      unknown-event-type safety net)
- [ ] `seen` sets (store upsert idempotency replaced them)
- [ ] REST-busy seeding (journal busy events are strictly fresher — verify first)
- [ ] `lastSessionsByHost` in-memory snapshots → read from LFGStore
- [ ] `closedCache` / `resumeTick%4` residue
- [ ] Failure-count debounce (HostLink/NWPathMonitor state machine replaced it)
- [ ] `focusedSnapshot` / `deepLinkSession` carry-forwards (store makes them redundant)
- [ ] Clock-skew read-state comparisons (identity-based `lastSeenMessageId` everywhere)
- [ ] UserDefaults cursors + read-state (store is authoritative; delete the mirror)

## Each deletion's protocol

One deletion per commit; before each: grep for every consumer, run the full suites, and
exercise the affected surface live once (send, resume, offline launch, unread). The ~25
workarounds die one at a time, not in a sweep commit.
