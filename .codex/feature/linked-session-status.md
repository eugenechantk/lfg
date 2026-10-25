# Linked session status

## User story

A completed session must stay idle when a separate session it once launched starts another task.

## Cause

`lfg-4e68ea` completed at 2026-10-20 16:46:31 UTC. Its linked Claude design session received a new prompt at 2026-10-21 01:38:41 UTC and is actively editing the UI map. `withChildSessionActivity` applied the permanent parent link as a busy override. The parent transcript and pane both correctly say idle.

## Decision

Separate sessions own their running state. Keep the linked running-session count as context, without promoting parent busy. Inline subagents retain their existing behavior because they belong to the parent's execution. This avoids guessing whether later child turns are still part of an old request.

## Success criteria

- [x] A busy linked session leaves an idle parent idle and preserves the linked-work count. Verify regression tests.
- [x] Parent turns and inline subagent activity remain running normally. Verify regression tests.
- [x] REST, journal, and push receive consistent snapshots. Verify focused suites and independent audit.
- [x] Both hosts preserve deployed usage endpoints and existing runtime changes. Verify frozen-source hashes, endpoint reads, sessions and schedules after deployment.

## Verification evidence

- Regression reproduced before the fix. `linked-session-status/red.txt`.
- Focused suites: 203 tests and 418 assertions passed. Frozen runtime status/recovery suites: 259 tests and 569 assertions passed on both hosts; TypeScript checks passed.
- Independent audit PASS: six adversarial tests and 60 assertions, plus 120 existing tests and 279 assertions. Actual journal watch creation/refresh and push ticks verified. `linked-session-status/audit/REPORT.md`.
- Both hosts now run `/Users/eugenechan/.lfg/releases/20261021-linked-session-status-1004/source`. Three runtime files and one regression file changed; 266 other source files remain byte-identical to each host's previous runtime, including the usage service and route.
- Live Pro observation: five snapshots over 26.5 seconds kept `lfg-4e68ea` idle and its active linked Claude session running. No parent busy deltas appeared. `linked-session-status/pro-live.json`.
- Usage endpoints responded on both hosts. All 270 manifest files verified. Pro preserved 32 sessions; Air preserved its empty session set. Scheduled task configurations and host identities were preserved on both hosts. `pro-deploy.txt`, `air-deploy.txt`, and live evidence under `linked-session-status/`.
- No agent was interrupted or closed. No client update, commit, or push was needed.
