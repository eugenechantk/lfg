# Verification Audit

Verdict: PASS (server scope; SC5 iOS out of scope for this audit)
Timestamp: 2026-09-07 02:18 HKT
Repository: /Users/eugenechan/dev/personal/lfg
Surface: api + cli (bun test / tsc), read-only live probes on 127.0.0.1:8766

## Change Audited

`src/sessions.ts`: (1) `normalizeCodexLine` emits a codex `event_msg`/`task_complete` carrying `payload.error` as an assistant text message with `apiError: true`, `errorCode = codex_error_info` (default `"other"`), via `codexTurnErrorText` (JSON-unwrap + HTML cut); (2) `computeStatus` gains a codex vocabulary block (`usage_limit_exceeded` -> `blocked`/`out_of_credits`; "model is not supported" / "requires a newer version" -> `model_unavailable`; any other coded error -> `unknown`); (3) the codex branch of `listSessionsUncached` grades `lastAssistantMsg(transcriptPath)` instead of `last` (any role). New tests in `src/sessions-codex-transcript.test.ts` and `src/sessions-status.test.ts`.

Running server: pid 84261 started 02:12:06, `src/sessions.ts` mtime 02:11:21 -> the live probes exercise the new code. I did not restart anything.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
|---|---|---|---|
| SC1 task_complete.error -> assistant apiError msg; no-error task_complete -> nothing | `bun test src/sessions-codex-transcript.test.ts` | PASS (18 pass / 0 fail; 4 new cases) | `08-sc1-codex-transcript-tests.log`; independently `10-adversarial-probe.log` (error null/absent/{}/""/"   "/123/string/[] all -> 0 msgs; real usage-limit -> 1 msg role assistant, apiError true, errorCode usage_limit_exceeded) |
| SC2 computeStatus codex vocabulary | `bun test src/sessions-status.test.ts` | PASS (17 pass / 0 fail; 5 new cases) | `09-sc2-sc3-status-tests.log`; `10-adversarial-probe.log` shows usage-limit -> out_of_credits with the full codex sentence as statusDetail, coded-other -> unknown |
| SC3 codex list grades last ASSISTANT msg | unit test over rollout fixture | PASS | `09-sc2-sc3-status-tests.log` ("selection: a later codex user row does not erase the block"); `10-adversarial-probe.log` `[SC3 fixture]` (error, user_message, thread_settings_applied -> still out_of_credits) and `[SC3 recovery]` (good assistant reply after error -> ok); live: `07-ground-truth-rollouts.log` shows 01a076bc's rollout tail is `thread_settings_applied` AFTER the error, and `04-sc4-codex-statuses.json` still reports it blocked |
| SC4 live GET /api/sessions + messages | curl | PASS | `04-sc4-codex-statuses.json`: exactly 01a076bc and 01a077c7 are `blocked`/`out_of_credits` with statusDetail "You've hit your usage limit ... try again at 9:00 PM."; the other 5 codex sessions are `ok`/null; all 8 claude sessions `ok`. `05-sc4-messages-01a077c7.json` (HTTP 200, `{id,messages}`): last message role assistant, apiError true, errorCode usage_limit_exceeded, text = codex sentence. `06-sc4-messages-01a076bc.json`: same |
| SC5 iOS PausedBannerView | FlowDeck build + screenshot | NOT AUDITED (out of scope per caller) | `01-list-paused-group.jpg`, `02-detail-banner.jpg` exist in this dir from the implementation agent; I did not produce or verify them |
| SC6 existing suites green | `bun test` | PASS | `01-bun-test.log`: `763 pass / 0 fail / 1620 expect() calls, 65 files, 10.91s`, exit 0. `02-tsc.log`: `bunx tsc --noEmit -p .` exit 0, empty output |

## Ground truth cross-check (caller item 4)

`07-ground-truth-rollouts.log`:
- `rollout-2026-09-07T01-32-52-01a077c7...jsonl`: 1 `task_complete`, and it carries `error: {message: "You've hit your usage limit ... 9:00 PM.", codex_error_info: "usage_limit_exceeded"}`; it is the last line of the file.
- `rollout-2026-09-06T20-41-19-01a076bc...jsonl`: 26 task_complete; the last one carries the same usage-limit error; the file's last line is `thread_settings_applied` (the SC3 discriminating case, live).
- All five `ok` codex sessions (01a0763b, 01a07207, 01a07641, 01a0722d, 01a07733): last `task_complete` has `error: null` and a non-null `last_agent_message`, and it is the last line of each rollout. So the live classification matches the rollouts 7/7.

