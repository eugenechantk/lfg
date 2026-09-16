# Feature: Authoritative Idle Status

## User Story

As an LFG user, I want a completed agent turn to leave the Working/Running state promptly so that the session list and detail view reflect what the agent is actually doing.

## User Flow

1. A session is working and the client receives `busy: true` from the live journal.
2. The turn finishes while the live stream is delayed or reconnecting.
3. A fresh `/api/sessions` snapshot reports `busy: false`.
4. LFG immediately renders the session as idle/unread instead of preserving the older live claim for an arbitrary minute.

## Success Criteria

- [x] SC1: A REST snapshot whose request began after the last journal busy statement immediately wins, including `busy: false` clearing a stale Working state. — **Verify by:** `JournalFreshnessTests` ordering cases.
- [x] SC2: A journal busy statement received after a REST request began still wins over that in-flight snapshot, preventing a stale response from clearing genuine work. — **Verify by:** `JournalFreshnessTests` ordering cases.
- [x] SC3: Snapshots without request-order evidence retain the existing bounded TTL fallback. — **Verify by:** existing and expanded `JournalFreshnessTests`.
- [x] SC4: The iOS client records each successful host snapshot's request start and uses it for busy and prompt reconciliation. — **Verify by:** iOS build plus source-level feature assertion.

## Test Strategy

Use deterministic LFGCore unit tests for the timestamp arbitration boundary, then build the full iOS app. Because the result changes the visible session group, verify the concrete regression session in Simulator and obtain an independent visual audit.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/JournalFreshnessTests.swift`
  - snapshot requested after journal statement wins immediately (SC1)
  - journal statement during an in-flight snapshot wins (SC2)
  - unknown snapshot ordering retains TTL behavior (SC3)

### Integration/Build

- Full `LFG` scheme build through FlowDeck (SC4)
- Source assertion that `HostFetch.snapshotStartedAt` reaches both busy and prompt arbitration sites (SC4)

## Implementation Details

The existing 60-second journal veto conflates two cases: a journal event that arrived during an in-flight REST request, and a journal event that is merely recent but predates the request. Record the per-host REST request start. A snapshot is authoritative when that start is at or after the journal statement; TTL remains only when ordering is unknown or the event arrived during the request.

## Decision Log

- Keep both sources rather than making REST unconditionally win. An SSE event can legitimately arrive after a REST request began, making the response older even if it completes later.
- Apply the same ordering rule to prompt reconciliation because it uses the same two-source arbitration contract.

## Residual Risks

- A host that is unreachable cannot provide a fresh snapshot; existing offline-state retraction remains responsible for that case.
- If both the stream and REST refresh are unavailable, no client can infer a remote state transition.

## Verification Evidence

- `swift test --filter JournalFreshnessTests` — PASS, 11 tests. The pre-implementation run failed because `snapshotStartedAt` did not exist; the same suite passed after implementation.
- `swift test` in `ios/LFGCore` — PASS, complete package suite.
- `flowdeck build --json` — PASS for the `LFG` iOS scheme.
- `git diff --check` — PASS.
- FlowDeck runtime on simulator `1602A30A-1098-4389-B1DA-42CB464A4FB1` — the concrete completed session `01a05b67-f7e3-73b2-85b4-e5c502c1a641` rendered under **Unread**, not **Working**; the active verification session rendered under **Working** at the same time.
- Independent visual audit — **PASS**. Report and captured runtime evidence: `.codex/evidence/20260901-152602-ios-visual-audit/evidence.md`.

## Bugs

- Regression case: `codexy-131852-30047` / `01a05b67-f7e3-73b2-85b4-e5c502c1a641`; server snapshot and final journal event both report `busy: false`, while the client sometimes remains Running.
