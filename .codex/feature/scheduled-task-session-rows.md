# Scheduled tasks as session rows

The later `task-detail-overview.md` refinement replaces the parameter table with
a read-only title and instructions above Sessions. Task controls move to a menu.
The completed contextual-search follow-up is documented in `scoped-tab-search.md`.

## User story

Scheduled tasks use the same compact list style as sessions. Opening a task
shows its instructions and parameters above its historical sessions.
Selecting a historical session opens the iOS conversation or desktop iTerm.

## Flow

Open Scheduled Tasks, select a row, read the task, and select a previous session.
Desktop navigation stays inside the main window until a session opens in iTerm.
The plus button continues to start Claude Code task setup.

## Success criteria

- [x] The task list uses compact rows with a status dot, title, and host/model metadata.
- [x] Selecting a task replaces the list with its detail view in the same container.
- [x] Instructions and parameters appear above the historical sessions.
- [x] Selecting a historical session opens it directly in iOS Sessions or desktop iTerm.
- [x] Older sessions outside the current desktop list remain openable.
- [x] Runs that never started a session show their failure without a broken session action.
- [x] Back navigation and Claude Code setup remain usable.

## Verification

Use the existing schedule-model tests and desktop feature harness. Add focused
coverage for resolving historical sessions beyond the loaded list.
Build both clients and independently audit the complete native navigation flow.
Use isolated fixtures and a disposable tmux session for iTerm verification.
Do not send agent prompts or change production schedules during verification.

Both native builds pass. The seven `ScheduledTasksTests` pass.
The desktop harness passes 173 assertions, including five new checks for
exact historical-session selection, resume eligibility, preserved agent and
directory, owning-host metadata, and rejecting unrelated search results.

The native audits use read-only fixture hosts on ports 8898 and 8899.
The iTerm check uses only the disposable `lfg-task-row-audit` tmux session.
Evidence is under `.codex/evidence/scheduled-task-session-rows/`.

The independent macOS audit passed at 620 points. It confirmed the same-window
detail flow, direct iTerm attachment, failure details, and setup-sheet dismissal.
The final detail has one back control. The optional 900-point check was not run.
The desktop preview and disposable tmux session were stopped after verification.
The installed production application was not replaced.

## Audit finding

The iOS audit found that an older session resolved on its task host, but its
transcript loaded from the default host. That peer may not have synced it yet.
Task navigation now preserves the source host as a read hint. A reachable live
owner still takes precedence, and agent operations keep their existing routing.
Four focused tests cover source preference, live-owner precedence, offline
fallback, and the separation between transcript reads and agent operations.
The final build passes. The focused Swift runs passed 69 tests: 30 multi-host,
22 host-state, and 17 schedule, routing, and related compatibility tests.
The fixture log confirms an exact archived-session lookup followed by a
transcript request to the same source host after the fix.

The audit also found the tab bar lifting the composer over the newest reply.
The transcript reserved only the window's home-indicator inset. It now measures
the container inset independently of the keyboard and reserves the extra space.
The keyboard replaces that clearance rather than adding it twice. All 41
transcript-window tests pass, including two new tab-bar boundary checks.
The focused Swift total is 110 passing tests.

The first fixture reused `question` and `answer` message IDs across two
conversations with different text. This violated the production identity
contract: Claude messages use transcript UUIDs, and the renderer caches
immutable text by that ID. The fixture now uses distinct message IDs and fresh
session IDs. Both exact-reply visibility checks passed against the unchanged final app. No production data or local database was edited.

## Release boundary

These changes remain uncommitted. The installed production apps and servers
were not replaced during this UI update. Desktop remote opening still depends
on the existing iTerm attach/resume path and host connectivity.

## Final native verification

Both independent native audits pass. The iOS audit confirms current and
archived conversations display their own full replies above the composer.
Software-keyboard show and hide also preserve readability. The audit retains
screenshots and recordings in `ios-audit/`; desktop evidence is in `mac-audit/`.

The simulator hardware-keyboard setting was preserved, and the temporary
software-keyboard toggle was restored after verification.

The temporary fixture servers, test app, desktop preview, tmux session, and
capture streams were stopped. The installed desktop app remained running.
Cleanup evidence is in `final-cleanup.json`.

## Follow-up: native tab-bar search

The user identified the crowded search and tab layout after the task-row work.
Apple's current Search fields HIG calls the intended pattern Search as a tab.
Its button appearance supports quick search and returns to the previous tab.

The session list still installs its original bottom search toolbar and plus
button. RootView now also installs a tab bar, so both surfaces compete for the
same bottom area. This design concern was outside the earlier navigation audit.

Recommendation: keep Sessions and Scheduled Tasks as the main destinations,
add the native search control beside them, and move the new-session action to
the top toolbar. For iOS 26, Apple's example uses `Tab(role: .search)` and places
`.searchable` on the containing `TabView`. The search correction is not yet
implemented. Decide search scope when implementing the shared search surface.

Sources checked live on 2026-10-09:
- https://developer.apple.com/design/human-interface-guidelines/search-fields
- https://developer.apple.com/design/human-interface-guidelines/tab-bars
- https://developer.apple.com/videos/play/wwdc2025/323/?time=797
