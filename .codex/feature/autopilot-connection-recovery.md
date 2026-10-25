# Autopilot connection recovery

## User story and flow

Long Claude tasks should resume after a connection error without manual intervention. Each existing Autopilot tick checks live local Claude sessions. It continues only an explicit connection error after the turn stops. It never revives archived sessions or errors predating activation.

## Success criteria

- [x] SC1: Register recovery on the existing interval — verify CLI list and registry test.
- [x] SC2: Recover genuine connection errors only; skip busy, external, newer activity, prompts, drafts, foreign leases, and cancellations — verify policy and integration tests.
- [x] SC3: Persist one claim per error before enqueue; survive restarts and concurrent runs without duplicate sends — verify filesystem integration tests.
- [x] SC4: Stop after three recoveries for one user task; delay successive recoveries; skip historical errors — verify clock-controlled tests.
- [x] SC5: Support dry runs without mutations or sends — verify integration test and live CLI dry run.

## Platform

Bun and TypeScript host service. No Apple app changes.

## Decisions

- Recovery is the first Autopilot step, before model-backed renaming can delay it.
- Only currently live, directly controlled Claude sessions qualify. Process-crash relaunch is outside this change.
- Fresh local leases and an empty idle composer are required. Never dismiss a prompt or clear a user draft.
- Persistent error claims fail closed after uncertain delivery. Never automatically replay an uncertain send.
- Three attempts apply to consecutive recovery errors; a genuine user instruction starts a new task budget.
- First activation establishes a timestamp cutoff. Old unfinished conversations stay untouched.

## Verification evidence

- SC1: `bun run src/cli.ts autopilot list` lists recover-connections first and retitle-sessions second on the same ten-minute interval. Registry test passes. Evidence: autopilot-recovery-cli.txt.
- SC2: Live-session inspection tests reject busy/external sessions, foreign/stale/wrong-PID leases, child agents/sessions/background processes, unreadable panes, user drafts, pending input, Stop, newer transcript activity and inherited fork errors. Tests also validate the exact own draft before Enter. Native queue changes veto recovery.
- SC3: Immutable claims use a fully written, fsynced temporary file and an atomic hardlink that cannot replace another claim. Twenty concurrent ticks enqueue once. An uncertain recovery is never re-armed by queue reconciliation or restart. The ordinary user queue retains its existing behavior.
- SC4: Clock-controlled tests confirm activation cutoff, one-minute settling, three recoveries per genuine user task and ten/thirty-minute retry delays. A new genuine user task resets the budget. Full backward transcript scanning finds task boundaries beyond large tool results.
- SC5: Live dry run examined 34 sessions and found zero eligible. Recovery-state dry-run tests confirm no activation or claims are written. The existing Autopilot audit log still records dry runs, as before.
- Focused regression run: `bun test src/autopilot src/sendq-delivery-policy.test.ts src/sendq-retraction.test.ts src/sendq-store.test.ts src/interrupt-marks.test.ts` passed 155 tests and 322 assertions. Evidence: autopilot-recovery-tests.txt.
- `bunx tsc --noEmit` passed. `git diff --check` passed. Evidence: autopilot-recovery-types.txt.
- Independent re-audit: PASS for isolated verification, eight independent tests and 20 assertions. Evidence: autopilot-recovery-audit/REPORT.md and results-recheck.txt. The prescribed auditor model could not start on this account; a default agent performed the independent audit instead.

## Runtime status and limits

Deployed and activated on both configured hosts (Pro and Air) on 20 October 2026. Both servers restarted and completed a natural recovery tick. Both APIs are healthy; existing sessions and scheduled-task settings were preserved. Each host passed 155 tests and TypeScript validation; all 277 staged files matched the manifest. The first recovery checks queued zero continuations. No real connection failure was deliberately induced. No commit, push or Apple-client release occurred. Deployment evidence: .codex/evidence/autopilot-recovery-deploy-20261020/REPORT.md.

Recovery covers live directly controlled Claude sessions only. It does not relaunch crashed processes, bypass usage limits, or recover archived sessions. Exhaustion and uncertain sends appear in Autopilot/send-queue logs; this change adds no new push notification type.

## Audit fixes

The first independent audit caught generic send-queue redelivery after uncertainty and a second feedback-prompt dismissal before Enter. Both are fixed. Recovery gets one Enter, preserves uncertain sends for reconciliation, and checks exact draft/ownership/Stop again before submission. Concurrent claims now publish complete JSON atomically. All criteria were rerun after fixes.
