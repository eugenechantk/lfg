# Diagnosis — stopped child agent latches a session "Working" on iOS (2026-10-04)

Session: `cy-173849-9408` (fiftyworkout, sid `6d81c2dd-6674-4c7c-9f37-3cd43843908b`), Pro host.

## Symptom
iOS list shows the session in **Working** (running-duration clock) long after its last turn
ended at 23:51 HKT on 2026-10-03.

## Ground truth (server is clean)
- `GET /api/sessions` on the Pro: `busy: false`, `runningChildAgentCount: 0`, child agent
  `a5192c704ffe99b77` has `status: "unknown"`.
- `journal.db`: last `busy` event for the sid is `busy:false` at 23:51:34.

## Chain
1. 17:52 the parent launched a background `ios_visual_evidence_auditor` child.
2. 18:07:46 Eugene stopped it. Its sidecar `agent-<id>.meta.json` records
   `"stoppedByUser": true`; no `<task-notification>` or tool_result completion is ever written.
3. **Server bug:** `src/subagents.ts` never reads `stoppedByUser`, so the child stays
   `running` until `RUNNING_STALE_MS` (30 min) flips it to `unknown`. The parent's turn ended
   at 18:08:49, but server `busy` stayed true until **18:37:50** — exactly 30 min after the
   child's last row.
4. **Client bug (the current symptom):** while the child read `running`, the iOS store cached
   it in `childAgentsBySession`. The later `unknown` row has the **same** `lastActivityAt`
   (staleness changes status, not timestamps). `ChildAgentSnapshotMerge.seed` keeps `existing`
   on a timestamp tie, so the cached `running` survives every list refresh.
5. `SessionStore.group(for:)` → `ChildAgentActivity.parentIsRunning` ORs in
   `agents.contains { $0.status.isActive }` → **Working**, indefinitely.

Only the detail view polls `/subagents` (`refreshChildAgents`, which overwrites via
`applyFetch`), and the cache is in-memory. So it clears on opening the session or a cold
launch, and otherwise lasts as long as the app process lives.

## Fixes (proposed, not yet made)
- **Client:** in `seed`, on a timestamp tie with differing status, let the non-active status
  win. Status only moves running → terminal/unknown without new activity; a return to running
  always brings a newer timestamp. This stays safe against the frozen-row trap the tie rule
  guards.
- **Server:** map `meta.json` `stoppedByUser: true` to `stopped` at once, which removes the
  30-minute busy latch on the parent.

## Workaround now
Open the session on the phone once (the detail poll corrects the cache), or force-quit the app.
