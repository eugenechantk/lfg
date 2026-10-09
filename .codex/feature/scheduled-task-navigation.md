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

## Original verification

Use focused API tests for bounded, ordered run summaries and Swift tests for
decoding and host-qualified task identity. Build both native apps. Record native
navigation and obtain an independent visual audit. Reuse isolated preview hosts;
Deployment was outside the original verification scope. The later authorized
release and desktop revision are recorded below.

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


## Desktop navigation revision — 2026-10-09

Scheduled Tasks replaces the session list inside the existing desktop window. A Sessions button returns to the list. The menu-bar shortcuts select a view in that same window. Session search and grouping remain owned by ContentView during the switch.

- [x] Opening Scheduled Tasks preserves the main window identity and creates no second window. AX snapshots retain the `sessions` window identifier.
- [x] Sessions returns to the list with its search and grouping state. A unique session query and Directory grouping survive the round trip.
- [x] Plus opens Claude Code setup within the task view. The independent audit opened and dismissed the sheet without creating work.
- [x] Both installed desktop copies match the verified binary. Hashes, signatures, 168 feature assertions, and running executable paths passed.

The independent native audit passed. Opening tasks expands a compact Sessions
window to the task view's 900-point minimum. Both menu-bar shortcuts use the
same window. Evidence: `.codex/evidence/release-20261009/desktop-container-audit/evidence.md`.

The final signed desktop binary is installed and running on Pro and Air.
Its SHA-256 is `fdaffa36d3075c532f6d8c561a18e2b9bd0ce6d92218438a7f6a5e5f415fe5c3`.
Air lacks GUI inspection permissions; its install passed signature, hash,
feature, process, and API checks. The native visual audit ran on Pro.

iOS 1.3.0 build `202610091410` passed the TestFlight release checks.
It uses the committed snapshot before this desktop-only revision.
Both host servers and the Pro MCP service restarted successfully.
The one-minute scheduler launched a new session naturally on both hosts.
Pro completed successfully. Air's Claude request failed during outbound TLS
connections. Both verification sessions were then closed through the API;
their disabled one-time tasks and run history remain available.
