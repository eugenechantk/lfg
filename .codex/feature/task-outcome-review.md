# Reviewed outcomes for finalized scheduled runs

Tier: Product. Platform: TypeScript/Bun host API and MCP tools.

## User story and flow

Eugene needs a reviewed completion decision to agree with the scheduler, even after a run has ended.

1. Finish or revise the session's canonical report and exact-run structured verdict.
2. Request outcome review for that task/run, with a reason.
3. The host reads the session's current final verdict and applies it atomically.
4. The existing task list shows the reviewed result. The run retains its previous assessment in an audit trail.

## Success criteria

- [x] SC1: Reviewing a terminal run applies its latest valid, exact-run verdict to the task list and persists it across reloads. Verify with real API/runtime integration tests.
- [x] SC2: The audit trail retains original status, outcome, summary, error, source session, reason, and review time. Run identity and execution timestamps stay unchanged. Verify with store and route tests.
- [x] SC3: Active/busy/waiting runs, missing or invalid verdicts, wrong-run verdicts, stale concurrent reviews, and task/run mismatches cannot change the stored outcome. Repeated identical review is idempotent. Verify with negative and concurrency tests.
- [x] SC4: Reviews do not launch sessions or change schedules, retry reservations, enabled flags, occurrence counters, or unrelated runs. Verify with whole-state comparisons and MCP integration.
- [x] SC5: The live host applies Jess PM's completed verdict and exposes its original incomplete assessment, with all saved tasks and other runs unchanged. Verify via live API snapshots before/after and independent audit.

## Implementation phases

1. Regression tests, durable review transaction, API route, and agent tool.
2. Focused scheduler regressions and independent verification.
3. Isolated host release based on the currently running release; apply only Jess's reviewed result through the API.

## Decision log

- Use an explicit review operation. Do not silently regrade arbitrary closed sessions or infer completion from report prose.
- The host validates the existing structured final-message contract. The caller supplies a review reason, not an unchecked success override.
- Update current outcome fields for existing clients. Preserve every prior assessment in an append-only review array.
- Review has no scheduling side effects and does not execute phone work.
- Keep current completion criteria. This fixes delivery of a reviewed judgment, not its strictness.
- Preserve unrelated dirty checkout changes; deploy from the clean current host release plus only these files.

## Verification evidence

- SC1–SC4: `bun test src/scheduled-task-review.test.ts src/scheduled-task-runtime-outcome.test.ts src/scheduled-task-outcome.test.ts src/scheduled-task-outcome-examples.test.ts src/scheduled-task-api.test.ts src/scheduled-tasks.test.ts src/scheduled-repeat.test.ts src/scheduled-auto-retry.test.ts src/scheduled-retry.test.ts src/scheduled-task-edit-model.test.ts` — 96 passed, 533 assertions. Output: task-outcome-review/tests-regression.txt.
- Seven new integration tests cover late completion, audit persistence, idempotence, active sessions, malformed outcomes, wrong identities, MCP routing, concurrent requests, stale correction rejection, and unchanged pending schedules/unrelated runs.
- `git diff --check` passed for all modified production files.
- All four production files matched the current live host release before changes, so an isolated release can copy only this implementation.

## Bugs and blockers

None open.

## Live verification

- Activated isolated release `/Users/eugenechan/.lfg/releases/20261022-outcome-review-221510/source`. Only the four scheduler files, CLI helper, and review test differ from the previous live source.
- No scheduled run was active. The restart preserved the entire task store before the review. Terminal agents stayed alive.
- Applied Jess PM review through `bun scripts/lfg-task-tool.ts review <task-id> <run-id>` with the recorded reason. Response: changed=true, status=succeeded, outcome=completed.
- Live list now reports Jess completed. The first audit entry retains incomplete, its original summary/error/outcome, source session, reason, and review time.
- Compared all stored tasks, unrelated runs, run counts, and execution identity/timestamps: unchanged. Canonical report/result already said completed and required no rewrite.
- Repeated the exact live request: changed=false, one audit entry, and the entire store stayed unchanged.
- Evidence: deployment.json, state-before-deployment.json, state-after.json, jess-review-response.json, jess-repeat-response.json, tasks-api-after.json, live-verification.json.

Independent final verification: PASS for SC1–SC5. The auditor confirmed the live API/store/canonical result agree, the original assessment is exact, all 30 task objects and other runs are unchanged, and the running release differs in exactly the six declared files. Evidence: task-outcome-review/independent-audit.md and independent-live-verification.json.
