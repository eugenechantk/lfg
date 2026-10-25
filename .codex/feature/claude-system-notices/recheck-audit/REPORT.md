# Independent recheck: PASS at source-contract scope

The current checkout satisfies SC1–SC5 within the documented host and client-contract scope. This recheck found no new request-relevant defect.

The deployed outcome remains unverified. This report does not prove that current sessions display the fix.

## Evidence

- `tests.txt`: 67 tests pass across the notices, session state, and journal pump suites. No failures.
- `probe.ts`, `probe-output.txt`, and `probe-results.json`: separate assertions use the saved real pane and an isolated provider fixture.
- The probe launches a fresh Bun process. The incident keeps its stable ID and count when the retry countdown changes.
- All probe files, including the isolated JSONL fixture and its sidecar, remain in this audit directory.

## Criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: Recognize the live limit format without ordinary prose | PASS | The saved real weekly meter yields its exact retry and reset details. Tests reject ordinary assistant prose, old scrollback, composer input, and fenced quotations. |
| SC2: Persist each incident without countdown duplicates | PASS | The fresh-process probe preserves one ID and one row. Tests preserve active state across failed captures and incomplete renders. Complete recovery clears active state. The isolated provider JSONL stays byte-identical. |
| SC3: Journal, history, and pagination | PASS | The probe confirms stable journal publication and matching recent/full/paged history IDs. Tests cover deferred publication until the provider tail catches up and replay after pump restart. |
| SC4: Paused status and recovery | PASS | The actual-pane probe produces `blocked`, `usage_limit`, and exact retry details. Tests cover stale question suppression and the long-retry busy override. Source paths in REST, journal, and push use that override. |
| SC5: Existing API error rendering contract | PASS, source only | Swift decodes `apiError: true` on the assistant text message. Components adds the orange API error label. `isBlocked` enables the paused banner. `usage_limit` uses the generic Build paused title, while `statusDetail` shows retry details. SessionStore deduplicates journal replay by stable ID. |

## Source paths inspected

- `src/claude-system-notices.ts` and its tests.
- `src/sessions.ts`, `src/journal-pump.ts`, and `src/session-state.ts`.
- `src/commands/serve.ts` and `src/push/watcher.ts`.
- `ios/LFGCore/Sources/LFGCore/Models.swift`.
- `ios/LFG/Components.swift`, `ios/LFG/SessionDetailView.swift`, and `ios/LFG/SessionStore.swift`.

## Limits

No current weekly-limit pane was available for live reproduction. The saved pane is historical evidence, and the probe uses it as a fixture.

The parent reports that the running host predates this module and has not loaded the fix. That deployment observation was not independently repeated by this auditor.

There is no visual rendering evidence or deployed-host verification in this recheck. Client rendering is verified by the source contract only. The parent separately owns the broader regression suite and type check.

This auditor did not restart or deploy the host, send session inputs, launch Apple apps, edit product code, or alter provider transcripts or databases.
