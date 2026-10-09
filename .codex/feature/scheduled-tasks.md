# Scheduled Tasks

## User story

Manage one-time and recurring Claude or Codex tasks from desktop and mobile. Create tasks through a conversation or a form, and inspect every run.

## User flow

1. Open the Scheduled Tasks mobile tab or the desktop's top-right Scheduled Tasks button.
2. Review tasks across hosts, including descriptions, models, and recent sessions.
3. Press plus to create with Claude Code, or use the menu for manual setup.
4. Discuss the work and timing, review the task, and save it.
5. View next runs, pause or edit a task, or run it now.
6. Open run history and read or continue the run's normal LFG session.

Navigation and task-row refinements are tracked in
`.codex/feature/scheduled-task-navigation.md`.

## Success criteria

- [x] SC1: One-time, interval, and five-field cron schedules validate and survive restarts. Verify with scheduler/store tests, including timezones and invalid input.
- [x] SC2: Each due task creates one Claude or Codex session and a durable run record. Verify with injected-clock tests and a real local run.
- [x] SC3: Pause, edit, cancel, run now, no overlap, restart recovery, and missed-run handling behave predictably. Verify with store/runtime integration tests.
- [x] SC4: Session tools create, list, update, and inspect scheduled tasks and history. Verify MCP calls through the real HTTP handler.
- [x] SC5: Desktop and mobile provide task lists, manual creation/editing, pause, run now, and run history. Verify builds, native UI interaction, screenshots, and recordings.
- [x] SC6: Chat creation supports back-and-forth and saves a task that appears in the manager. Verify a real conversation plus UI evidence on both platforms.
- [x] SC7: Run history shows status, timestamps, failures, and a route to the session. Verify API and native UI flows.

## Decisions

- Use host-owned schedules; local execution needs that host awake and LFG running.
- Check schedules once per minute after the initial startup check. Run now starts immediately.
- Preserve existing finding-based watches. General task runs use a separate, versioned store and the existing session creation path.
- Coalesce missed recurring runs into one run. One-time tasks run once when the host returns. Never replay every missed interval.
- Save run claims before launching; do not silently retry an uncertain launch after a crash.
- Use native SwiftUI controls shared where practical, with platform-specific navigation.
- Reuse normal LFG sessions for conversations and execution. Do not add a second model backend.
- Keep unrelated dirty work intact. No commit, push, or release is included.

## Verification evidence

The backend audit passes on current source. Evidence is in
`.codex/evidence/scheduled-tasks/backend-audit/report.md`.

- Forty-six focused backend tests pass, including MCP calls through the real HTTP handler.
- All 228 LFGCore tests pass. TypeScript checks and both native builds pass.
- Real due Claude and Codex tasks completed and retained session IDs and results.
- The iPhone created a task through chat, answered a timing question, and saved it.
- The iPhone created an interval task through the form, paused it, ran it immediately,
  and read its completed conversation from history.
- Independent audits verified desktop and mobile creation, controls, chat, and results.
- The final iPhone audit passed repeated warm task switching and clearing a model override.
- The final desktop audit passed saved-host restoration and switching away from an open run detail.

All seven success criteria passed. Native reports are in
`.codex/evidence/scheduled-tasks/native-audit/evidence.md`,
`.codex/evidence/scheduled-tasks/mobile-audit/evidence.md`, and
`.codex/evidence/scheduled-tasks/final-audit/evidence.md`.
The final report verifies the fix for the first mobile audit's stale-history failure.

Curated evidence is under `.codex/evidence/scheduled-tasks/`:
`ios-chat-saved.png`, `ios-run-history.mov`, `backend-final-tests.log`,
`core-all-tests.log`, `ios-final-build.log`, and `desktop-final-build.log`.

Verification used an isolated task store on port 8897 and current session routes
on port 8898. It did not restart production, install over the desktop app, or
publish an iOS build. The existing production host uses an older Codex executable;
its session binding failed during the first audit. Current-source acceptance passed.

## Bugs

Fixed during verification:

- One failed session inspection blocked all other due tasks. Inspections now fail independently.
- The desktop sidebar clipped its empty state. Its native column now has a usable minimum width.
- Polling replaced older loaded history. Refresh now retains those pages.
- Editing a completed one-time task could lose a fractional ISO timestamp. Parsing now preserves it.
- Desktop rows lacked a usable default accessibility action. They now use native buttons with list selection.
- Restoring a saved host could race host discovery. Initialization now reacts to the available host list as well as selection.
- Warm task switching reused history state from a different task. Detail navigation now has a separate identity for each selected task. Loading is distinct from empty history.
- Clearing an optional model kept the old override. Explicit null now restores the agent default.
- Equivalent serialized schedules could shift interval timing during an edit. Comparison now uses schedule values, not JSON field order.

The test proxy also needed to remove stale compression headers. This was a test
harness issue; production calls do not use that proxy.
