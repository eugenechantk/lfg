# Scheduled tasks in chats

A scheduled task can belong to one durable chat. It saves a schedule and instructions on that chat's host. Chat actions need no Space or terminal.

Ask the chat to create a job, or open **Chat settings → Tasks**. The chat has built-in tools to create, read, edit, pause and cancel jobs. The native screen shows the next run, latest report and notification state.

## Three actions, one primitive

**Start coding session** keeps the existing directory, agent, model and terminal-session behavior.

**Send reminder** saves fixed text. At the due time, the host adds the reminder to the chat and queues an iOS notification. This action does not call a model.

**Run instructions** resumes the same chat with its current standing instructions and memory. It can use the chat's tools, shell, files, configured MCP servers and skills. The saved instructions describe the check, follow-up action, notification condition and stopping condition.

For example: “Every 30 minutes, check this submission's review state. Notify me when Apple approves it, then stop. Otherwise report the current state without notifying.” The required account or connector must already work on the owning host.

The host controls scheduling. A model does not idle between runs. Busy chats defer tasks until the current turn finishes.

## Schedule and results

The native form creates one-time or interval schedules with a timezone. Chat tools and the API also support cron and finite repeat schedules. Editing instructions preserves an existing schedule unless the editor changes it explicitly.

An instruction run returns a report and a structured decision: notify, notification text and stop. The chat transcript shows the report. The host stores the decision separately. Checks can remain quiet until a condition matches. The optional always-notify policy alerts after each successful run. Invalid results and execution errors never produce success alerts.

Pause prevents new dispatch. Cancel also cancels unsent notifications. Cancellation does not interrupt an accepted turn or undo its completed actions. Changed instructions apply to future runs.

## Recovery and delivery

The host saves completion and notification intent together. Stable run identifiers prevent replaying accepted chat work after restart. Interrupted accepted turns stay interrupted; inspect them rather than automatically repeating tools or remote actions.

The host retries pending notifications per registered device. A failed phone does not block another phone. Transport receipts survive restart. Cancellation suppresses pending delivery; it cannot recall a notification already accepted by APNs.

Job notifications carry the original chat identity and use the existing push navigation. Scheduled turns suppress the generic “finished” notification. The next manually sent turn restores normal completion notifications.

The selected host must be running and awake. Overdue work runs when it becomes available. This is not a cloud scheduler. iOS permission and the host's APNs configuration still control notification delivery. “Notification sent” means transport acceptance, not proof that the phone displayed it.

## Shared backend and client surface

All actions use `TaskStore`, `TaskScheduler`, the same task/run records, and `/api/scheduled-tasks`. The main Tasks tab shows every action. Chat settings shows a filtered view of those same records. Editing, pausing or cancelling in either view updates the same task.

The action is `session` (also the default for legacy tasks), `chat`, or `notify`. Chat and reminder actions require an owning `chatId`. They use that chat's provider settings. Only session actions require a directory and agent.

- `GET /api/scheduled-tasks?chatId=<chat-id>` filters tasks by owner.
- `POST /api/scheduled-tasks` creates a task; chat actions require a stable `requestID`.
- `GET /api/scheduled-tasks/<task-id>` reads the task, runs and notification receipts.
- `POST /api/scheduled-tasks/<task-id>` edits fields; chat actions require the last read revision.
- `POST /api/scheduled-tasks/<task-id>/cancel` cancels the task.
- `POST /api/scheduled-tasks/<task-id>/run` requests an immediate run.

The private worker configuration adds `/api/scheduled-tasks/mcp/<chat-id>`. It keeps the host's other MCP configuration. Its tools are `create_scheduled_task`, `list_scheduled_tasks`, `update_scheduled_task`, `scheduled_task_runs`, `run_scheduled_task` and `cancel_scheduled_task`. The server supplies the owning chat and rejects access to other chats' tasks.

Old `/api/chat-jobs` routes and job tools remain compatibility adapters. They translate field names and use the same canonical records. They own no separate file or scheduler loop.

## Storage upgrade

Records and the notification outbox live in `LFG_DATA/scheduled-tasks.json`, normally `~/.lfg/scheduled-tasks.json`. The new store format is version two. Version-one scheduled tasks remain readable and keep their original behavior.

When the new host starts, it imports an existing `chat-jobs.json` once, in one atomic write. It preserves task IDs, creation receipts, revisions, accepted run snapshots and per-device notification receipts. Malformed data or identity collisions stop the import without changing the destination. Accepted chat work does not replay.

The original chat-job file stays intact as a backup. Older host binaries cannot read the new task format. Rollback needs a coordinated data backup restore; the old chat-job file alone is insufficient after new activity.

This implementation was tested with temporary stores. Production data has not been migrated or restarted by this change.
