# Scheduled tasks in LFG

Checked 2026-10-09. Research and recommendation only; no runtime changes or tasks created.

## Decision

Both providers already support scheduling. LFG's opportunity is one phone interface for persistent tasks across Claude, Codex, and the user's hosts.

Extend LFG's existing scheduler if we pursue this. Keep existing finding-based watches compatible while adding general session tasks.

## Current provider support

- **Codex:** Scheduled tasks are managed through ChatGPT desktop or web. Local project runs need the computer and desktop app running. Advanced schedules use RRULE. Codex CLI has no Scheduled management interface. [Official documentation](https://learn.chatgpt.com/docs/automations?surface=app).
- **Claude Code:** `/loop` and `CronCreate` support local recurring prompts and one-time tasks. They need a running session; recurring tasks expire after seven days. Some tasks restore when a session resumes. [Official documentation](https://code.claude.com/docs/en/scheduled-tasks).
- **Claude cloud routines:** `/schedule` creates durable recurring or one-time tasks. Custom cron intervals must be at least hourly. Cloud runs do not require the user's computer. [Official documentation](https://code.claude.com/docs/en/routines).
- **Claude Cowork:** Supports recurring tasks, including remote execution. Tasks needing local files or apps run locally. [Official documentation](https://support.claude.com/en/articles/13854387-schedule-recurring-tasks-in-claude-cowork).

## Existing LFG foundation

- `src/auto/scheduler.ts`: five-field cron matching, one-minute polling, configurable host timezone, and about 25 hours of catch-up.
- `src/auto/store.ts`: saved prompts, schedules, enabled state, working directories, and last-run timestamps.
- `src/auto/runner.ts`: Claude-only headless execution, read-only tools by default, and a finding-or-silence output contract.
- `src/commands/serve.ts`: task CRUD and manual-run endpoints; starts the scheduler when background tasks are enabled.

The local host answered `GET /api/auto/agents`: zero configured tasks, timezone `Asia/Hong_Kong`. This proves endpoint availability, not successful scheduled execution.

## Recommended first scope

1. Choose Claude or Codex, host, repository, prompt, and model.
2. Support one-time, repeating interval, and cron schedules with an explicit timezone.
3. Create a normal LFG session for each run so results remain inspectable and steerable.
4. Add phone controls for pause, run now, next run, and history.
5. Record success and failure, prevent overlapping runs, and define restart catch-up behavior.
6. Notify when a run finishes or needs input, using the task's saved permissions.

Local jobs still require their selected host to be awake and LFG running. Reliable scheduling needs durable run records and strict cron validation beyond the current implementation.
