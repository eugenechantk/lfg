# Desktop client redesign — proposal (2026-10-15)

Canvas: LFG UI Map, https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD — "Desktop · A2" row (`dA2-*`) on the Tasks redesign page is current; the wide exploration (`dW-*`) is on the "Desktop wide window (Oct 15)" page. The original standalone canvas (7MwhGQnrcbGdoyMzbpt5n4) is superseded.
Status: proposal only. No code changed.

## What is wrong today

1. The app is the iPhone layout in a Mac window. One column, list → push → detail. At 1200pt the rows stretch across the whole window and most of it is empty.
2. Task rows show name, a schedule sentence and host · model. They do not show when the task runs next, how the last runs went, or whether it is enabled.
3. Task detail is a title, a sentence and a flat "SESSIONS" list. Every action (Run now, Pause, Settings, Cancel) is behind one ⋯ menu.
4. Editing is a 650×720 modal grouped Form. The schedule is a dropdown ("Repeat a set number of times"), cron is five separate fields, and nothing shows the next run dates.
5. Two unrelated create flows: "+" opens the chat sheet, manual setup hides in ⋯ as one item per host.
6. Host status, grouping and filters live in toolbar chips and the More menu, which fight over the ~300pt toolbar budget.

## The proposal in one line

A native three-pane Mac window: sidebar (views + hosts) → list → detail with an inspector. No modal forms for editing.

| Artboard | What it shows |
| --- | --- |
| Main — Tasks | Sidebar, task list grouped Running now / Up next / Paused / Finished, detail with actions in the bar, instructions card, run-duration strip, run table with inline result, Details inspector. Click a task, a run, Pause, or the switch. |
| Schedule editor | Popover from the inspector's Schedule row. Modes: Once · Days and time · Every… · Cron. Live sentence + next dates as chips + the cron equivalent. |
| New task — describe it | Prompt-first composer with host and directory chips. Examples fill the box. Shows the in-progress setup chat. |
| New task — set up manually | Same sheet, second tab. Name + big instructions editor on the left, settings column on the right. |
| Sessions | Same sidebar. Needs you / Working / Recent list. Detail answers the live question in place, shows the last exchange, and has Open in iTerm, Fork, Switch tool. |
| Narrow window | Sidebar collapsed into a title menu, "needs you" count stays visible, hosts in a footer. |

## Mapping to the data model (keeps the design honest)

| UI | Existing field / endpoint |
| --- | --- |
| Next run, "in 14h" | `nextRunAt` |
| Row history dots, run strip | `recentRuns`, `/runs` (status, startedAt, finishedAt) |
| Inline run result | `run.summary`, `run.error` — replaces the Run details sheet |
| Pause / Resume, switch | existing `act(…, enabled:)` |
| Days and time mode | `kind: "cron"` (`0 9 * * 1-5`); "Add a time" = hour list |
| Every… + Ends Never | `kind: "interval"` (minutes; hours/days × 60/1440) |
| Every… + Ends After N | `kind: "repeat"` (occurrences, everyMinutes, first start) |
| Upcoming dates | computed client-side from the schedule |
| Answer a question from desktop | `POST /api/sessions/:id/answer` (iOS already uses it) |
| "Continue previous setup" | the saved chat key the chat sheet already stores |

New work the design implies:

- **"Latest" exchange in Sessions** needs a transcript read on desktop. The server has it; the desktop does not fetch it today.
- **Run activity** (sidebar) is a cross-task run feed. It can start from each task's `recentRuns`.
- **Projects in the sidebar** replaces "group by directory" in the More menu.
- **Examples in New task** are new copy.

## Visual system

