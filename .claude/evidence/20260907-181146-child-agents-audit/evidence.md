# Verification Audit

Verdict: PASS
Timestamp: 2026-09-07 18:11 (local)
Repository: /Users/eugenechan/dev/personal/lfg
Surface: mixed (Bun API + Swift package unit tests + code review of SessionStore hunks)

## Change Audited

child-agents-survive-host-routing (`.claude/feature/child-agents-survive-host-routing.md`).
Server `withSessionWorkActivity` (src/subagents.ts) now puts `childAgents` on each
`GET /api/sessions` row (omitted when empty); `Session.childAgents` decodes leniently
(ios/LFGCore/Sources/LFGCore/Models.swift); pure merge rule `ChildAgentSnapshotMerge`
(ios/LFGCore/Sources/LFGCore/ChildAgentSessions.swift); `SessionStore` seeds from rows and
routes the `/subagents` read to the owner via send semantics.

Scope restricted by caller: SC1–SC4 only. No simulator, no tmux, no server restart.
Running server: pid 10001, started Mon Sep 7 17:28:37 2026 — AFTER src/subagents.ts mtime
(17:27:36), so the live process runs the new code (03/04 logs).

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
| --- | --- | --- | --- |
| SC1a `bun test src/subagents.test.ts` passes | bun test | PASS — 21 pass / 0 fail | 01-sc1-bun-test-subagents.log |
| SC1b `bunx tsc --noEmit -p .` clean | tsc | PASS — no output, exit=0 | 02-sc1-tsc.log |
| SC1c live rows carry `childAgents` matching sidecar count; idle rows have NO key | curl 8766 | PASS — 18 rows: 8 with `childAgents`, 10 without; all 8 match `/subagents` by count AND id set (ALL_MATCH: True); 0 rows with a present-but-empty array; 5 sampled no-key rows all have `/subagents` agents=0; entry keys = agentType, description, finishedAt, id, lastActivityAt, spawnDepth, startedAt, status | 03-sc1-api-sessions.json, 04-sc1-row-vs-subagents-comparison.log, 05-sc1-subagents-*.json |
| SC2 `swift test --filter ModelsTests` incl. testDecodeSessionChildAgentsLeniently | swift test | PASS — 14 tests / 0 failures; the test asserts (a) absent key → `[]` (session "without"), (b) unknown status "weird-new-status" → `.unknown` + default description, (c) malformed value `"childAgents":"nope"` → `[]` without failing the session decode | 06-sc2-swift-test-ModelsTests.log; test source in ModelsTests.swift diff |
| SC3 seed: empty row never blanks; fresher row supersedes; tie keeps existing | swift test on `ChildAgentSnapshotMerge.seed` | PASS — testSeedFillsAnEmptyStoreFromTheRow, testSeedNeverClobbersWithAnEmptyRow, testSeedPrefersTheFresherSetAndKeepsExistingOnTie all pass | 07-sc3-sc4-swift-test-ChildAgent.log (second run) |
| SC4 fetch: 404/empty from non-owner never blanks; 404 from owner blanks; transport failure keeps | swift test on `applyFetch` | PASS — testFetchFromAPeerNeverBlanksWhatTheOwnerSaid (notFound + agents([]) with fromOwner:false keep existing), testFetchFromTheOwnerIsAuthoritativeEvenWhenEmpty (notFound/agents([]) with fromOwner:true → []), testTransportFailureKeepsTheSnapshotRegardlessOfHost | 07-sc3-sc4-swift-test-ChildAgent.log (second run) |

Rule source confirmed against the tests (ChildAgentSessions.swift lines ~205–260):
`seed`: `guard !row.isEmpty else { return existing }` → empty row never blanks;
`rowAt > existingAt ? row : existing` → strict greater, so tie keeps existing.
`applyFetch`: `.agents(a)` → `fromOwner || !a.isEmpty ? a : existing`; `.notFound` →
`fromOwner ? [] : existing`; `.failed` → `existing`.

## Artifacts

- 01-sc1-bun-test-subagents.log
- 02-sc1-tsc.log
- 03-sc1-api-sessions.json (raw GET /api/sessions, 57,576 bytes)
- 04-sc1-row-vs-subagents-comparison.log
- 05-sc1-subagents-{f6d7f271,a7536cc4,410abeb6,2eeecde2,96d9e70f,038215e0,5894849f,2d0acb33}.json
- 06-sc2-swift-test-ModelsTests.log
- 07-sc3-sc4-swift-test-ChildAgent.log
- evidence.md

## Commands

```
cd /Users/eugenechan/dev/personal/lfg
bun test src/subagents.test.ts
bunx tsc --noEmit -p .
lsof -nP -iTCP:8766 -sTCP:LISTEN -t                       # → 10001
ps -o pid,lstart,command -p 10001; stat -f '%Sm %N' src/subagents.ts
curl -s --max-time 60 http://127.0.0.1:8766/api/sessions  # saved as 03-*.json
# per row with childAgents:
curl -s --max-time 60 http://127.0.0.1:8766/api/sessions/<id>/subagents
cd ios/LFGCore && swift test --filter ModelsTests
cd ios/LFGCore && swift test --filter ChildAgentSessionTests
cd ios/LFGCore && swift test --filter ChildSessionsBarVisibilityTests
```

## Notes

- **Test-filter naming gap (not a defect, but affects reproducibility).** The caller's
  and feature doc's stated filter `ChildAgentSessionTests` runs only 5 presentation/decoding
  tests. The six `testSeed*`/`testFetch*` merge tests live in the
  `ChildSessionsBarVisibilityTests` class (same file). Both classes were run; both green.
  The feature doc's "Verify by" for SC3 says `ChildAgentSessionsTests.seedRule…`, which
  matches neither class nor method name.
- **SessionStore hunk review (ios/LFG/SessionStore.swift):**
  - `refreshChildAgents` (495–525): `owner = host(forSession:)`, `target = MultiHost.routeHost(
    owner:isClosed:reachable:agnostic:)` — identical inputs to `client(forSession:)` (473–479),
    so routing is send-semantics as claimed. `fromOwner = owner != nil && target.id == owner?.id`
    is correct for all four `routeHost` branches: owner reachable → owner (true); owner down +
    live → owner (true; the request then fails → `.failed` → snapshot kept); owner down +
    closed → agnostic (false unless same entry); owner unknown → agnostic (false). 404 is
    detected via `LFGError.http(404, _)`; all other errors → `.failed`. Writes are guarded by
    `merged != existing`, so no redundant writes; an owner-sourced `[]` IS written, which is
    the intended authoritative blank.
  - `rebuildSessions` seed (2489–2495): iterates `fresh` (the reconciled LIVE merge, which
    includes a down host's last-good snapshot rows — the exact rows carrying the badge), not
    `sessions`/`closed`. `closedSession(from:)` never sets `childAgents`, so seeding closed
    rows would be a no-op anyway. Guard `!s.childAgents.isEmpty` plus `seed`'s own empty-row
    guard means an empty row never touches the dictionary. No defect found.
  - Minor conservative behaviour, not a defect: two host entries for the same machine
    (different entry `id`, same `hostId`) make `fromOwner` false when the read lands on the
    sibling entry, so its 404 is treated as peer ignorance. Fails safe (keeps the snapshot).
- The live population at audit time had only one row with a `running` agent (2d0acb33 —
  this audit's own session); the other 7 carried `completed` agents. The count/id match
  holds for all 8, which is what SC1 requires.
- SC5 (simulator) was explicitly excluded by the caller and is not covered here.
- No source, test, or project files were modified. Only the evidence directory was written.
