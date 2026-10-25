# Independent audit: automatic post-session outcome reconciliation

Verdict: **PASS for implementation and SC1–SC5, including deployed-host verification.**

## Scope

Reviewed the feature document, new queue worker, installed Python hook, and scheduler/API/outcome changes against the supplied baseline. Tests used temporary stores and stub session reads. No production implementation was edited. No database, live mutating API, phone, schedule, or service operation occurred in this audit.

## Findings fixed during review

1. A Stop event could be deleted before its task run's source-session binding was persisted. The worker now retains and retries unmatched events until its bounded expiry. An independent test executes the real hook, drains before binding, then binds and verifies later completion.
2. Taking the first 50 files before checking their retry times could delay later eligible events. The limit now counts eligible events. The regression suite verifies progress through a deferred backlog.

Both fixes were re-read and independently retested. No remaining blocking defect found.

## Success criteria

| Criterion | Verdict | Evidence |
|---|---|---|
| SC1: short durable hooks without network or continuation | PASS | Python hook only writes local files and exits zero with empty stdout. Existing lease tests pass. Queue-write failure still permits the original lease transition. Real Codex probe artifacts contain Stop and SessionEnd events pinned to UserPromptSubmit. Installed script matches reviewed source; hook configuration hashes remain unchanged. |
| SC2: automatic corrected outcome, original audit retained | PASS | Queue invokes the existing exact-run review operation through the real runtime and JSON store. Completion changes assessment fields while preserving original incomplete assessment, saved task settings, execution identity, and finish time. Explicit-review regressions preserve unrelated histories and reservations. |
| SC3: freshness, active/busy guards and replay safety | PASS | Active runs and busy sessions cannot change outcome. Trigger timestamps and optional hook outcomes guard against stale transcript results. Wrong-run, malformed and missing verdicts fail closed. Duplicate Stop/SessionEnd and event replay append at most one review. A mismatched hook turn cannot reuse the old turn marker. |
| SC4: durable retries and bounded needs-review result | PASS | Retry metadata persists to disk and worker re-instantiation resumes it. Busy and stale-transcript events wait; exhausted matching events receive needs-review receipts. Late source-session binding now survives. Unrelated sessions expire without changing task state. |
| SC5: installed event drains on deployed host | PASS | The installed-hook event drained automatically in 9.798 seconds, with changed:false and the whole store unchanged. Independently verified the live receipt, release bytes, and running host directory. |

## Independent evidence

- `independent-tests.txt`: **56 tests passed, 265 assertions**, across six files.
- `independent-probes.test.ts` adds three probes: real-hook late binding/busy wait/restart/replay; queue-write failure preserving lease behavior; mismatched turn refusing old identity.
- The queue-write failure probe completed within two seconds and produced no continuation output. Existing hook lifecycle tests confirm the normal lease fields and release semantics remain intact.
- `independent-hook-install-verification.json`: installed Python bytes match source; both hook configuration hashes match the install snapshot.
- `cli-probe/verification.json` and actual queue files confirm a real Codex run emitted Stop and SessionEnd, each after the recorded turn start. These are lifecycle-hook evidence, not production scheduled-run completion proof.

The first independent probe run expected an absent Python optional value to be omitted; the hook correctly serializes it as null. The test expectation was corrected and all probes rerun. This was an audit-test issue, not an implementation failure.

## Operational bounds

Reconciliation validates and synchronizes the session's final judgment. It does not grade report prose, restart the agent, control a phone, change completion criteria, or fix transport stalls. The queue uses the existing single-host TaskStore transaction model. Hooks can enqueue while the host is offline; the worker cannot process events until that host resumes.

## Live verification: SC5 PASS

Read-only verification confirms the installed-hook replay reached the deployed worker automatically. The receipt identifies the exact Jess session and run, reports `reviewed` with `changed:false`, and arrived 9,798 milliseconds after the event. The source queue file is gone and its durable receipt remains. Jess still has exactly one earlier outcome review.

The entire live task store equals both before/after proof snapshots. The task-list API agrees with the persisted Jess run. No saved task, schedule, attempt count, execution identity, other run, or audit entry changed during this idempotent proof.

The running host PID 23961 has the new release as its working directory. Its worker and scheduler bytes match reviewed source. The installed hook bytes match the release. A hash comparison against the preceding release found exactly the six declared changed/new files, excluding VCS/dependency directories. The scheduler starts the queue worker in its normal startup path.

Evidence: independent-live-verification.json, live-event.json, and the actual durable live receipt. This live proof replays a matching verdict for an already-completed run; automatic application of a changed verdict was verified in the isolated runtime tests. The real Codex lifecycle probe separately verified that normal Stop and SessionEnd hooks generate turn-pinned events.

**Final verdict: PASS for SC1–SC5.** The late-binding and deferred-backlog defects found during review are fixed. No remaining blocking finding. Independent live verification performed no mutations, service restart, phone operation, or database query.
