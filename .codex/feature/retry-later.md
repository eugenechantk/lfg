# Feature: Retry later

## User story and flow

Retry a task when I am available, using a delay in minutes or an exact local date and time.
Choose Retry later beside Retry now. Choose 35, 45, or 60 minutes, enter custom minutes, or choose a date and time.
Save one retry. See its time in the task card and list. Change or cancel it before it starts.

## Success criteria

- [x] SC1: Relative delays and exact dates produce a future instant; invalid values cannot save. Verify with Swift tests and simulator recording.
- [x] SC2: A retry survives a host restart and starts once when due, including paused and completed tasks. Verify with real-store scheduler tests.
- [x] SC3: Retrying preserves recurring settings, next run, and finite occurrence budget. Verify with scheduler tests.
- [x] SC4: A pending retry can be replaced or cancelled. Run now and stopping future runs clear it. Active tasks cannot queue a second run. Verify with store/API tests.
- [x] SC5: iPhone, iPad, and Mac show Retry later, saved time, and controls. Network failures keep the form open. Verify builds, client tests, and an independent visual audit.

## Platform and implementation

Bun/TypeScript host and shared SwiftUI task views backed by LFGCore.
Persist one optional retryAt timestamp per task. Claim retries atomically as manual runs, separate from scheduled occurrences.
Use the existing host scheduler, including its minute polling and catch-up after sleep.

## Decision log

- Preserve the recurring schedule. A retry is an extra manual run, even when the recurring task is paused or finished.
- One pending retry per task; saving again replaces it. A run already in progress blocks scheduling a retry.
- If a regular occurrence and retry are due together, one retry runs first. The regular occurrence waits for that run to finish.
- A manual Run now consumes a pending retry. Regular scheduled runs keep their normal timing.
- Display local date and time with timezone in the picker. Do not change the task's execution timezone.
- No production task changes, host restart, release, commit, or push are required for development verification.

## Verification evidence

- Host: `bun test src/scheduled*.test.ts`: 57 tests passed, 330 assertions. Log: `.codex/feature/retry-later-host-tests.txt`.
- Swift: `swift test --package-path ios/LFGCore`: 464 tests in 69 suites passed. Log: `.codex/feature/retry-later-swift-tests.txt`.
- Builds: `flowdeck build --json` passed for iOS; `LFG_DESKTOP_OPTIMIZATION=-Onone bash desktop/build.sh` passed for Mac. Mac uses its existing standalone Swift build script because FlowDeck discovers only the iOS project.
- SC1/SC5 self-check: iPhone simulator `cc-01a14c70-retry` saved the 35-minute preset through the real UI and production API. `retryAt=1792286337000`; regular `nextRunAt=1792370485929` and `scheduledRunCount=0` remained unchanged.
- Self-check screenshots and navigation traces: `.codex/evidence/retry-later/navigation/20261018-084300-in-lfg-open-tasks-open-the-task-retry-la/` and `20261018-084354-in-the-retry-later-sheet-tap-schedule-re/`.
- Independent iPhone audit passed: invalid zero minutes disables saving; custom seven minutes persists; exact-time change persists; cancellation clears the retry; injected HTTP 503 retains the sheet, entered value 23, and visible error. Recordings and state snapshots: `.codex/evidence/20261018-084454-ios-visual-audit/iphone/`.
- Independent audit: **PASS**, all five criteria. iPad saved the 35-minute preset and displayed pending controls. Mac navigation verified the pending card, exact-time and minutes modes, presets, change, and cancellation controls.
- Final report: `.codex/evidence/20261018-084454-ios-visual-audit/evidence.md`. The report maps each criterion to recordings, screenshots, state snapshots, or test output.
- No product failures remain. No release, commit, or push was performed.

### Recheck on October 18 at 9:04 AM HKT

- Found the completed implementation and audit already in this checkout. No product code changed during this recheck.
- Re-ran host tests: 57 passed, 330 assertions. Log: `.codex/feature/retry-later-host-recheck.txt`.
- Re-ran Swift tests: 464 passed in 69 suites. Log: `.codex/feature/retry-later-swift-recheck.txt`.
- Reviewed the iPhone, iPad, and Mac evidence above. All seven changed source files predate the 8:54 AM independent PASS report.
- `git diff --check` passed.
- A fresh default build compiled but failed at local ad-hoc signing with `internal error in Code Signing subsystem`, twice. The simulator build passed with the one-command override `CODE_SIGNING_ALLOWED=NO`. Log: `.codex/feature/retry-later-build-recheck-unsigned.jsonl`.
- The original signed build and UI audit remain the runtime evidence. This recheck does not prove a new signed build or release. No signing settings, keychain data, production host, or real tasks changed.

## Test and verification corrections

- Initial Swift tests exposed two fixture mistakes: a record was encoded despite being decode-only, and a schedule omitted its required timezone. Corrected the test fixtures; all Swift tests then passed.
- A first simulator navigation attempt ran during initial boot and could not read the accessibility tree. The completed launch and subsequent navigation succeeded.
- FlowDeck's tree omits native navigation-toolbar buttons. `sim-navigate` reads the complete tree and successfully tapped Schedule retry.
- Mac snapshots must set `LFG_DESKTOP_CONFIG_DIR` to an isolated fixture config. Its hosts file needs the wrapper `{"hosts":[...]}`; an array is invalid and seeds bundled hosts. Corrected our owned fixture config. No production config was changed.

## Bugs

None yet.
