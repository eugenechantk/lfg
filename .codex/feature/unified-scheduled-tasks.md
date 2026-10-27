# Unified scheduled tasks

Product tier. High-risk storage and execution refactor with existing store/API tests as characterization coverage.

## User story and flow

One scheduled-task primitive supports starting a coding session, resuming a durable chat, or sending a fixed reminder. A task may belong to a chat. Tasks and chat settings show the same records and controls. Existing terminal tasks retain their behavior.

## Success criteria

- [x] SC1: One TaskStore, task/run model, scheduler loop and canonical scheduled-task API support all three actions. Verify mixed-action store/runtime/API integration tests and serve wiring inspection.
- [x] SC2: Legacy task files remain readable. Import old chat jobs, run receipts and notification intents atomically and once, preserving IDs, revisions, history and no-replay behavior. Leave source files intact. Verify temporary-store migration/restart/collision tests.
- [x] SC3: Existing session tasks retain retries, finite schedules, editing, manual execution, outcomes and task-edit session behavior. Verify existing scheduler/API/outcome regressions, with date-sensitive baseline fixtures isolated.
- [x] SC4: Chat actions keep busy deferral, pause/cancel races, current instructions/memory, conditional notify/stop, atomic outbox and per-device delivery recovery. Verify existing chat tests and new independent probes.
- [x] SC5: Native clients use canonical task records/API. Chat settings filters tasks by chat; the main Tasks tab includes them and routes to suitable controls without directory or desktop requirements. Verify Swift contracts and fresh phone/iPad native audit with recordings.
- [x] SC6: Built-in scoped tools create and manage the same scheduled tasks. Compatibility chat-job routes only translate requests to the shared store. Verify scoped MCP and canonical/compatibility cross-API tests.

## Decisions

- Extend the existing scheduler and TaskStore. Add execution actions `session`, `chat` and `notify`; absent action means an existing session task.
- Keep chat-job endpoints temporarily as compatibility adapters. They will own no persistence or scheduling loop.
- Persist notification intents alongside canonical runs. Keep executor-specific reporting contracts behind the common scheduler.
- Upgrade the store format so older hosts fail closed rather than launching new action types incorrectly. Read existing version-one task files and write the new format atomically.
- Automatic import code runs only when a new host starts. This task tests migrations in temporary directories and does not mutate production state.
- No commit, push, production restart or release without a separate explicit request.

## Verification evidence

- Review gallery: https://share.eugenechantk.me/unified-tasks-2783ad/ . Live HTTP 200, 17 screenshots and two H.264 recordings. Browser verification confirms both videos load without errors, including landscape iPad dimensions. The page links the updated architecture.

- Backend independent audit: `unified-scheduled-tasks/backend-audit/final-recheck-report.md`; 233 product tests / 1001 assertions and 34 independent probes / 115 assertions pass.
- TypeScript check passes. Final backend source manifest verified by the auditor.
- Swift contracts: 91 tests / 14 suites pass (`unified-scheduled-tasks/swift-tests.txt`).
- Native iOS and Mac builds pass (`ios-build-routing.jsonl`, `mac-build-routing.txt` in the evidence directory).
- Real Claude acceptance: `unified-scheduled-tasks/live-report.json` PASS. Shared MCP creates reminder/chat actions, canonical IDs match compatibility projection, the same provider session reads edited memory, and both expected notification payloads are accepted by fake transport.
- Independent native audit PASS: `unified-scheduled-tasks/native-audit/evidence.md`. Fresh iPhone and landscape iPad checks cover shared identities, lifecycle controls, correct durable-chat routing, coding-task editor, quiet/match/stop, reminder delivery receipts and duplicate prevention. Screenshots and recordings are in the audit directory.

## Bugs and residual risks

- The initial video files lacked final metadata while recording. The auditor finalized both through FlowDeck and verified playable streams/durations with ffprobe. Original diagnostic copies remain intact.

- Independent native audit found Open chat from global Tasks called the terminal-session destination. An explicit shared chat route now renders ChatSessionScreen on every platform. Fresh iOS/Mac builds and independent phone/iPad rechecks pass.

- Migration rejects malformed legacy metadata, duplicate identities/creation receipts and malformed delivery receipts atomically. Strict v2 loading prevents silently resetting a missing outbox. Original failing audit evidence remains intact.
- Two old retry tests now specify completion times. Assertions and production retry behavior remain unchanged.
- The host must remain awake. Physical iPhone APNs display remains unverified; transport in acceptance tests is fake.
- Old chat-job source files remain intact. A rollback after v2 activity needs a coordinated data backup restore. Production state remains unchanged.
