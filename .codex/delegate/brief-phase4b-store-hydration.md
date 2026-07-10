# Delegation Brief: phase4b — SessionStore hydrates from + writes through LFGStore

**Goal:** the app renders from durable state: a cold launch with every host unreachable
(airplane mode) shows the full session list AND recently-viewed transcripts from the local
LFGStore instead of a blank screen. Live behavior is unchanged — the network paths keep
working exactly as they do; LFGStore becomes the substrate they hydrate from and write to.

**Repo:** worktree of `lfg`. Allowed files: `ios/LFG/SessionStore.swift`,
`ios/LFG/LFGApp.swift` (store construction/injection only), `ios/LFGCore/**` (small
additive helpers on LFGStore if needed, with tests). Do NOT touch `src/`,
`SessionListView.swift`, `SessionDetailView.swift`, project.yml, or any push/Live Activity
files. **Everything is ADDITIVE** — no existing path is deleted or behaviorally changed
while hosts are reachable; hydration only fills otherwise-empty state.

## Context (read first)

- `ios/LFGCore/Sources/LFGCore/LFGStore.swift` + `LFGStoreRecords.swift` — the Phase 4a
  layer (upsert ingestion, bounded messages, cursors, readState). Just landed; read its
  actual API, don't guess.
- `ios/LFG/SessionStore.swift` — the @MainActor view-model. Key seams:
  `applyHostFetch(_:)` (REST snapshot per host), `apply(_ ev: LiveEvent)` (stream reducer),
  `loadHistory(_ sid:)` / transcript handling (`transcripts` dict), `markOpened`
  (read-state, UserDefaults-backed `lastSeenMessageID`/`lastOpenedAt`), the 60s poll, and
  `start()`.
- `ios/LFG/HostLink.swift` — `reloadCursor()`/cursor persistence via
  `HostLinkPolicy.cursorKey` (UserDefaults). Cursors STAY in UserDefaults this phase
  (moving them is riskier than it's worth until the store is proven; mirror writes only).
- `ios/LFG/LFGApp.swift` — where SessionStore is constructed.

## Spec

1. **Store lifecycle:** construct one `LFGStore` at
   `Application Support/lfg-store.sqlite` (create dir; falls back to in-memory on open
   failure — never crash launch) in `LFGApp`/SessionStore init; hold it on SessionStore.
2. **Write-through (fire-and-forget Tasks off the hot paths, never blocking UI):**
   - `applyHostFetch` success → `upsertHosts` (that host) + `upsertSessions(sessions,
     hostId: host.id)`.
   - Wherever transcripts are set/appended (REST history load AND stream message events) →
     `appendMessages(sessionId:, …)` with the same Message values.
   - `markOpened`/read-state updates → `markSeen(sessionId:lastSeenMessageId:)`.
   - HostLink cursor advances: mirror `setCursor(hostId:seq:)` alongside the existing
     UserDefaults write (find the single choke point; do not restructure HostLink).
3. **Cold-launch hydration:** in `start()` (or init), BEFORE any network result arrives:
   read stored hosts/sessions and populate the in-memory session list state ONLY where
   empty (`lastSessionsByHost[hostId]` nil etc. — additive, first-writer-wins with real
   fetches); populate `lastSeenMessageID` from readState for unread computation. Hydrated
   sessions must render in the list exactly like fetched ones (they flow through the same
   merge the 60s reconcile uses — reuse that code path, do not build a parallel one).
4. **Transcript hydration:** when a session detail opens (`focus`/loadHistory path) and the
   network fetch fails or hosts are unreachable, populate `transcripts[sid]` from
   `store.messages(sessionId:)` if in-memory transcript is empty. (If the fetch succeeds it
   wins as today.)
5. **One-time seed:** on first run with an empty store, seed readState from the existing
   UserDefaults `lastSeenMessageID` map so unread states don't reset (flag key in
   UserDefaults to run once).
6. Swift 6 strict concurrency; LFGStore calls are async — hop appropriately; no UI stalls.

## Verification (run what the sandbox permits)

1. `cd ios/LFGCore && swift test` green (115 + any you add).
2. Build: `cd ios && flowdeck build --workspace LFG.xcodeproj --scheme LFG --simulator
   D69C6DC8-241A-4DAA-A148-8A969CA25A55` (if sandbox blocks, say so).
3. State the exact flow for: cold launch offline (what renders, from where), cold launch
   online (hydration vs fetch race), reopening a previously-viewed session offline.

## Definition of done
- [ ] Cold launch with unreachable hosts renders the stored list + stored transcripts of
      previously opened sessions (the airplane gate — delegator verifies live).
- [ ] All writes-through wired (sessions, messages, read-state, cursor mirror).
- [ ] Zero behavior change while online; no deletions; suites green.

**Report back:** files changed, the three flows, test/build output, deviations.
