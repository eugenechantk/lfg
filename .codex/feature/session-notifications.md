# Custom session notifications

## User story and flow

Sessions need to explain progress, results, blockers, and reminders in alerts across LFG clients.
The session sends a short message through `lfg notify`, MCP, or HTTP. The host saves a receipt,
publishes a journal event for Macs, and sends the same alert to every registered iPhone and iPad.
Tapping the alert keeps the existing session route.

## Success criteria

- [x] SC1: Custom text and status reach every registered mobile client. Verify with notification service integration tests and APNs payload tests.
- [x] SC2: The Mac consumes custom alerts through its resumable host feed. Verify with desktop feature tests covering decode, reconciliation, and duplicate suppression.
- [x] SC3: CLI and MCP accept the same contract and return honest delivery receipts. Verify with CLI/HTTP integration and MCP tests.
- [x] SC4: Completed alerts suppress the generic finish for the same turn. Later turns and real questions still notify. Verify with watcher and desktop regression tests.
- [x] SC5: Blank, oversized, cross-origin, unknown-session, and conflicting retry requests fail safely. Same request IDs never resend. Verify with service and HTTP tests.
- [x] SC6: Automatic completion uses current assistant prose when available. Verify with watcher and desktop tests.
- [x] SC7: Independent audit passes. Verify with the software-development verification auditor.

## Platform and scope

TypeScript/Bun host and CLI; native Swift macOS client. iOS already renders APNs alert text.
No new screen, scheduler, database migration, commit, push, release, or host restart.

## Decisions

- One message fans out to all clients. Client selection and device-specific copy are unnecessary for this request.
- Status describes the alert; it does not overwrite real session execution state.
- The latest completion receipt is independent of the latest alert. Both host and desktop track its identity, so reminders and delayed snapshots cannot rearm a later turn.
- Keep bounded JSON receipts outside the synced repo. Request IDs make ambiguous retries safe.
- Mobile acceptance means APNs accepted the alert, not that a person saw it.
- Use the existing native desktop build script: this target has no Xcode project.

## Verification evidence

- SC1, SC3, SC4, SC5, SC6: `bun test` across 14 affected suites passed 196 tests and 629 assertions. Evidence: `session-notifications/regressions.txt`.
- SC2: `desktop/build.sh` succeeded. The real executable's `--desktop-feature-test` passed 282 checks. Evidence: `session-notifications/desktop-build.txt` and `desktop-tests.txt`.
- SC3: A real isolated `cmdServe({backgroundTasks:false})` on loopback port 18769 created a chat, accepted a custom completed alert, persisted one journal event, and returned duplicate=true on retry. Mobile state was unavailable because no device was registered in the isolated data directory. Evidence: `session-notifications/real-route-proof.json`.
- TypeScript: `bunx tsc --noEmit` passed. `git diff --check` passed.
- Native visual banner and physical iPhone/iPad arrival have not been tested. Tests prove production payload construction, route handling, journal delivery, and desktop posting candidates.
- SC7: Independent audit PASS for SC1-SC6. The configured auditor model was unavailable, so a separate supported agent performed the gate. It passed 208 Bun tests / 716 assertions, including 12 adversarial tests; 21 native probes; 282 checks in the final executable; a fresh real host/CLI/MCP flow; type checking, diff checks, and source/binary hashes. Evidence: `session-notifications/audit/audit-report.md`.


## Bugs

No open findings. Fixed during verification:

- Capped and sanitized the source title in APNs snapshots.
- Rejected unpaired surrogates and control text before saving or publishing alerts.
- Added explicit completion receipts independent of later reminders.
- Scoped duplicate suppression to each busy interval in both host and desktop.
- Preserved completion receipts when late REST snapshots reconcile with newer events.

## Release boundary

Implemented and verified locally. No commit, push, production host restart, desktop installation, or TestFlight release.
The host and Mac client need rollout. Existing iPhone/iPad clients already render the supplied APNs alert text.
Physical arrival and native banner rendering remain unverified.

## Rollout follow-up

Pro host and MCP restarted on 2026-10-29. The signed Mac app is installed and running from /Applications/lfg.app. Independent deployment audit passed; all 31 task configurations and 37 terminal sessions remain preserved. The release also preserves the existing offline-chat fix.

Air remains pending because SSH fails and its authenticated API returns HTTP 530. Packages and receipts are in `.codex/feature/session-notifications-release-202610291845/`. No commit or push occurred.
