# Task-edit chats follow the task model

## User story
Editing an existing task must use its saved agent and model instead of forcing Claude Code.

## User flow
1. Open an existing task and choose Change with chat.
2. Start or reuse a conversation with the task's saved agent and model.
3. If those settings changed, start a matching conversation on the next edit request.

## Success criteria
- [x] New edit chats forward the saved agent and model, ignoring conflicting request fields. Verify API tests for Claude, Codex, explicit models, and defaults.
- [x] Matching live chats are reused. Legacy chats and changed settings start a matching chat. Verify sequence tests across requests and task updates.
- [x] Editing preserves schedules and run history. Failed creation preserves the existing chat reference. Verify real TaskStore integration tests.
- [x] The host runs the updated behavior. Verify a disposable task with the real route and provider launch; independently audit the evidence.

## Scope
The host owns model selection for existing-task edits across desktop and mobile. New-task authoring is unchanged.

## Decisions
Record the requested agent/model with each edit-session pointer. This handles provider default models without comparing runtime model aliases.
Existing chats without that metadata get replaced once; their IDs remain in edit-chat history.
Do not interrupt an old chat when replacing its pointer.

## Verification evidence
Regression logs, provider probes, independent audit, and activation records are in `.codex/evidence/task-edit-model-20261016/`.

## Original investigation
The earlier desktop startup/fork error remains unreproduced. This change addresses the user's explicit model-selection request.

## Results before deployment
- Regression tests first failed: 8 passed, 9 failed against the previous code.
- After the fix, all 41 tests passed across scheduled-task-edit-model, scheduled-task-api, scheduled-a2, and scheduled-tasks.
- Real HTTP routes on isolated port 18767 launched Codex with gpt-6.1-sol and Claude with sonnet. Both replied TASK_EDIT_MODEL_OK.
- Runtime session listings matched each saved agent and model. Both temporary tasks stayed disabled.
- Probe sessions were closed through the API; the isolated server stopped.
- Probe setup needed a canonical temporary directory for Claude folder trust, then polling for its first transcript write. These were harness fixes.
- No client changes are needed: desktop and mobile both call the same host route.

Evidence directory: `.codex/evidence/task-edit-model-20261016/`.

## Activation
Independent audit: PASS. The auditor ran 41 regression tests and 7 additional cases, including a task update during provider startup.
Both production hosts now run the reviewed source. Pro restarted from PID 12716 to 11181; Air from 65931 to 88723.
Both returned their unchanged host identities after restarting. Source hashes match the reviewed files.
No active phone sign-in or starting scheduled task was present at either restart.
The Air dependency check made no changes. No commits or pushes were made.
Activation records: `pro-activation.json` and `air-activation.json` in the evidence directory.

## Concurrent release check
The separate 1.4.0 release restarted both hosts again after our activation. The three changed production files still have matching hashes on both hosts. The release owner confirmed it did not overwrite task-edit source.
