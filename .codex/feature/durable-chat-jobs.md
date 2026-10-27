# Durable chat jobs

Product tier. Implement both reminders and recurring instruction jobs in one primitive.

## User story and flow

Ask a durable chat to schedule a job, or open Jobs in its settings. Save a schedule and instructions. At the due time, send a reminder directly or run the instructions in the same durable conversation. Instructions decide whether a result needs a notification and whether the job should stop. Tap the iOS notification to return to that chat. Inspect, edit, pause and cancel jobs without a Space.

## Success criteria

- [x] SC1: One persisted job model supports one-off reminders and repeated instruction runs with timezone validation, revision-safe edits, pause/cancel and stable creation receipts. Verify Bun API/store tests and Swift client contracts.
- [x] SC2: Run jobs resume the owning chat with its current instructions/memory; busy chats defer jobs; restart/duplicate receipts never replay accepted work. Verify integration tests using real ChatSessions storage and a deterministic runner.
- [x] SC3: Structured job results control notification and stopping. Unchanged checks stay quiet; malformed results/errors do not become success alerts. Verify parser and recurring-job integration tests.
- [x] SC4: Completed runs and notification intents persist atomically. Notification delivery retries per device, retains accepted receipts and suppresses canceled jobs. Verify injectable APNs transport, restart and retry tests.
- [x] SC5: Every native durable chat has built-in job tools through its owning host, preserving other configured MCP servers. Verify MCP protocol tests, native launch tests and isolated real provider creation/run probe.
- [x] SC6: Jobs UI creates, lists, edits, pauses, cancels and shows result/delivery state. Job push payload opens the original chat. Verify Swift tests, phone/iPad native flow, and independent visual audit.
- [x] SC7: Existing scheduled tasks, normal chat sending, generic completion notifications and terminal discovery keep working. Scheduled checks suppress generic finished pushes. Verify targeted regressions, TypeScript check and native builds.

## Decisions

- Reuse schedule validation/next-occurrence logic from scheduled-tasks.ts. Jobs own a dedicated store/executor because the older executor creates terminal sessions. Both new behaviors share one model and lifecycle; there is no Apple-specific watcher engine or new OS cron service.
- Add a direct notification action for fixed text and an instruction action for checks. The host owns time, recurrence and durable delivery, not an idle model or a provider-native loop.
- A recurring instruction can notify conditionally and stop on its matched result. The same mechanism supports any available connector/tool.
- Keep job tools scoped to the current chat through a loopback MCP endpoint. Merge this server with normal host MCP configuration. No secrets on argv.
- Use existing APNs alert transport and registered devices. Retain pending alerts when push is unavailable; acceptance is not proof of display. Local iOS mirroring and new cloud hosting are outside this implementation.
- Keep production host/8766 and live schedules untouched. No commit, push or release unless explicitly requested.

## Verification evidence

- Red store/API test initially failed on the missing job primitive: `durable-chat-jobs/red-tests.txt`.
- 135 Bun tests, 504 assertions passed across jobs, chat, legacy scheduler/API and APNs/watcher regressions. `durable-chat-jobs/backend-tests.txt`.
- TypeScript check passed. `durable-chat-jobs/types.txt`.
- 10 Swift client/presentation tests passed, including queued one-off pause state. `durable-chat-jobs/swift-tests.txt`.
- Broader Swift push, chat and scheduler regressions passed: 73 tests / 13 suites. `durable-chat-jobs/swift-regressions.txt`.
- Final iOS and Mac builds passed: `durable-chat-jobs/ios-hit-area-build.jsonl` and `durable-chat-jobs/mac-hit-area-build.txt`.
- Actual Claude Code acceptance passed: the built-in chat-scoped HTTP MCP tool created both job actions; a virtual due time dispatched them; the conditional instruction used edited memory (Pip to Miso), completed in the same provider conversation and produced one conditional notification intent. Fixed reminder produced a second intent without a model call. APNs delivery used a fake registered device/transport. `durable-chat-jobs/live-report.json` and `live-probe.ts`.
- Independent backend audit PASS: 201 product tests / 882 assertions, 15 independent probes / 38 assertions, and TypeScript check. All twelve source fingerprints match. `durable-chat-jobs/backend-audit/final-recheck-report.md`.
- Two unchanged legacy auto-retry tests depend on an October 21 fixture clock. Their entire suite passes 20 tests / 63 assertions with that clock. No legacy source was changed.
- Initial independent native audit exercised phone and iPad flows, then found a narrow row tap area and an unproven notification-tap path. Its PARTIAL report remains unchanged: `.codex/evidence/20261026-162130-ios-visual-audit/evidence.md`.
- Fresh final native audit PASS: identifier and real center touches open Jobs and Edit job on iPhone and landscape iPad. A cold simulated notification opens the exact owning Scout chat after normal onboarding saved the isolated fixture host. Three final H.264 recordings validate. `.codex/evidence/20261026-durable-jobs-recheck/evidence.md`.
- The initial cold-launch test lost fixture-only environment settings; this was a test setup issue. The recheck used persistent normal client settings. Physical APNs delivery remains unverified.
- Review gallery includes original flow captures, fresh recheck captures and six recordings. Review copies correct the iPad video display rotation without changing frames; originals remain intact.
- `git diff --check` passed. User/runtime documentation: `docs/chat-jobs.md`.


## Bugs

- Fixed `send` callback shadowing its scheduled-job parameter with the existing running-job local variable.
- Fixed Swift test fixtures running concurrently across two serialized suites. Consolidated into one serialized suite.
- Fixed the shared Jobs view importing LFGCore unconditionally in the Mac's single-module build.
- Fixed creation receipts after due time, queued reminder pause/resume, and notification acceptance when all device tokens are retired.
- Fixed the native queued one-off job losing its Pause button after claiming its only schedule occurrence. Paused queued jobs now display Paused. Added Swift presentation regressions, then rebuilt iOS and Mac.


- Fixed the new Jobs link and job edit rows ignoring touches in empty label space under plain button styling. Their padded labels now define a rectangular hit area.

## Independent audit fixes

- Retain notification intents through temporary push outages without exhausting an attempt budget.
- Retire replaced device receipts and rotate pending notification batches so retrying phones cannot starve new alerts.
- Budget JSON-escaped UTF-8 bytes when truncating APNs text.
- Defer busy dispatch races without bypassing pause. Recheck cancellation after awaited chat lookup and payload preparation.
- Reject edits to immutable action, chat and creation identifier. Preserve original creation fingerprints across edits and overdue retries.

## Residual limits

- Physical iPhone APNs display is not proven. Backend transport probes use fakes; simulator injection only proves client routing.
- The owning host must remain running and awake. No cloud scheduler or local iOS fallback was added.
- Provider tools can perform side effects. Recovery never automatically replays an accepted interrupted turn.
- Production host and live schedules are unchanged. No commit, push, TestFlight upload or deployment has occurred.

## Review handoff

- Native screenshots, recordings and architecture: https://share.eugenechantk.me/durable-chat-jobs-e06508/
- Self-contained architecture file: `.codex/brainstorm/durable-chat-reminders/architecture.html`. Updated the earlier phased proposal to match the implemented generic job model.
- Gallery source: `durable-chat-jobs/build_review.py`. Media stays on this MacBook Pro. The link has no login and stops after reboot until sharing restarts.
- Production deployment, Git commit/push and TestFlight release remain outside this handoff.
