# Scheduled task navigation

## User story

Sessions and Scheduled Tasks are separate mobile tabs. A visible desktop button
opens every scheduled task. Each task shows its instructions, host, model, and
previous sessions. Plus starts a conversation with Claude Code.

## Success criteria

- [x] Mobile has exactly two tabs. Switching tabs preserves navigation. Opening
  a historical session selects Sessions and opens the correct conversation.
- [x] Desktop has a top-right Scheduled Tasks button, including at compact width.
- [x] The task list combines configured hosts. Each row shows description, host,
  model or an explicit agent-default label, and recent historical sessions.
- [x] Historical rows open their run and conversation. Full history remains accessible.
- [x] Plus opens chat setup directly with Claude Code and a host selector. Chat
  supports follow-up replies and saves tasks visible in the list.

## Verification

Use focused API tests for bounded, ordered run summaries and Swift tests for
decoding and host-qualified task identity. Build both native apps. Record native
navigation and obtain an independent visual audit. Reuse isolated preview hosts;
do not deploy, commit, or replace the installed desktop application.

- `ScheduledTasksTests.swift`: seven tests pass, including recent sessions,
  compatibility with older hosts, model defaults, and host-qualified task identity.
- `scheduled-task-api.test.ts` and `scheduled-tasks.test.ts`: 15 tests and 53 assertions pass.
- TypeScript checks and both native builds pass.
- All 168 desktop assertions pass. The window-fit harness keeps every toolbar
  item visible at 620, 900, 1199, and 1200 points.
- Evidence: `.codex/evidence/scheduled-task-navigation/`.
- The independent mobile audit passed all criteria, including real Claude Code
  follow-up questions and saving a paused task.
- Desktop flows passed, but a 900-point window hid Scheduled Tasks in overflow.
  The toolbar now uses compact controls below 1200 points. A fresh independent
  audit passed at 620, 900, 1199, and 1200 points and opened tasks at 900 points.
- Final reports: `mobile-audit/evidence.md`, `desktop-audit/evidence.md`, and
  `final-toolbar-audit/evidence.md` under the evidence directory.

## Decisions

Show the latest three runs inline and offer full history. Preserve the existing
manual editor as a secondary menu action. Keep each host's task identity separate.
Use Claude Code for the setup conversation; execution can use Claude or Codex.

## Bugs and residual risks

The desktop audit found a toolbar overflow at medium widths. The compact layout
now extends through those widths and reserves space for all five actions.
The final native width checks passed. No known acceptance failures remain.
The installed desktop app, production host, and published mobile build were not
replaced by this task. Test sessions closed, preview processes stopped, and test
tasks remain disabled with their transcripts preserved.
