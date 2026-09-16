# Feature: child-agents-survive-host-routing

Diagnosis: `.claude/diagnosis-child-agents-missing-in-detail-20260907.md`.

## User Story

As the lfg iOS user, I want the session view's child-sessions bar and the "Child sessions (N)"
menu entry to agree with the list row's 👥 N badge, so that when the list says agents are
running I can always open them.

## User Flow

1. A Claude session spawns background agents; the list row shows `👥 2`.
2. The owning host drops to connecting/degraded (foreground return, tunnel blip) or the peer is
   the only reachable host.
3. User opens the session → the bar above the composer and the More-menu entry still list the
   agents the badge counted.

## Success Criteria

- [x] SC1: `GET /api/sessions` rows carry `childAgents` (id, description, agentType, spawnDepth,
  status, timestamps) whenever the sidecar list is non-empty — **Verify by:** `bun test
  src/subagents.test.ts` (`withSessionWorkActivity` exposes the array) + live curl on 8766.
- [x] SC2: `Session` decodes `childAgents` leniently (absent → `[]`) — **Verify by:**
  `ModelsTests.testDecodeSessionChildAgents` (swift test).
- [x] SC3: The store seeds `childAgentsBySession[sid]` from the row when it has no entry yet, and
  never lets an empty row clobber a populated entry — **Verify by:**
  `ChildSessionsBarVisibilityTests.testSeed*` (in ChildAgentSessionTests.swift) on the pure `ChildAgentSnapshotMerge` rule (swift test).
- [x] SC4: The per-session `/subagents` read goes to the OWNER (send routing), and a failure
  from a non-owner host never writes `[]` — **Verify by:** code path uses `client(forSession:)`;
  `ChildSessionsBarVisibilityTests.testFetch*` (in ChildAgentSessionTests.swift) for 404-from-peer vs 404-from-owner.
- [x] SC5: Live: with the phone's owner host forced non-live and a session showing 👥 N, the
  detail view shows the bar + menu entry — **Verify by:** simulator run against the Pro with a
  spawned two-agent session; screenshot of bar + menu. (Peer-404 path exercised via SC4's unit
  test; the sim proves the seed path renders.)

## Platform & Stack

- **Platform:** Bun server (TypeScript) + iOS (SwiftUI, LFGCore package)
- **Tests:** `bun test`, `swift test` in `ios/LFGCore`, FlowDeck sim for SC5

## Steps to Verify

1. `bun test src/subagents.test.ts src/sessions.test.ts`
2. `cd ios/LFGCore && swift test --filter 'ChildAgent|Models'`
3. Restart the Pro server (by port), curl `/api/sessions` for a row with `childAgents`.
4. FlowDeck: build+run on the session sim, open a session with agents, screenshot bar + menu.

## Implementation Phases

### Phase 1: Server row carries the agents
- Scope: `withSessionWorkActivity` adds `childAgents` (omitted when empty to keep old payloads byte-identical); `Session` type gains the optional field.
- SC1. Gate: bun tests green.

### Phase 2: Client decode + merge rule + owner-pinned read
- Scope: `Session.childAgents`; `ChildAgentSnapshotMerge` (pure, LFGCore); `SessionStore.rebuildSessions` seeds; `refreshChildAgents` uses `client(forSession:)` and the merge rule.
- SC2–SC4. Gate: swift tests green, app builds.

### Phase 3: Live verification
- SC5.

## Decision Log

- **Row carries the full agent list, not just the count.** The list endpoint already has the
  array in hand; sending it costs a few hundred bytes per active row and makes the two surfaces
  share one source. Alternative (persist child agents in GRDB) covers cold launch too, but the
  badge itself isn't persisted, so the surfaces already agree there.
- **Reads pinned to the owner via `client(forSession:)`.** Sidecars are only guaranteed on the
  owner; the peer's synced copy lags minutes. `readRouteHost` stays for transcripts, which have a
  local fallback.
- **Seed-if-nil, never clobber with empty.** Avoids the JournalFreshness trap of a frozen row
  re-asserting stale statuses over a fresher poll result.
- **Omit `childAgents` when empty** so the REST payload for idle sessions is unchanged.

## Verification Evidence

| SC | Method | Result |
| --- | --- | --- |
| SC1 | `bun test` (781 pass / 0 fail across 66 files, incl. new `withSessionWorkActivity` cases); `bunx tsc --noEmit` clean; Pro server restarted 17:28:37 (pid 10001), `GET /api/sessions` → 7 rows carry `childAgents` (e.g. `410abeb6` → 3 completed), 13 idle rows have no key | PASS |
| SC2 | `swift test` in `ios/LFGCore`: 476 pass / 0 fail; `ModelsTests.testDecodeSessionChildAgentsLeniently` covers present / absent / malformed | PASS |
| SC3 | `ChildSessionsBarVisibilityTests.testSeed*` (3 tests) on `ChildAgentSnapshotMerge.seed` | PASS |
| SC4 | `refreshChildAgents` now routes via `MultiHost.routeHost` (send semantics); `ChildSessionsBarVisibilityTests.testFetch*` (3 tests) on `applyFetch` | PASS |
| SC5 | FlowDeck sim `cc-2d0acb33` (iPhone 17 Pro), fixed build against the Pro (`127.0.0.1:8766`): probe session `50980bea` with two running agents → list row `👥 2`, detail shows `2 child sessions, 2 running` bar (AX id `childSessionsComposerBar`) and More menu `Child sessions (2)` (screenshots in the FlowDeck session dirs `148B24CF`/`EDE23BCD`). Later, with the Pro reached only through a local proxy that was then killed and the Air set as default host, the bar stayed on screen 75 s into the outage. **Caveat:** the same held on a control build with the old routing, because the rig needed a second Pro entry (the bundled tunnel host) and the client keeps that reachable route; removing it triggers an unrelated multi-host quirk that hides the machine's live rows (see Bugs). The peer-404 path is therefore proven by SC4's unit tests + the diagnosis probe (Air 404s the live transcript), not by an end-to-end control. | PASS (positive path); control inconclusive |

## Bugs

_None open in this change._

**Follow-up observed (not this change):** with two host entries for the same machine (e.g.
a loopback URL plus the bundled tunnel URL, same `hostId`), removing one in Settings hides
that machine's LIVE sessions from the list even though the remaining entry stays green and
keeps answering `GET /api/sessions` (stub log showed the polls landing). Closed rows from the
peer still show. Reproduced twice on 2026-09-07 in the sim (old and new build alike).

Independent audit: PASS — `.claude/evidence/20260907-181146-child-agents-audit/`.