Native macOS 26 dark. System font (SF Pro). Graphite panes (#161618 window, #232327 sidebar, #1A1A1D inspector). One accent (blue #3B8EFF, a canvas tweak). Status is colour plus shape: running = ring, scheduled = clock, paused = bars, failed = ×, needs you = orange !. 13pt body, 22pt detail title.

## References (Mobbin)

- Linear project page — list with a properties inspector: https://mobbin.com/screens/212fda35-366e-4dc0-a1d1-3b679659d6ab
- Databricks job — run-duration chart over a run table, details panel: https://mobbin.com/screens/1bd9f80c-3c2d-46ba-bd06-b6177a78ebdb
- Hex scheduled runs — schedule + next + timezone in one cell: https://mobbin.com/screens/a9e8931d-c5f9-432d-8f2d-85bdd0554412
- Emergent tasks — next-run chip, switch, execution history: https://mobbin.com/screens/8ff17900-8340-41a4-a90d-3510fe14bc94
- Gemini scheduled actions: https://mobbin.com/screens/a9515df0-210d-4edb-aac6-a4027e28ee37
- Luma recurrence (date chips): https://mobbin.com/screens/df491cad-5809-4312-921c-5af20484862e
- Posh recurrence (ends after N, sentence): https://mobbin.com/screens/189b8716-c548-4120-b321-c5b561dde52d
- Sweatpals recurrence (segmented frequency, day chips): https://mobbin.com/screens/f6fc1f93-23dc-41ed-984a-4da3f79aa35d
- Cursor agents — sidebar views + group/filter: https://mobbin.com/screens/ef7c23a0-61cc-4d41-8988-7c3d84610f2f
- Lemni agents — three panes, instructions as a document: https://mobbin.com/screens/03a83600-7b5f-4941-aa72-a1dd91b5dd93

## Open decisions

1. Sidebar replaces the centered Sessions/Tasks switcher. That undoes the recent single-row/centered switcher work. Recommended: yes — the switcher was a phone pattern.
2. Inline editing in the inspector replaces the edit sheet. Recommended: yes for schedule/host/model/directory; instructions edit in place.
3. Session detail pane on desktop (today a click opens iTerm directly). Recommended: single click selects, double click / Return opens iTerm.

## Implementation notes (for later)

- `shared/ScheduledTasksView.swift` is shared with iOS and was being edited by another session (finite-repeat schedules) on 2026-10-15. Build the Mac layout as a separate `#if os(macOS)` view tree rather than more `#if` branches inside the shared one.
- `NavigationSplitView` three-column gives the sidebar collapse for free; re-measure toolbar fit with `lfg --window-fit`.

## Round 2 — narrow window first (Eugene's real usage)

Eugene runs the desktop app narrow, so list, task and edit stack as pushed pages. Row 3 on the canvas
("Narrow window: one stack, list → task → edit") is now the primary proposal; rows 1–2 are the wide case.

| Page | Key change from today |
| --- | --- |
| 1 Tasks list | Keeps the centered Sessions/Tasks switcher (with a needs-you count). Status line + host dots replace toolbar chips. Rows show next run and 5 run dots. A docked "Describe a new task…" bar replaces the + button and the per-host manual menu. |
| 2 Task | Three big actions (Run now, Pause, Edit with chat) instead of one ⋯ menu. Schedule card with next dates. Run strip + run rows. Instructions and details after the runs. |
| 3 Run result | A pushed page, not a sheet. Result text first, then facts, then Open session in iTerm. Up/down steps through runs. |
| 4 Edit task | A pushed page with Cancel/Save, not a 650×720 modal. "Edit with chat instead" at the top. Host shown as fixed. |
| 5 Schedule | Its own page: Once / Days / Every / Cron, toggleable day chips, a live sentence and next run dates. |
| 6 New task | Prompt-first; "Set up manually" links to the edit page. |
| 7 Sessions | Questions are answered inside the list; the answered row moves to Working. |

Decision this resolves: keep the switcher (open decision 1 above is reversed for the narrow case).

## Round 3 — adopt mobile A2, cut scope (current)

Eugene: no answering in place, no session creation on desktop, and reuse the mobile A2 task flow
(LFG UI Map canvas, page "Tasks redesign (Oct 15)", boards `tA2-*`). Row 3 was rebuilt; the run,
schedule and new-task pages were removed (A2 folds them into the timeline and the form).

| Page | A2 pattern | Desktop change |
| --- | --- | --- |
| 1 Tasks | Needs input / Active / Closed, time column, result line, Retry/Answer pill | Switcher replaces tab bar; "Answer" becomes "Open ↗" (iTerm); + in title bar |
| 2 Task view | Chips, next-run card (Run now / Pause), instructions clamp, runs timeline, "Ask to change…" bar | Timeline rows open the session in iTerm (↗) |
| 3 Edit in form | Sentence first, frequency chips, day toggles, Ends, next runs, Runs on | Same |
| 4 Change with chat | Change card with Apply/Discard, Undo, suggestion chips | Sheet under the title bar |
| 5 Failed | Failed card, "2nd in a row", Retry now / Ask to fix, schedule still on | Open session link because a session started |
| 6 Needs input | Question + options answered in place | Question only + "Answer in iTerm" |
| 7 Sessions | A2 row shape | Open ↗ / Resume pills; no new-session button |

Also removed from the wide Sessions page: New session button, in-place answer options.

Server work A2 already lists (still true for desktop): change proposed before save (chat returns a
patch), a task-scoped edit chat that stays out of Sessions, "Ends after N / on date" for weekday/cron
schedules, consecutive-failure count from `recentRuns`.

Round 3 follow-up: on desktop, "Ask to change this task…" is a **Change with chat button** that opens a
Claude Code session in iTerm with the task's settings (today's Edit with chat). Page 4 (in-app change card)
was removed, so A2's server needs for a proposed-change patch and a task-scoped chat do not apply to desktop.

Round 3 follow-ups: no buttons on any list row (tasks or sessions); desktop Sessions uses "Needs input" to match Tasks and the S1 sessions redesign. All desktop designs moved into the LFG UI Map canvas.
