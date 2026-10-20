# Automatic retry for incomplete scheduled runs

Product tier. TypeScript host and shared native clients.

## User story and flow

An incomplete run must keep its scheduled occurrence. Assign its retry to the next interval and move later occurrences back one interval.
Retry now starts that same occurrence immediately. Change retry time opens with the assigned date and allows an earlier or later time.
A late retry holds later occurrences until it finishes. Those occurrences keep their interval cadence.

## Success criteria

- [x] SC1: Incomplete interval and finite-repeat runs receive one durable retry at the next interval. Later runs move back. Verify with real-store tests.
- [x] SC2: A three-run repeat can complete three occurrences despite repeated incomplete attempts, including its last occurrence. Verify with scheduler sequence tests.
- [x] SC3: Retry now replaces the pending retry. Earlier and later edits persist without overlapping later occurrences. Verify with store and HTTP tests.
- [x] SC4: Restart and duplicate completion reports cannot duplicate a retry or shift the schedule twice. Cancellation, pause and explicit schedule edits retain user control. Verify with mutation sequence tests.
- [x] SC5: Native clients explain the saved occurrence, show the deferred next run, and seed the picker from the assigned retry. Verify with Swift tests and an independent simulator audit.
- [x] SC6: Retry now clears the pending retry while active. An unsuccessful attempt restores that time if it is still future. Verify with the Retry now failure, restart and chosen-time regression tests.

## Design decisions

- Keep scheduledRunCount as the number of logical occurrences claimed. Retry attempts belong to their original occurrence and do not increment it.
- Persist the original run ID on a pending retry and on its attempts. Persist an occurrence number for finite repeats.
- Persist a delay separately from the saved schedule. Shift the effective repeat anchor to preserve its remaining count and cadence.
- Only interval and finite-repeat schedules have an automatic interval retry. One-time and cron behavior stays as it is.
- Respect an explicit interval end date. A task paused by the user does not start an automatic retry. An explicitly scheduled retry can still run while paused.
- Incomplete retries retain the same occurrence. Failed or interrupted recovery attempts also retain it. Initial infrastructure failures keep their current behavior.
- Retry now stores the consumed retry time on its attempt. Failure restores that time if it remains future, without moving later runs again. A passed time uses the next future interval.
- Restoration also keeps the original pause behavior. A user-chosen retry stays authorized while paused. An automatic retry still waits for resume.
- Cancelling a retry explicitly skips recovery of that occurrence. Stopping the task clears all pending execution.
- A schedule edit starts a new schedule revision. An old run cannot defer the new schedule.
- Do not rewrite historical runs or mutate production tasks during verification.

## Verification evidence

- SC1–SC4: `bun test src/scheduled*.test.ts` passed 93 tests and 532 assertions. Evidence: `.codex/evidence/automatic-task-retry/host-tests.txt`.
- SC1–SC4: Independent host audit passed 11 real-store, scheduler and HTTP scenarios. It completed three occurrences across 15 recovery attempts. Report: `.codex/evidence/automatic-task-retry/host-audit/REPORT.md`.
- The audit found two edges, now fixed: pausing an already-disabled final recovery and retaining an older run's occurrence number. Both have permanent regression tests.
- SC5 model coverage: `swift test --package-path ios/LFGCore` passed 486 tests in 74 suites. Evidence: `.codex/evidence/automatic-task-retry/swift-final.txt`.
- TypeScript: `bunx tsc --noEmit` passed without diagnostics. Evidence: `.codex/evidence/automatic-task-retry/types-final.txt`.
- iOS: `flowdeck build --json --xcodebuild-options='CODE_SIGNING_ALLOWED=NO'` passed. Evidence: `.codex/evidence/automatic-task-retry/ios-build.jsonl`.
- Mac: `LFG_DESKTOP_OPTIMIZATION=-Onone bash desktop/build.sh` passed. This app uses its existing standalone Swift build script. Evidence: `.codex/evidence/automatic-task-retry/desktop-build.txt`.
- SC5: Independent iPhone 17 Pro audit passed. It recorded the assigned retry, seeded picker, earlier and later edits, Retry now, final occurrence and paused state.
- Native evidence: `.codex/evidence/20261020-120145-ios-visual-audit/evidence.md`. The report includes a 240-second recording, screenshots and saved API states.
- Native compact date controls ignored synthetic taps. The audit verified their assigned values and used relative-time controls for earlier and later edits. Swift tests cover absolute dates.
- Parent review also checked screenshots and asserted the saved UI states: earlier/later edits, shifted next run and Retry now retained occurrence 1.
- Verification used isolated fixture ports 18957/18958. The fixture app, capture session and server were stopped afterward. No production tasks, host processes, commits or releases changed.

### Retry now fallback correction

- The user asked whether a failed immediate retry restores its original scheduled time. Review found that the first implementation skipped it and used the following regular slot.
- Persist the consumed time and whether it was automatic on the immediate attempt. Restore both if that time remains future.
- `bun test src/scheduled*.test.ts` passed 101 tests and 553 assertions. Evidence: `.codex/evidence/automatic-task-retry/retry-now-fallback-tests.txt`.
- Coverage includes failed, incomplete and interrupted results, repeated immediate attempts, host restart, chosen times, final occurrence and paused schedules.
- The independent audit caught a restored user-chosen time incorrectly inheriting automatic pause behavior. The fix preserves its original authorization; permanent regression tests cover both modes.
- SC6 independent audit passed eight scenarios. The previous host audit passed all 11 scenarios again. TypeScript and `git diff --check` also passed.
- Report: `.codex/evidence/automatic-task-retry/retry-now-fallback-audit/REPORT.md`. No production effects occurred. Native UI code did not change in this correction.

## Scope and limits

This is a local implementation. It applies when a future run becomes incomplete after deployment; historical runs were not rewritten.
The Mac build passed and shares the verified presentation models. A separate Mac GUI audit was not run.

## Bugs

None yet.
