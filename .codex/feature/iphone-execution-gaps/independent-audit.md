# Independent audit: iPhone execution gaps

Verdict: **PARTIAL**. The launch policy and recovery instructions pass review. The original production defect remains unresolved.

## Scope

Reviewed only the new provider-routing additions in `src/tmux.ts`, the policy module and tests, the shared iPhone Control skill, its timing reference, the Warm Up Tips reference, and the machine-local policy/provider. Other dirty files belong to other sessions. No phone operations, database queries, service restarts, schedule changes, or commits occurred in this audit.

## Implementation: PASS

- Exact workspace matching selects `openai-phone` through one escaped CLI config argument. Other workspaces receive no override. Selection appears before the positional prompt.
- Fresh launches preserve the configured model when no model is requested. Explicit models remain intact. Resumes and forks receive no new provider override.
- Missing policy files retain previous behavior. Malformed policy data and read failures propagate; the public spawn function returns an explicit launch error instead of silently starting with the wrong policy.
- The user-level provider disables WebSockets and configures a 60-second idle timeout with one stream retry and one request retry. The default remains `openai-long-timeout`; model, effort, and service tier retain their previous values. The before/after change artifact reports only an additive provider table.
- The updated reference now correctly limits automatic selection to fresh LFG launches. Direct CLI sessions require explicit selection. A host build containing the routing code is required; policy-file presence alone proves no activation.
- Recovery instructions distinguish driver execution, delayed result delivery, and agent continuation gaps. They require current ownership, booking, local receipts, and a fresh screen before further input. They forbid uncertain input replay and claiming gaps as playback.

## Independent verification: PASS

- `bun test src/codex-launch-policy.test.ts src/tmux-argv.test.ts src/codex-bind.test.ts`: 50 tests passed.
- Driver regression suite, using `uv run --with requests python -m unittest discover -s /Users/eugenechan/.claude/skills/iphone-control/tests -q`: 54 tests passed.
- Warm-up helper suite: 27 tests passed.
- iPhone Control skill validation, using the validator with PyYAML: passed.
- Generated argv from the real launcher and real policy without launching anything: both configured workspaces select the provider; an unrelated workspace does not; model defaults remain unpinned; resumed and forked sessions receive no override.

Initial test attempts used nonexistent `scripts/tests` paths and lacked Python dependencies. Corrected commands above passed; initial setup errors are not product failures.

## Production proof: PARTIAL

- The original event timelines show seconds of local execution followed by minutes before enclosing result delivery. They isolate the delay outside ordinary phone execution. They do not identify the exact transport component.
- Local fault injection verifies idle-SSE timeout behavior. `workspace-config-recovery.json` shows a real CLI launch using the policy reconnecting once after about 60.225 seconds and completing. This reproduces an injected silent stream, not the original defect.
- In `workspace-1-events.json`, a live image-and-command probe hit an idle timeout at 81.881 seconds, resumed its next command at 86.753 seconds, and completed five commands. This demonstrates useful live recovery.
- `workspace-2-result.json` is **not accepted**: the harness stopped at 150.023 seconds after one successful read-only phone-status command. That command finished at 10.953 seconds; a transport decode error appeared at 145.237 seconds. A substantial continuation gap persists under the candidate settings. Exit code 0 after harness termination does not establish completion.
- Earlier ignored-project-config runs are failed activation attempts. Neither their successful tool calls nor their recovery text verifies the intended provider. Both project-local provider definitions and selection were ineffective.
- The 117.685-second baseline and 45.646-second candidate comparison are single small runs. They do not establish causation or prove the production defect is fixed.

## Success criteria

- SC1: PARTIAL. Production timing isolated; exact defect not deterministically reproduced.
- SC2: NOT MET. The responsible component is unconfirmed, and the real warm-up workspace probe still lost substantial time.
- SC3: PASS. Skill guidance and validation meet the stated safety and recovery requirements.
- SC4: PARTIAL. Existing regression suites pass and global defaults remain intact. The fresh phone workspace runtime probe did not finish. Host deployment/activation is separate and unverified here.

Do not label the original execution-gap issue resolved. Describe this as a tested transport mitigation and safer recovery guidance pending successful runtime verification and production evidence.

## Follow-up: raw traces and disabled-host experiment

Raw records confirm the same completed-local/late-outer shape in the candidate profile's first workspace:

- Custom call `call_bdae7c42f1db4cc88d591521f5affd73` starts at 10:00:02.513 UTC.
- ImageView completes at 10:00:02.761; CommandExecution completes at 10:00:03.035.
- Its enclosing output appears at 10:01:03.579: 61.066 seconds after dispatch and 60.544 seconds after the last nested completion.
- Later enclosing calls take 0.190–0.206 seconds. This supports the timeout mitigation's effect on one delayed return, while leaving the underlying defect unconfirmed.

The second workspace's enclosing call completes in 1.305 seconds at 09:59:52.686 UTC. Its later long gap has no outstanding tool in the raw records. This is an agent continuation or response gap, distinct from a running phone command.

Both `native-results.json` runs are rejected: zero successful commands, despite exit code 0. Disabling `code_mode_host` did not expose an alternate functioning tool path. Raw records still show custom `exec` calls, returning the literal error `code-mode host is disabled`. These attempts provide no image-return or phone-status verification.

Only timestamps, tool types, tool status, and explicit tool errors were inspected for this follow-up. Private reasoning text was excluded.

## Final-state cleanup review

The failed transport candidate was withdrawn. The implementation PASS above records the reviewed experiment, not the final deployed state.

Independently confirmed:

- `/Users/eugenechan/.codex/config.toml` SHA-256 is `c172e55e02a9da90b7475b280d57452791635959b3e14fddc7928a2200f92cbe`, exactly matching the recorded original hash. The candidate provider is absent. Existing model, provider, effort, and service tier remain unchanged.
- The machine-local launch policy and both candidate modules are absent from their live paths. `src/tmux.ts` contains no candidate policy import, routing call, option, or launch-error wrapper. Unrelated pre-existing edits remain.
- Both ineffective project configuration files are absent. The experimental policy module and tests remain only under `launcher-candidate` for review.
- `withdrawal.json` records no host restart, schedule edit, or phone input. This audit did not execute any such operation.
- The shared skill still passes validation. Safe recovery guidance remains useful independently of transport settings.

Overall verdict remains **PARTIAL**. The original production issue is blocked by an unconfirmed transport defect. No active transport mitigation should be claimed from these experiments. SC2 remains unmet.

### Documentation correction cleared

Re-read the final Warm Up Tips pacing section. It now explicitly states that no transport change remains active and forbids restarting an active run to test a candidate. The stale activation claim is cleared. The final feature document keeps SC2 open and distinguishes unchanged driver behavior from failed candidate runtime proof. `final-verification.json` agrees with the independently observed cleanup state and records no database query. No further tests or phone operations were needed for this narrow correction.

Final verdict: **PARTIAL overall; PASS for retained skill guidance and cleanup. Original execution-gap fix unresolved.**
