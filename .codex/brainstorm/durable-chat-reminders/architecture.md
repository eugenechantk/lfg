---
title: Unified scheduled tasks
subtitle: Coding tasks, chat reminders and condition checks share one scheduled-task primitive.
template: doc
theme: shadcn
lang: en
source: Implemented in cua-message, 27 October 2026
---

## A One primitive

A scheduled task can belong to a durable chat. It saves instructions, a schedule, a notification rule and a stopping rule.

A condition check is a recurring instruction job. It does not need a separate watcher type. The host controls time and recurrence.

| Action | Execution | Notification |
|---|---|---|
| Start coding session | Start the existing agent in its saved directory | Keep the existing session notification behavior |
| Send reminder | Add saved text to the chat without a model call | Queue its saved message |
| Run instructions | Resume the same chat with current instructions, memory and tools | Follow the returned decision or always-notify policy |

Chat and reminder actions run without a Space, desktop or tmux pane. Coding tasks retain their existing session behavior. Production remains unchanged.

## B Saved records

The host stores all tasks, run receipts and notification intents in scheduled-tasks.json, one atomic JSON store. The existing chat store keeps conversation history and provider identity.

A job records its owning chat, instructions, action, schedule, revision and next run. Stable creation identifiers make retried saves safe.

A run records the accepted instructions, occurrence, result and notification decision. A notification records delivery state separately for each registered device.

All actions share one TaskStore, run model, TaskScheduler and scheduled-task API. Session tasks retain their existing executor.

## C Execution

```flow
Chat -> Tasks: Save instructions and schedule
Tasks -> Host: Claim a due run
Host -> Chat: Add reminder or resume conversation
Chat -> Outbox: Save report and notification decision
Outbox -> iPhone: Retry delivery through APNs
```

Busy chats defer scheduled work. The host never interrupts a manual turn to start a job.

The native worker can close while idle. A scheduled run resumes the saved provider conversation with current standing instructions and memory.

## D Condition checks

For an App Store check, save instructions that identify the submission, explain how to check it, and define the notification condition.

For example: “Check this submission every 30 minutes. Notify me when Apple approves it, then stop. Otherwise report the current status without notifying.”

The run uses the host's available tools and authenticated connectors. Saved instructions define the check.

The report appears in the chat. A structured result tells the host whether to notify and stop. Quiet checks suppress generic completion notifications.

## E Management and recovery

Ask the chat to create or manage jobs. Its built-in MCP tools can create, list, edit, pause, cancel and inspect job history.

Chat settings filters Tasks by the owning chat. The main Tasks tab shows those same records alongside coding tasks.

Both views show the next run, latest report, delivery state and errors.

Edits use revision checks. Pause stops future dispatch. Cancel also suppresses pending notifications. Neither action undoes completed tool actions.

After restart, stable chat receipts prevent replaying accepted work. Interrupted accepted turns remain interrupted for inspection.

The host imports old chat jobs atomically and once. It preserves identities, revisions, run snapshots and delivery receipts, and leaves the source intact.

Malformed data or identity collisions stop the import without changing records. Older host binaries cannot read the new store format.

A rollback after new activity needs a coordinated data backup restore. Production data remains unchanged.

## F Delivery boundary

Completion and notification intent persist together. Temporary transport failures remain pending and retry independently for each device.

APNs acceptance is not proof that iOS displayed a banner. The phone's notification permission still controls presentation.

The selected host must be running and awake. Overdue work runs when the host becomes available. A sleeping host delays both checks and reminders.

A job notification carries its original chat identity. Verification covers backend contracts, actual Claude execution and native simulator flows. Physical iPhone delivery remains unverified.
