# Feature: Open a session's task

## User Story

Open the task that owns a session from its More options or desktop context menu.

## User Flow

1. Open More on iOS, or right-click a desktop session.
2. Choose “Go to task view” when the session has a task.
3. Show that task's detail page on its owning host.

## Success Criteria

- [x] SC1: Task associations resolve to the correct host and task, including identical task IDs on different hosts. Verify with Swift tests.
- [x] SC2: iOS More shows the action only for a task session. Tapping dismisses More and opens the task detail page. Verify with simulator recording.
- [x] SC3: The action also works when opening a session from a task's run history. Verify with simulator recording.
- [x] SC4: Desktop right-click shows the action only for a task session and opens its task detail page. Verify with desktop runtime evidence.

## Platform and Test Strategy

SwiftUI on iOS and macOS. Reuse `ScheduledTaskRoute.task` and the existing Tasks pane.
Test host-scoped task identity in LFGCore; verify the actual navigation in both apps.

## Decision Log

- Use the concise label “Go to task view” on both platforms.
- Use the session's explicit task association; do not infer one from its title or directory.
- Wait for the iOS options sheet to dismiss before changing navigation.
- Change the task path as the single navigation source. Its existing observer clears the run-session selection.
- When the owning task is already the session's parent page, use native dismissal, matching Back.
- Preserve unrelated edits already in the working tree. The initial implementation stayed local. Commit and TestFlight release were authorized on 2026-10-17; pushing was not requested.
- Preserve task metadata when desktop closed sessions and search results become display rows. The old mapping discarded it.
- Keep the existing iOS options height for ordinary sessions; add space for the new row on task sessions.

## Verification Evidence

- `swift test --package-path ios/LFGCore --filter 'SessionTaskNavigationTests|SessionSheetModelTests'`: 9 tests passed in 2 suites. Log: `.codex/evidence/session-go-to-task-20261016/swift-tests.log`.
- The new task-navigation tests failed before adding the shared identity helper, then passed after implementation.
- `flowdeck build --json`: BUILD succeeded. Log: `.codex/feature/session-go-to-task-build.jsonl`.
- iPhone 17 Pro self-check: opened Pro task run, opened More, saw the action, tapped it, and observed Pro navigation task with Fixture Pro badge. The synthetic request log records the Pro task's run-history request. Final independent recordings are listed below.
- `git diff --check`: passed after implementation.
- Desktop final build passed; `--desktop-feature-test` passed 204 assertions, including closed-session task preservation. Evidence: `.codex/evidence/session-go-to-task-20261016/desktop-audit/feature-test.json`.
- Independent desktop audit: AXShowMenu hid the action on both ordinary sessions, showed it on both task sessions, and AXPress opened each owning task despite duplicate task IDs. Parent inspected the Air menu and destination screenshots. Evidence: `desktop-audit/03-air-task-menu.png`, `04-air-task-detail.png`, `06-pro-task-menu.png`, and `07-pro-task-detail.png` beneath the evidence directory.
- Final iOS build passed at 16:09:21 UTC; all 9 focused tests passed again. Build log: `.codex/evidence/session-go-to-task-20261016/ios-final-build.jsonl`.
- Independent final-build iPhone and iPad checks passed: ordinary More hides the action, task More shows it, duplicate task IDs resolve to Fixture Air, and run-history return uses the existing task page with a clean toolbar. Recordings and screenshots: `ios-audit/iphone/final2-*` and `ios-audit/ipad/final2-*` beneath the evidence directory.
- Parent inspected the final iPad split layout and iPhone run-history screenshots. Toolbar pixel ranges in the iPhone return screenshot exactly match the clean native-Back reference: pencil x301–317; menu dots x353–356, x361–364, x369–371 at y75–93.
- Final independent reports both say PASS: `.codex/evidence/session-go-to-task-20261016/ios-audit/evidence.md` and `desktop-audit/REPORT.md`.
- Cleanup: stopped the parent's fixture app and verified/stopped synthetic host PID 26912. Ports 18891 and 18892 have no listeners. The desktop auditor stopped its test app and relocked the Mac. No commit, push, release, production restart, or installed-app replacement occurred.
- Both audit simulators are shut down. The parent simulator was also shut down after verification.

## Residual Risks

Runtime checks used synthetic local hosts, not production tasks or physical devices. Desktop archived-session association is covered by headless assertions; live runtime checks covered active synthetic rows. Existing installed desktop app and real host services were unchanged.

## Bugs

- Resolved: SC3 audit found overlapping toolbar buttons after run-history return. Fix attempt 1 removed the simultaneous session-selection update; it cleared the persistent defect but left a transient overlap. Fix attempt 2 uses native dismissal when returning to the existing parent task. Final iPhone and iPad checks passed, with the iPhone toolbar matching the native-Back reference.
