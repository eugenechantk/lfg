# Scheduled task outcomes

## User story

Scheduled runs must report whether they achieved their saved instructions. An agent ending its turn does not prove success.

## User flow

1. The host starts one execution with the task description and a separate execution policy.
2. The agent performs the work, checks its result, and reports a structured verdict.
3. The host records completed, incomplete, or failed and shows the reason in Tasks.

## Success criteria

- [x] SC1: Claude and Codex receive a separate execution policy with the run ID and completion rules. Verify with launch argument and runtime tests.
- [x] SC2: Only a valid final verdict for this run can produce success. Verify with parser and scheduler tests.
- [x] SC3: Partial work, blockers, and missing or invalid verdicts become incomplete; agent and infrastructure errors become failed. Verify with scheduler and API tests.
- [x] SC4: Busy sessions and live questions stay active; closed sessions can still supply their final verdict. Verify with runtime tests.
- [x] SC5: Incomplete runs appear in Needs input with their reason and retry actions on mobile and desktop. Verify with Swift presentation tests and independent simulator evidence.
- [x] SC6: Run outcomes survive reloads and do not change recurrence or earlier history. Verify with API integration and existing schedule tests.
- [x] SC7: Claude model and effort changes preserve the scheduled run's policy and run ID. Verify with durable policy tests, launch arguments, and an isolated real HTTP control probe.

## Platform

Bun and TypeScript host; shared Swift presentation models and SwiftUI clients.

## Decision log

- Use the execution agent's judgment. No second model call or extra inference cost.
- Require a run-scoped JSON result at the end of the final response. Do not guess success from prose.
- Keep succeeded and failed API states. Add incomplete as a terminal state that requires attention.
- Preserve existing history. Runs started before this change without a verdict cannot earn a new success from session idleness.
- Keep infrastructure errors separate from the agent's assessment. A transport error cannot become success.
- Scope excludes deploying the host or shipping a new client build.
- Preserve the policy across same-conversation Claude model and effort respawns. Reconstruct it from durable run history before replacing the process.

## Implementation

Each execution receives a separate policy. Claude uses its appended system prompt; Codex receives developer instructions for that session.

The agent must assess the requested result, duration, deliverables, and verification. Its final response ends with a run-specific JSON verdict and reason.

The host checks only the latest assistant response. It requires one valid terminal verdict for the exact run. Tool text, ordinary prose, malformed blocks, and other run IDs cannot earn success.

An idle response must stay stable for at least five seconds. Empty startup transcripts have a sixty-second grace period. Busy activity, live questions, or failed inspections reset the settling period.

Completed maps to succeeded. Incomplete maps to incomplete. Error maps to failed. Infrastructure failures remain failed or interrupted. Missing verdicts become incomplete with an explanation.

Incomplete runs use the existing attention group and retry controls. The task card, history, run details, and completion counts reflect the outcome.

The shared native presentation logic serves mobile and desktop. Existing history and recurrence rules remain unchanged.

Claude model and effort routes recover the run's reporting policy from its session ID and pass it to the replacement process. Ordinary sessions receive no scheduled-task policy. Editing the saved task does not change the run ID in that policy.

## Verification evidence

- SC1–SC4, SC6: `bun test src/scheduled*.test.ts src/tmux-argv.test.ts src/tmux-launch.test.ts` passed 102 tests. Log: `scheduled-task-outcomes-host-tests.txt`.
- SC1–SC4, SC6: independent host audit passed 94 regression tests and seven additional probes with 41 assertions. A follow-up verified the current parser and runtime with 15 tests and 112 assertions. Report: `.codex/evidence/scheduled-task-outcomes/host-audit/REPORT.md`.
- SC1–SC3: real isolated provider runs passed. Codex returned completed and the scheduler recorded succeeded. Claude could not access a required private file, returned incomplete, and retained the reason. Both disposable sessions closed successfully. Evidence: `.codex/evidence/scheduled-task-outcomes/live/result.json`, plus raw provider transcripts.
- SC5 model coverage: all 470 Swift tests in 71 suites passed. New regression verifies the attention group, incomplete label, reason, card, and retry controls. Log: `scheduled-task-outcomes-full-swift.txt`.
- TypeScript typecheck passed with no diagnostics. Log: `scheduled-task-outcomes-types.txt`.
- `git diff --check` passed.
- Additional parser review passed 70 independent probes, 106 scheduled-task and tmux regression tests, and eight HTTP checks using raw Claude/Codex transcripts. It covers unfinished fences, comments, line endings, and literal inline code. Evidence: `.codex/evidence/scheduled-outcome-host-review-20261019/review.md` and `auditor/REPORT-final.md` in that directory.
- SC5: independent native audit passed on an isolated iPhone 17 Pro. Incomplete appeared in Needs input with the reason, Retry now, Retry later, run-row Retry, and zero completed. Completed remained Done under Closed. Error remained Failed under Needs input. Evidence: `.codex/evidence/scheduled-task-outcomes/ui-audit/20261019-000500-ios-visual-audit/evidence.md` and screenshots `03-incomplete-detail.jpg`, `04-all-outcomes-list.jpg`.
- SC7: 120 targeted host tests passed, including policy recovery after reload, task edits, normal sessions, and both respawn argument paths. Typechecking and `git diff --check` passed. Logs: `scheduled-task-outcomes-respawn-tests.txt`, `scheduled-task-outcomes-respawn-types.txt`.
- SC7: both actual HTTP controls succeeded on a disposable Claude run. Each replacement used a new process ID, the same session ID, and the full run policy. The independent auditor decoded the actual process arguments and confirmed exact policy equality. Evidence: `.codex/evidence/scheduled-task-outcomes/respawn-live/result.json` and `host-audit/respawn-provider-proof.json`. Cleanup succeeded. The first probe failed only because its argument logger was bypassed; that result is retained as `respawn-live/first-probe-result.json`.
- SC7: independent host audit passed eight probes with 52 assertions, plus the real respawn evidence review. The earlier iPhone audit remains valid; this follow-up changes host behavior only.

## Limits

The execution agent owns the judgment. Structured output does not prove that every complex task will be assessed correctly.

Codex receives the policy through its documented [developer instructions setting](https://learn.chatgpt.com/docs/config-file/config-reference). Real-provider verification confirms delivery on this host.

This change is verified locally. It does not restart the production host or release a native client.

Desktop uses the tested shared presentation models. A separate desktop GUI audit was not run.

Closed-session resume and cross-provider handoff are outside the policy-preservation guarantee. They may start a process without the policy or change the session ID that the run follows. Such a session cannot earn success without a valid verdict for the original run. Use the task's Retry action to start a fresh assessed execution. This is distinct from same-conversation model and effort changes, which preserve the policy.

The broader host suite finished with 1,314 passes, eight failures, and one error. Two iOS toolbar source tests reproduce from exact HEAD files. Session search and history tests reported timeouts and pagination failures. Those paths are outside this change. The independent audit records the deterministic baseline evidence. Full log: `scheduled-task-outcomes-full-host.txt`.

## Bugs

No open feature bugs. Broader-suite baseline failures are listed above.
