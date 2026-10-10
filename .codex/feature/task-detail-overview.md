# Task detail overview

## User story

Open a scheduled task and read its title and instructions, followed by a list
of the sessions it triggered. The title and instructions are read-only.

## Flow

Select a task in Tasks. Its title, schedule in device time, and a three-line preview of its
secondary-colored instructions appear above SESSIONS. Show more reveals the full
instructions; Show less collapses them again. Short instructions need no toggle.
Select a history row to open its conversation on iOS or iTerm on Mac.
Task settings and schedule actions live in the toolbar's Task options menu.
Existing failure details remain available for a run that never started a session.

## Success criteria

- [x] The detail starts with a readable, selectable title and instructions.
- [x] No editable fields, parameter table, or action rows interrupt the overview.
- [x] Sessions appear as a list below the instructions and open as before.
- [x] Empty history and failed runs remain understandable.
- [x] Task options and Back navigation remain usable.
- [x] The layout works on iPhone, iPad, and desktop in the same container.

## Verification

This is a presentation change in the shared SwiftUI view. Keep the existing
history fetching and navigation logic. Build both clients, run the existing
scheduled-task tests and desktop harness, then independently audit the native
views with read-only fixtures. Do not create tasks or send session prompts.

Both native builds passed. All 11 focused Swift tests and 173 desktop assertions
passed. Independent audits passed on iPhone 17 Pro and iPad Pro 11-inch running
iOS/iPadOS 26.3, plus the desktop client at 620-point width.

Evidence reports and native captures:
- `.codex/evidence/task-detail-overview/phone-audit/evidence.md`
- `.codex/evidence/task-detail-overview/ipad-audit/evidence.md`
- `.codex/evidence/task-detail-overview/mac-audit/evidence.md`

The audits verified current and older conversations, selectable overview text,
empty history, failed-run details, menu dismissal, and Back navigation. Desktop
history attached the disposable tmux session in iTerm. No task or session was
changed, and no prompt was sent.

Test apps, recorders, capture streams, fixture servers, and the disposable tmux
session were stopped. The Mac was re-locked. The installed desktop app stayed
running throughout verification.

## Release boundary

Do not commit, install a production build, or restart host services in this turn.
