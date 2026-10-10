# Edit scheduled tasks with an agent

## User story

Edit an existing task through a conversation or its manual form on mobile and desktop.

## Flow

Open Task settings to see the form. Edit with chat appears before its fields.
Tap it to create a fresh Claude Code session using the saved task settings.
The sheet closes and opens the normal session view on mobile or iTerm on desktop.
The agent asks what to change, then uses the update tool for that task.
Return to Task settings to see the latest saved form values.

## Success criteria

- [x] Existing tasks show the form and Edit with chat without a mode selector; manual creation still works.
- [x] Edit chat stays on the selected task's host and uses its saved directory.
- [x] The agent receives the task ID and current settings, with update-only instructions.
- [x] Starting chat does not change or run the task, or create another task.
- [x] Each Edit with chat action creates a fresh session for the selected task and host.
- [x] Reopening the form reloads saved changes.
- [x] Missing or cancelled tasks and chat-start failures produce clear errors.
- [x] Mobile uses the normal session view; desktop uses its existing session opener.

## Verification

Use real temporary task stores and API routes for backend integration tests.
Verify update prompts, task identity, host routing, error paths, and preservation
of runs. Swift tests cover edit endpoints, conversation keys, and displayed
kickoff messages. Build both clients and audit the native flow independently
against isolated fixtures. The fixture can simulate an agent conversation and
apply the requested change to a temporary task through the real task API.

## Results

The form-first follow-up is tracked in `.codex/feature/task-header-chat-entry.md`.
The results below cover the earlier editing flow.

Backend integration tests passed: 17 tests and 89 assertions across task routes
and scheduling. Swift task tests passed: 10. Both clients built successfully;
the desktop feature runner passed 173 checks.

Independent iPhone and iPad audits confirmed the normal session handoff, live
saved reply, return to the originating task, and refreshed Form state. The saved
cron changed to 10 AM. Task identity, history, timezone, directory, model, and
paused state remained intact. The fixtures use real API routes and temporary
storage, with simulated agent replies.

The first desktop audit verified Chat/Form editing and conversation isolation.
A later audit verified the final centered navigation and compact history layout.
That later pass did not launch iTerm or a live provider; the desktop session
opener is the existing implementation. Live Claude execution is not claimed.
Error paths have automated coverage; they were outside the recorded UI pass.

Reports live under `.codex/evidence/task-chat-editing/phone-audit/`,
`ipad-audit/`, `mac-audit/`, and `mac-navigation-audit/`.

## Release boundary

No commit, production task mutation, server restart, or TestFlight upload is
part of this change. Live host adoption requires deploying the new endpoint.
