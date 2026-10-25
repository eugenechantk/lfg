# Independent verification

Result: PASS for the scoped implementation and completed runtime checks on Pro and Air.

## Verified

- Nine independent adversarial tests passed with 46 assertions after the recovery repair.
- Six existing regression files independently passed: 123 tests, 230 assertions.
- An explicit Codex turn stays running during six hours of silent tool work and repeated bookkeeping writes. Completion closes it immediately.
- Descriptor, launch, and fork matching reject child rollouts sharing their parent's process.
- Claude end_turn, stop_sequence, and API failure close the turn before delayed metadata. A later genuine prompt reopens it.
- The decisive transcript timestamp lets a Stop hook beat later metadata mtime.
- Claude tool execution remains running after fourteen minutes of silence.
- Structured reader, pane-less journal, and push observations agree on all recognized lifecycle fixtures.
- Read-only production requests succeeded. The catalog advertises gpt-6.1-sol as its default. The snapshot contained 35 sessions and 3 busy sessions.

## Finding

The initial repair left pickKnownCodexThread accepting a managed session's previously persisted child ID. The independent recovery test reproduced the gap. The final implementation rejects that child, selects the parent from open descriptors, and persists the corrected managed binding. The test now passes; the persistence branch was independently inspected.

## Limits

- The existing inferred Claude timeout remains fifteen minutes. It can demote a real long tool after that threshold. The tested fourteen-minute case does not prove longer tools remain running.
- Deployed Pro status logic was independently checked through read-only REST and transcript boundaries. Air API health, CLI version, and model availability/default were independently checked over SSH. No restart or session control was performed by this audit.
- REST enumeration's wiring was inspected and covered by the existing parity tests; the audit's direct consumer replay exercises the shared reader, journal helper, and push observer.
- No product source was changed by this audit.

## Evidence

- independent.test.ts and independent-output.txt
- recovery-red.txt
- regression-output.txt
- live-models.json and live-sessions.json

## Deployed Pro verification

- The child rollout 01a159d9-752d-70f1-aa30-b24a940b06e3 does not appear as a terminal session.
- The abandoned paywall 89d4222d-32c8-45e5-bed5-9f5dd0b37e15 is idle.
- Parent 01a1577f-4140-70e3-95ba-63c21cc1bf0d is idle because its transcript actually completed at 15:20:14.882Z. It also completed an earlier turn at 15:19:11.333Z. This confirms completion detection; it cannot prove active work survived the rollout.
- Another live Codex session, 01a159de-6074-72c1-8828-018379fc072d, remains busy and its latest explicit lifecycle boundary is task_started at 15:11:48.631Z.
- Independent snapshot and boundary evidence: deployed-sessions.json and deployed-busy-boundaries.json.
- Deployment logs for both hosts report preserved schedules and sessions, plus verification of 277 manifest files. The audit did not independently restart either host.

## Final runtime evidence

- Independently reviewed pro-live.json: eight snapshots over 48.7 seconds keep active Codex 01a159de-6074-72c1-8828-018379fc072d busy throughout. Every snapshot excludes the false child terminal binding and keeps the abandoned paywall idle.
- The journal contains no busy transitions for that active session or the false child during this window. Other sessions have actual busy transitions, so this is not evidence of a frozen journal.
- Independently queried Air over SSH: /api/info and /api/models succeed; codex-cli is 0.163.0; gpt-6.1-sol is available and the default. Evidence is air-independent.json.
- Reviewed Air's completed verification evidence in air-live.txt: API healthy and 277 deployed source files verified. Pro verification also reports 277 source files verified.
- Air's CLI upgrade corrected the previous 0.155.1 catalog, which lacked the requested model despite its configured default.