## Regression review (caller item 2) - from `00-sessions-diff.patch` + `computeStatus` read

- Successful task_complete (error null/absent): branch returns `[]` when `err` is falsy, non-object, or an array. Proven at runtime in the adversarial probe (8 no-message shapes -> 0 msgs, none threw).
- Standalone `error` event: the `p.type === "error"` branch is textually unchanged and sits BEFORE the new `task_complete` branch; probe shows it still yields a `system`/`tool_result` with no apiError and classifies `ok`.
- Non-error assistant message: probe `[non-error assistant]` -> `ok`; `computeStatus`'s first gate (`!text || !last?.apiError` -> ok) is unchanged.
- Claude transcript API errors: the new codex block is inserted AFTER the auth (`authentication_failed`/401/403) branch and BEFORE the claude prose labels. It only fires on `errorCode === "usage_limit_exceeded"` or the literal phrases "model is not supported" / "model requires a newer version". None of the pre-existing claude tests changed (git diff of the test file is append-only) and all 12 pre-existing status cases pass.

## Artifacts

All under `/Users/eugenechan/dev/personal/lfg/.claude/feature/evidence/codex-turn-errors-surface/`:
- `00-sessions-diff.patch` - `git diff -- src/sessions.ts`
- `01-bun-test.log` - full `bun test`
- `02-tsc.log` - `bunx tsc --noEmit -p .` (empty = clean)
- `03-api-sessions-raw.json` - raw `GET /api/sessions`
- `04-sc4-codex-statuses.json` - codex rows {sessionId,status,statusReason,statusDetail}
- `05-sc4-messages-01a077c7.json`, `05-sc4-messages-headers.txt`, `06-sc4-messages-01a076bc.json`
- `07-ground-truth-rollouts.log` - last task_complete per live codex rollout
- `08-sc1-codex-transcript-tests.log`, `09-sc2-sc3-status-tests.log`
- `10-adversarial-probe.ts` (copy of the scratchpad script), `10-adversarial-probe.log`

## Commands

```
cd /Users/eugenechan/dev/personal/lfg
bun test                                   # 763 pass, 0 fail
bunx tsc --noEmit -p .                     # exit 0
bun test src/sessions-codex-transcript.test.ts
bun test src/sessions-status.test.ts
ps -eo pid,lstart,command | grep '[c]li.ts serve'; stat -f '%Sm %N' src/sessions.ts
curl -s 127.0.0.1:8766/api/sessions | jq '.sessions[] | select(.agent=="codex") | {sessionId,status,statusReason,statusDetail}'
curl -s "127.0.0.1:8766/api/sessions/01a077c7-b6bf-7431-9bb0-1775dfd7e54b/messages?limit=3" | jq '.messages | last'
grep -c '"task_complete"' ~/.codex/sessions/2026/09/07/rollout-2026-09-07T01-32-52-01a077c7-b6bf-7431-9bb0-1775dfd7e54b.jsonl
bun run /private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/96d9e70f-2d3a-466d-8dd5-0cae1530b05c/scratchpad/adversarial-task-complete.ts
```

## Notes

- Response shape: `/api/sessions` is `{sessions: [...]}` and `/messages` is `{id, messages: [...]}`; the feature doc's `jq '.[]'` recipe is wrong for this shape (cosmetic, doc-only).
- `git diff -- src/sessions.ts` also contains unrelated in-flight work from other sessions on the shared dirty tree (hidden-dirs `exclude` for `listResumable`/`searchResumable`, `codexResponseUserText` for newer codex user-message shapes, `userTurnFromLine` widening). Not part of this feature; not audited beyond the fact that the full suite and tsc are green with them present.
- Observation, not a defect: the codex `model_unavailable` regex in `computeStatus` is not gated on agent, so any `apiError` message whose text literally contains "model is not supported" / "model requires a newer version" would take that branch regardless of source. No existing claude case matches it.
- Observation, not a defect: a `task_complete.error.message` that starts with `{` but is invalid JSON (or valid JSON without a `message`) is surfaced verbatim as the error text (probe cases 9-11). It does not throw and still classifies `unknown`.
- SC5 (iOS banner) was explicitly excluded from this audit; the two .jpg files in this directory are the implementation agent's, not mine.
- No source, test, or config files were modified. No server restart. All live probes were read-only GETs.
