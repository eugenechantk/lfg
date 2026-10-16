# Feature: Finite repeat schedules

## User story

Eugene wants one task to run three occurrences, one day apart, without agent-written rescheduling instructions.

## User flow

1. Open task setup or edit an existing task.
2. Choose Repeat a set number of times.
3. Set the first start, repeat interval, interval unit, and occurrence count.
4. Save and see the finite schedule in the task list and detail.
5. LFG advances the schedule and stops after its final occurrence.

Conversational setup accepts the same fields through the host API and MCP tools.

## Success criteria

- [x] SC1: A repeat schedule stores first start, interval, and total occurrences, including the first. Invalid inputs fail clearly. Verify: Bun validation and API tests.
- [x] SC2: Three daily slots advance independently of agent success and survive reload, with no fourth automatic run. Verify: Bun lifecycle, launch-failure, restart, manual-run, pause/resume, edit, and missed-slot tests.
- [x] SC3: Existing once, interval, and cron behavior stays compatible. Verify: scheduler and API regression suites.
- [ ] SC4: Native editor can save and reload 3 occurrences every 1 day. Invalid counts and intervals disable Save. Verify: Swift Testing and recorded iPhone editor flow.
- [ ] SC5: List/detail describe the repeat count and interval; finished repeats group as completed. Verify: Swift model tests and iPhone/Mac UI evidence.
- [x] SC6: Chat setup and MCP expose finite repeats and tell agents not to reschedule execution. Verify: API prompt/schema tests.
- [ ] SC7: Independent auditor verifies the public behavior. Verify: auditor report with evidence.

## Decisions

- Product tier. Preserve existing dirty changes in the shared checkout.
- Add schedule kind `repeat`: `at`, `everyMinutes`, `occurrences`, and `timezone`.
- Occurrences count planned slots, including the first. A day means 24 elapsed hours; cron remains the wall-clock option across DST.
- Valid ranges: 1–1000 occurrences and 1–525600 interval minutes.
- Slots stay anchored to the first start. Missed slots coalesce without extending the series or replaying a burst.
- Failed launches consume their planned slot. Manual runs do not consume or move the schedule.
- Pause/resume skips past slots and preserves the original end. A finished repeat needs a new future start to run a new series.
- No commit, push, TestFlight release, or production host restart is implied by source verification.
- Existing phone schedules stay intact during implementation. Assess a safe host cutover only after verification.

## Tests and implementation

Backend: scheduled-tasks.ts, scheduled-task-api.ts, scheduled-task-tools.ts and focused test files.
Native: LFGCore ScheduledTasks.swift and shared ScheduledTasksView.swift, with package tests.
Use a disposable API fixture for UI verification. Never run live phone jobs as tests.

## Verification evidence

- SC1–SC3: `bun test src/scheduled-repeat.test.ts src/scheduled-tasks.test.ts src/scheduled-task-api.test.ts`: 27 passed, 0 failed. Evidence: `.codex/evidence/finite-repeat-schedules/backend-tests.log`.
- SC3: MCP and task-notification regressions: 41 passed, 0 failed. Evidence: `backend-regression.log` in the same directory.
- SC4 model: `swift test` in `ios/LFGCore`: 276 tests passed. Repeat editor coverage includes serialization, unit conversion, validation, labels, and completion grouping. Evidence: `swift-all.log`.
- SC6: API/MCP tests verify the repeat schema, example, first-occurrence semantics, and host-owned execution instructions. Included in the 27-test backend result.
- Real HTTP lifecycle: the production route and scheduler launched exactly three local stub sessions, persisted the finished state, rejected an unchanged resume, and launched no fourth session. Evidence: `http-lifecycle.json`. No external agent or phone ran.
- Native build: `flowdeck build --json` from `ios`: succeeded. Evidence: `ios-build.log`.
- Mac UI: current-source isolated build passed save/reopen, readable labels, invalid-count and interval validation, completed grouping, and three-run history checks. Evidence: `mac-verification.md` and its referenced screenshots and accessibility trees. The audit app and port 8909 fixture were stopped after verification.
- Independent iPhone audit: PARTIAL. Current sources built and launched, but FlowDeck could not capture the editor. Report: `.codex/evidence/20261015-000100-ios-visual-audit/evidence.md`.

## Current production boundary

On 15 October, Eugene requested both TikTok sequences using native repeats. The local host restarted through its existing supervisor to activate the tested backend.
The live API accepted and enabled two new repeat tasks, each with three occurrences and a 1440-minute interval. Their next starts match the approved account times.
All 20 existing agent processes survived the restart, and all 18 known session IDs were rediscovered. No waiting phone sign-in or scheduled run was active.
The two old FiftyStrong jobs stay cancelled. The new task receipts are in `/Users/eugenechan/inbox/fiftystrong-tiktok-warmup/verification.json`.
Installed native clients remain unchanged. The iPhone visual audit blocker below still applies to the new editor UI.

## Blocker report

SC4, the iPhone part of SC5, and SC7 remain open. Implementation and Mac verification are complete; the iPhone visual gate is not complete.

The independent auditor exhausted five capture recovery approaches:

1. Restart the original capture session. It stopped updating after fixture setup.
2. Use the documented one-off screen fallback. It stalled without an image.
3. Reboot the original simulator and relaunch the app. Capture still stalled.
4. Create a fresh isolated iPhone 17 Pro. Initial capture worked, then failed during host setup.
5. Erase the replacement and configure the fixture through launch arguments. Capture reported success but produced no image or tree for over 90 seconds. Restarting it also stalled.

The auditor consulted the local FlowDeck UI guide before using its fallback. Exact commands and artifacts are in `.codex/evidence/20261015-000100-ios-visual-audit/evidence.md` under Recovery Attempt Ledger.

Best hypothesis: FlowDeck or its simulator capture service is failing independently of the repeat editor. The failure occurs before reaching that editor. The evidence does not establish an app defect.

Resume by restoring reliable simulator capture, restarting the disposable fixture, and repeating the independent iPhone save/reload, validation, list/detail, and Completed checks. Do not weaken those criteria or treat Mac proof as iPhone proof.

Audit cleanup is complete. Both fixtures, the isolated Mac app, and all audit UI sessions stopped. The audit simulators and the parent simulator created by the isolation hook shut down. The later backend activation is recorded above.

## Bugs

The lifecycle check found that clock rollback could allow an unchanged completed schedule to resume. The host now rejects that request independently of wall time. A regression test and real HTTP check pass.
