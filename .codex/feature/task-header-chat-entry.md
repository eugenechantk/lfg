# Task header and edit chat entry

Product change for the shared iPhone, iPad, and desktop task interface.

The active-count header was superseded by `.codex/feature/task-connection-chrome.md`. The form-first editing flow below remains current.

Show the total active schedule count at the left of the task list header. Count enabled schedules that can still run again. Exclude paused, completed, and cancelled schedules. Keep the total stable while searching and hide it on phone detail screens.

Task settings opens directly to the existing form. Remove the Chat/Form selector. Place Edit with chat before the form fields. One tap creates a fresh Claude Code session for the saved task, dismisses the sheet, and opens the normal session view on mobile or iTerm on desktop. The agent asks what to change. The button does not save unsaved fields or alter the schedule.

## Success criteria

- The list header shows the correct active count on the left.
- Search does not change the total; pausing or resuming changes it after refresh.
- The edit sheet shows the chat button and form without a segmented control.
- Starting chat issues one request on the task's host and routes to the new session after sheet dismissal.
- The form and dismissal controls are disabled during startup. Errors remain visible and allow a retry.
- Starting chat does not save, execute, or replace the task.
- Manual task creation remains a form without the edit-chat button.

## Verification

259 Swift Testing tests and 644 XCTest tests passed, with one XCTest skipped. Five backend API tests passed with 53 assertions. iOS and desktop builds passed.

The independent iPhone and iPad audit passed. Recordings verify the header, sidebar, form, disabled startup, session handoff, back navigation, failure, and retry. The isolated fixture uses real task routes and simulated agent sessions. Saved tasks and run histories stayed unchanged; no task execution was requested.

Native desktop captures verify the list and editor. The existing desktop session opener remains unchanged; live iTerm handoff and Claude execution were not exercised.

Evidence: `.codex/evidence/20261010-111520-ios-visual-audit/evidence.md` and `.codex/evidence/task-header-chat-entry/verification.json`. Audit simulators and fixtures were removed or stopped. No release, commit, or host restart is part of this change.
