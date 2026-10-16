# Feature: Tasks A2 redesign (mobile first, then desktop)

Design: canvas "LFG UI Map", page **Tasks redesign** → row **A2 dark** (`tA2d-*`), and page **A2 build plan** (annotated copies of the same six screens). Desktop design: row **Desktop · A2** (`dA2-*`), matched to the mobile screens on 2026-10-15, with its own build-plan boards (`plan-desk-*`) on the A2 build plan page.

Status: **shipped to the servers and TestFlight** (2026-10-15). Commits `371f82d` (code) and `58f9f3d` (docs); `lfg serve` restarted on the Pro and the Air; TestFlight build 202610151935 (1.3.0, VALID, in beta testing). Follow-up 2026-10-16 (runs fold, logos, host move): commits `887e00d` and `30688b2`, both servers restarted, TestFlight build 202610161149 (1.3.0, VALID, in beta testing), Mac app installed on the Pro and the Air. Every phone and Mac screen passed `claude-design-verifier` against its board. Progress is in the Implementation log at the end; summary page: `.claude/tasks-a2/summary-page.md`.

## User Story

As Eugene, I want the Tasks tab to tell me at a glance which tasks need me, what runs next, and whether the last run worked, and I want to change a task by form or by chat without leaving it, so that scheduled agents feel like something I supervise, not something I dig for.

## User Flow

1. Open Tasks. Sections: **Needs input · Active · Paused · Closed**. Each row shows when it runs next (or when it ended), the schedule, and the last result. The Tasks tab shows a badge with the Needs input count.
2. Tap a task. The top card says the state: next run (Run now / Pause), failed (Retry now / Ask to fix), waiting for an answer (answer in place), paused (Resume), running, or closed. Below: instructions and a timeline of upcoming and past runs.
3. Tap **Edit**. The form has two schedule modes: **Once** (a date and time) and **Repeat** (quick picks such as every 5 minutes, hourly, every 3 days, weekdays; Custom for a raw cron expression; Ends: never, after N runs, or on a date). It shows the schedule as a sentence and previews the run times. Save.
4. Or tap **Ask to change this task…**. A chat sheet opens over the task. When the agent saves a change, a card shows each changed field, old → new, and the new next run.
5. Desktop (phase 6): the same list, task view and form in the narrow Mac window. A run's question shows with one "Answer in iTerm" button, and "Change with chat" is a button that opens the edit chat in iTerm. No answering in place, no Ask bar, no change card on the Mac.

## Annotated design → components

Numbers match the pins on the **A2 build plan** canvas page.
Tags: **FE new** = new view or model · **FE reuse** = existing code, used as is · **FE change** = existing frontend code that gets edited or replaced · **BE exists** = no server change · **BE new/change** = server work. The full list of FE changes is under "Existing frontend code that changes".

### List (`tA2d-list`)

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | Host header "Connected · 1 running" | reuse `HostConnectionHeader` (iOS), `DesktopConnectionStatusBar` (Mac) | exists |
| 2 | Search + host filter | reuse bottom search; FE new host filter menu (client-side filter) | exists |
| 3 | Sections Needs input · Active · Paused · Closed, counts, collapse | FE new `TaskListSection` + `TaskListGrouping` (LFGCore, pure); FE new `TaskSectionHeader` (shared; the iOS session header is private and iOS-only) | exists: `currentRun.status`, `lastRun.status`, `enabled`, `cancelledAt`, `nextRunAt` |
| 4 | Time column: next run, "Now", end date. **Paused rows show their next scheduled run in gray** (when it would fire if resumed); **blank when there is none** | FE new `TaskRowModel.time` | exists `nextRunAt`, `lastRun.finishedAt`; **BE new `upcomingRuns`, computed for paused tasks too** |
| 5 | Title + schedule sentence + host | FE new `TaskRowView`; reuse `ScheduledTaskSchedule.description` | exists |
| 6 | Result line with glyph (✓ summary, ✕ error, question, running) | FE new `TaskRowModel.result` | exists `lastRun.summary/error`; **BE new `currentRun.prompt`** (question text) |
| 7 | Paused section. The third line says "Paused by you · <date>" | `TaskListGrouping` rule: `!enabled && canResume && !cancelled` | **BE new `pausedAt`** |
| 8 | Tasks tab badge = Needs input count | FE new badge on `dockTab` (RootView has no badge support) | none |
| 9 | + new task | reuse `beginTaskCreation` → NewSessionView | exists |

### Task view (`tA2d-detail`)

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | Back, then one grouped glass pill with two icons: Edit (pencil) and ••• (Run now, Pause, Stop future runs). Same style as the list's search + ••• pill, per Apple's grouped toolbar items | FE change: one `ToolbarItemGroup(placement: .topBarTrailing)` holding the Edit button and the ••• `Menu`; iOS 26 draws them in a shared glass capsule. Reuse `ScheduledTasksModel.act` | exists: `POST /:id/run`, `POST /:id {enabled}`, `POST /:id/cancel` |
| 2 | Title | FE new `TaskDetailHeader` | exists |
| 3 | Schedule sentence | reuse `schedule.description` | exists |
| 4 | Chips: host, agent + model, folder | FE new `TaskPropertyChips` (shared; `AgentBadge` is iOS-only, so a small shared badge) | exists |
| 5 | Status card "Next run · Tomorrow 9:00 AM · in 22 h" | FE new `TaskStatusCardModel` (LFGCore) + `TaskStatusCard` view | exists `nextRunAt` |
| 6 | Run now / Pause (Resume) | reuse actions | exists |
| 7 | Instructions, Show more | reuse `TaskInstructions` | exists |
| 8 | "23 runs · 22 completed" | FE new | exists `runCount`; **BE new `succeededCount`** |
| 9 | Upcoming runs (hollow nodes) | FE new `RunTimelineView` | **BE new `upcomingRuns`** (next 3) |
| 10 | Past runs (status, summary, duration, open session) | FE new `RunTimelineRow`; reuse `taskSessionView` push (iOS) | exists `recentRuns` + `GET /:id/runs` paging |
| 11 | "Ask to change this task…" bar | FE new `TaskAskBar` → chat sheet (iOS) | see Chat |

### Task view: last run failed (`tA2d-detail-failed`)

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | "Last run failed" card, shown whenever the **latest** finished run failed or was interrupted and no run is active, even on a first failure. The "2nd in a row" label is added only when the streak is 2 or more | `TaskStatusCard(.failed)`; rule in `TaskStatusCardModel` | exists `lastRun.status`; **BE new `consecutiveFailures`** (label only) |
| 2 | Reason "Opus 5.5 was unavailable…" | FE new `RunErrorText` (maps raw errors to one plain sentence) | exists `lastRun.error` (raw exception text) |
| 3 | Retry now → "Retrying now · Open session" | reuse run now | exists `POST /:id/run` (409 if a run is active) |
| 4 | Ask to fix | opens chat sheet with "Why did the last run fail?" | see Chat |
| 5 | "Schedule still on. Next run: …" | `TaskStatusCard` footnote | exists `nextRunAt` |
| 6 | Red nodes in the timeline | reuse `RunTimelineRow` | exists |

### Task view: run needs input (`tA2d-detail-input`)

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | "Run is waiting for you · 12 min" | `TaskStatusCard(.needsInput)` | exists `currentRun.status == needs_input`; **BE new `currentRun.prompt.statedAt`** |
| 2 | Question + agent context | FE new `TaskPromptCard` (shared; `PromptPanelView` needs `SessionStore`, iOS-only) | **BE new: embed `journal.latestPrompt(run.sessionId)` as `currentRun.prompt`** `{question, context, options}` |
| 3 | Option buttons | FE new `ScheduledTasksClient.answer(sessionId, index)` | exists `POST /api/sessions/:id/answer {index}` |
| 4 | "Type a different answer…" | FE new `ScheduledTasksClient.send(sessionId, text)` | exists `POST /api/sessions/:id/send` |
| 5 | Open session | reuse `taskSessionView` (iOS), `Opener.open` (Mac) | exists |
| 6 | "One-time task. It moves to Closed when this run ends." | card footnote when `schedule.kind == once` | exists |

### Edit in form: two modes (`tA2d-edit-once`, `tA2d-edit` = Repeat)

A segmented control picks **Once** or **Repeat**. Repeat is one builder: when the gap fits the clock, it saves a `cron` schedule; when it does not (every 3 days, every 5 hours, every 45 minutes), it saves an exact-gap schedule (`repeat` with After N, else `interval`) that starts at the chosen time. The user never picks between cron and repeat. Example boards: weekdays (`tA2d-edit`), every 5 minutes, every hour, every 3 days.

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | Cancel / Save | reuse `ScheduledTaskDraft` validation + save; FE change: `ScheduledTaskEditor` When section rebuilt (SV:1002) | exists `POST /:id` |
| 2 | Name, instructions (compact rows) | reuse | exists |
| 3 | Mode: **Once · Repeat** | FE new `ScheduleModePicker` + `ScheduleDraft` (LFGCore) | exists: kinds `once`, `cron`, `repeat`, `interval` |
| 4 | Sentence, plus how it runs ("Runs at fixed clock times" or "Exact gap from Fri, Oct 16 at 9:00 AM") | `ScheduleDraft.sentence`; `ScheduleDraft` picks the kind | label from the preview endpoint |
| **Once** | | | |
| O1 | Calendar (past days disabled) and time | reuse `DatePicker(.graphical)` + `hourAndMinute` | exists `kind once`, `at` (must be in the future) |
| O2 | Date shortcuts (Tomorrow 9 AM, Monday 9 AM, Next Friday) | FE new chips | exists |
| O3 | "Runs once, then the task moves to Closed" | footnote | exists |
| **Repeat** | | | |
| R1 | Quick picks: Minutes · Hourly · Daily · Weekdays · Weekly · Monthly · Custom | FE new `RepeatPresetChips` | exists |
| R2 | Every N (minutes / hours / days): a **number field**, no − / + buttons | FE new `EveryNumberField`; FE change: replaces Repeat every + unit (SV:1173) | cron step, or `everyMinutes` |
| R3 | Weekday dots (Weekdays, Weekly) | FE new `WeekdayPicker` | cron day-of-week |
| R4 | Time / At minute; **Starts** (date + time) only for exact-gap schedules | reuse `DatePicker` | exists `at`; **BE change: `interval` starts at `at`** |
| R5 | **Custom**: one cron text field, shown only when Custom is picked. The other picks show no cron (Eugene, 2026-10-15) | FE new `CustomCronField`; FE change: replaces the five cron rows with * buttons (SV:1210) | validated by the preview endpoint |
| R6 | Ends: Never · After N · On date. After N shows a **Number of runs** field (typed only, no − / + buttons; 1–1000) and a "Last run: Thu, Oct 29 at 9:00 AM" line | FE new `EndsControl` + `RunCountField`; last run from the preview | exists `repeat.occurrences`; **BE change: cron `maxRuns`, `endsAt` for cron and interval** |
| R7 | Next runs | FE new `NextRunsPreview` (debounced) | **BE new `POST /api/scheduled-tasks/preview`** |
| 5 | Time zone · Change | reuse `TaskTimezonePicker` | exists |
| 6 | Runs on: host, folder, agent, model | reuse `TaskDirectoryPicker` + grouped model menu | exists |

Kind rules in `ScheduleDraft` (tested): minutes N divides 60, hours N divides 24, daily N = 1, weekdays, weekly, monthly, custom → `cron`. Anything else → exact gap: `repeat` when Ends = After N, otherwise `interval` (+ `endsAt` for On date). Existing tasks of any kind open in the right mode and pick.

**Every variant, one board:** `plan-edit-variants` on the A2 build plan page shows each variant below as a live phone with what it saves. Mobile boards are `tA2d-edit-*`; the desktop has the same set as `dA2-edit-*`. Each row is one `ScheduleDraftTests` case.

| Variant | Board | Saves (`TaskSchedule`) | Needs |
|---|---|---|---|
| Every 5 minutes | `tA2d-edit-cron-5min` | `cron "*/5 * * * *"` | — |
| Every 7 minutes | `tA2d-edit-7min` | `interval everyMinutes 7, at` | BE3 interval starts at `at` |
| Every hour | `tA2d-edit-cron-hourly` | `cron "0 * * * *"` | — |
| Every 5 hours | `tA2d-edit-5hours` | `interval everyMinutes 300, at` | BE3 |
| Every day at 9:00 | `tA2d-edit-daily` | `cron "0 9 * * *"` | — |
| Every 3 days | `tA2d-edit-cron-3days` | `interval everyMinutes 4320, at` | BE3 |
| Weekdays | `tA2d-edit` | `cron "0 9 * * 1-5"` | — |
| Weekly, Mon Wed Fri | `tA2d-edit-weekly` | `cron "0 9 * * 1,3,5"` | — |
| Monthly, the 1st | `tA2d-edit-monthly` | `cron "0 9 1 * *"` | — |
| Custom (also any cron no preset matches) | `tA2d-edit-custom` | `cron "30 8 1,15 * *"` | BE2 label + validation |
| Ends after 10, clock times | `tA2d-edit-after-n` | `cron "0 9 * * 1-5"` + `maxRuns 10` | BE3 cron maxRuns |
| Ends after 5, exact gap | `tA2d-edit-3days-after` | `repeat everyMinutes 4320, at, occurrences 5` | exists today |
| Ends on a date | `tA2d-edit-on-date` | `cron "0 9 * * 1-5"` + `endsAt 2026-12-31` | BE3 endsAt |
| Once | `tA2d-edit-once` | `once at` | — |

### Edit with chat (`tA2d-chat`)

The agent saves changes directly, as it does today. There is no Apply and no Undo (Eugene, 2026-10-15).

| # | Design element | Frontend | Backend |
|---|---|---|---|
| 1 | Sheet over the task: "Change task · <name>" | FE new `TaskChatSheet` (iOS only; transcript views are iOS-only). FE change: `startEditingChat` no longer pushes a session; `SessionStore` hides task-edit chats | **BE change: one edit chat per task.** Store `editSessionId` on the task; tag the session `purpose: "task-edit", taskId` (same pattern as `parentSessionId`) |
| 2 | "The agent saves changes as soon as it makes them" | copy | exists: `update_scheduled_task` writes directly, unchanged |
| 3 | User bubble, agent reply | reuse `TranscriptMessageView` + `MessageComposer` (the child-session sheet already does this) | exists `GET /api/sessions/:id/messages`, `POST /:id/send` |
| 4 | "Saved · 3 changes" card: field, old → new | FE new `TaskChangeCard` + `TaskChangeDiff(before, after)` (LFGCore). The sheet keeps the task as it was when it opened; when a refetch shows a newer `updatedAt`, it diffs the two and inserts the card into the thread | exists `GET /api/scheduled-tasks`. **No new server code** |
| 5 | "Next run: Fri 8:00 AM" | reuse schedule sentence + `upcomingRuns` | `upcomingRuns` (BE1) |
| 6 | Composer (no suggestion chips) | reuse `MessageComposer` | exists |

### Desktop (`dA2-*`, phase 6)

The Mac app compiles the shared task views, so each mobile component above is reused as is. Boards: list, task view, failed, needs input, and the edit form in the same six variants as the phone. Plan boards: `plan-desk-summary`, `plan-desk-detail`, `plan-desk-input`, `plan-desk-edit`.

| Screen | Same as the phone | Mac difference |
|---|---|---|
| List | Four groups, no row buttons, paused rows show the next run or nothing | Sessions / Tasks switcher instead of the tab bar; + in the title bar; host strip |
| Task view | Edit + ••• pill, status card, runs timeline | A past run opens its session in iTerm; a Change with chat button replaces the Ask bar |
| Last run failed | Card on any failed latest run; "2nd in a row" from the second | Ask to fix and Open session open iTerm |
| Run needs input | The card shows the run's question and context | No options in the app: one "Answer in iTerm" button opens the run's session |
| Edit in form | Once · Repeat, every control and kind rule, Next runs | Cancel / Save in the title bar, inline Instructions, Agent and Model rows, `.field` date pickers |
| Change with chat | The agent saves directly | A button that opens the edit chat in iTerm (today's Edit with chat, moved to the task view). No Ask bar, no change card |

Backend: nothing Mac-only. The desktop uses BE1–BE4; the answer and send routes stay phone-only.

## Backend work (all in `src/`)

**BE1. Richer list response** (`GET /api/scheduled-tasks`, `scheduled-task-api.ts:83-95`)
- `upcomingRuns: number[]` (next 3). New `nextOccurrences(schedule, after, n)` in `scheduled-tasks.ts`: croner `nextRuns(n)` for cron; arithmetic for interval and repeat; one item for once (none if its time has passed). Computed from the schedule **even while the task is paused**, because paused rows show their next scheduled run; empty means the row's time column stays blank.
- `consecutiveFailures`: count `failed`/`interrupted` runs from the newest until another status appears.
- `succeededCount`.
- `pausedAt` on the task: set when `enabled` goes false, cleared on resume.
- `currentRun.prompt = {question, context, options, statedAt}` when the run is `needs_input` (from `journal.latestPrompt`).

**BE2. Schedule preview**: `POST /api/scheduled-tasks/preview {schedule}` → `{label?, nextRuns: number[5], error?}`. Runs the same validation as save. One schedule engine for the form, the chat card and the timeline.

**BE3. Schedule fixes for the Repeat builder**: `schedule.endsAt` (ISO) for cron and interval; `schedule.maxRuns` for cron (croner `maxRuns`/`stopAt`). Count only scheduled runs, like `repeat` does. A task that reaches its end moves to Closed (`nextRunAt = null`, `enabled = false`). `interval` (an exact gap with no run limit) starts at `at` instead of counting from the save.

**How much work is the change card?** Very little, because the agent saves directly (no Apply, no Undo).
- The sheet remembers the task as it was when it opened. While the sheet is open it refetches the task; when `updatedAt` changes, `TaskChangeDiff(before, after)` lists each changed field, and the card shows them. Then "before" moves forward to the new task, so the next change gets its own card.
- No server code for the card, no pending record, and no change to the agent's tools or prompt.
- Cost of adding an Apply step later, for comparison: a propose tool, a pending record, apply and discard routes, telling the agent the outcome, and the agent waiting on a tap. About 150 lines of server code plus a less direct chat.

**BE4. Task-edit chat session**: `/:id/chat` reuses `task.editSessionId` when that session is alive, else starts one tagged `purpose: "task-edit", taskId`. Session rows carry the tag, so clients drop these sessions from the Sessions list.

**Exists, reused as is**: run now, pause/resume, cancel, runs paging, session answer/send/messages, edit-chat start, `update_scheduled_task`.

**Known risk, out of scope**: runs are never pruned, so `scheduled-tasks.json` grows forever.

## Frontend structure

- `shared/ScheduledTasksView.swift` is about 1,430 lines. Phase 0 splits it into `shared/Tasks/*.swift` with no change in behavior, so both apps reuse the pieces.
- New pure logic goes in a new `ios/LFGCore/Sources/LFGCore/TaskPresentation.swift`: grouping, row model, status card model, timeline model, `ScheduleDraft`, `TaskChangeDiff`. Swift tests cover all of it.
- The Mac app compiles only listed files (`desktop/build.sh:20-30`). Add `shared/Tasks/*` and `TaskPresentation.swift` there and in `ios/project.yml`.
- iOS-only: `TaskChatSheet`, the dock badge, session push.
- Mac-only: iTerm opening, the narrow-window toolbar (already in progress in `LFGSessions.swift`), the Change with chat button, and the question card without options.
- Colors: system colors and `Theme` tokens. Light and dark both work; dark is the reference.

### Existing frontend code that changes

SV = `shared/ScheduledTasksView.swift`, ST = `ios/LFGCore/Sources/LFGCore/ScheduledTasks.swift`. Line numbers are from 2026-10-15 and will move after the phase 0 split.

| Phase | File (location) | Change |
|---|---|---|
| 0 | SV (whole file) | Split into `shared/Tasks/*.swift`. Pure move, no change in behavior |
| 0 | `desktop/build.sh:20-30`, `ios/project.yml:33` | Compile the new shared files and `TaskPresentation.swift` |
| 1 | ST `ScheduledTaskRecord` (:243), `ScheduledTaskRun` (:218) | Decode `upcomingRuns`, `consecutiveFailures`, `succeededCount`, `pausedAt`, `currentRun.prompt` |
| 1 | ST `ScheduledTasksClient` (:467) | Add `preview`, `answer`, `send` |
| 1 | ST `listGroup` / `ScheduledTaskGroup` (:287, :299) | Replaced by `TaskListSection` (4 sections instead of Pending / Completed) |
| 2 | SV `ScheduledTasksView` list body (:448 groups, :519 `groupHeader`, :505 `taskRow`) | Four sections with `TaskSectionHeader`; rows become `TaskRowView` |
| 2 | SV `TaskListSummary` (:619) | Replaced by `TaskRowView` |
| 2 | `ios/LFG/RootView.swift` `listDock` / `dockTab` (:241-295) | Tab badge for the Needs input count |
| 3 | SV `ScheduledTaskDetail` (:676) | Rewritten: header, chips, status card, timeline, Ask bar. The ••• menu stays |
| 3 | SV run list in the detail (:725-748, `ScheduledSessionRow` :561) | Replaced by `RunTimelineView`. `ScheduledRunDetail` (:840) stays for the long-press "Run details" |
| 4 | SV `ScheduledTaskEditor` (:1002) | When section rebuilt from presets: kind picker (:1105), repeat fields (:1173) and the five cron fields (:1210) go away. Custom keeps one cron text field. The "Edit with chat" button (:1084) moves to the task view |
| 4 | ST `ScheduledTaskDraft` (:365) | Reads and writes the schedule through `ScheduleDraft` |
| 5 | ST `startEditingChat` (:496); SV sheet dismiss (:152-160) | The edit chat opens in `TaskChatSheet`, no longer as a pushed session |
| 5 | `ios/LFG/SessionStore.swift` grouping | Drop sessions tagged `purpose: task-edit` from the Sessions list |
| 6 | `desktop/ScheduledTasksPane.swift`, `desktop/LFGSessions.swift` switcher | Use the shared views; switcher shows the Tasks Needs input count |
| 6 | `desktop/build.sh:20-30` | Add `shared/Tasks/*.swift` and the new LFGCore files |
| 6 | Shared views, `#if os(macOS)` | Cancel / Save in the title bar, `.field` date pickers, numeric `TextField` formatter, 400pt layout |
| 6 | Change with chat button (today's "Edit with chat", SV:1084, moves to the task view) | `startEditingChat`, then `openSession(editSessionId)` in iTerm |
| 6 | Question card, `#if os(macOS)` | Hide the options and free-text row; show "Answer in iTerm" |

Two pieces are deliberately **not** changed: `PromptPanelView` (it needs `SessionStore`, so the task view gets its own small card) and `NewSessionView` task creation (the + button keeps today's flow).

## Success Criteria

- [x] SC1: The list shows four sections in this order: Needs input · Active · Paused · Closed. Each task appears once, and Closed starts collapsed. — **Verify by:** `TaskListGroupingTests` (one case per rule) + FlowDeck screenshot on iPhone 17 Pro against a fixture host.
- [x] SC2: Row time column and result line match the rules (next run, Now, end date; paused rows show their next scheduled run in gray, or nothing when there is none; ✓/✕/question/running/paused-by-you). — **Verify by:** `TaskRowModelTests` + screenshot.
- [ ] SC3: The Tasks tab badge equals the Needs input count, and it hides at 0. — **Verify by:** unit test on the count + screenshot with 2 and 0.
- [x] SC4: The list API returns `upcomingRuns`, `consecutiveFailures`, `succeededCount`, `pausedAt`, and `currentRun.prompt` for a needs-input run. — **Verify by:** `bun test src/scheduled-task-api.test.ts` cases + a `curl` against a scratch server on a spare port.
- [x] SC5: The task view shows the right status card for each state: next run, running, paused, failed, needs input, closed. Failed shows on any failed or interrupted latest run, including a first failure; the streak label appears only at 2+. — **Verify by:** `TaskStatusCardModelTests` + 6 screenshots from fixture tasks.
- [x] SC6: Answering a needs-input run from the task view reaches the session. The answer appears in the transcript, and the task leaves Needs input. — **Verify by:** live run on a fixture task whose prompt asks a question; tap an option in the simulator; check `/api/sessions/:id/messages` + list API.
- [x] SC7: Retry now starts a run, and the card shows "Retrying now". — **Verify by:** simulator tap + list API shows `currentRun`.
- [x] SC8: The form round-trips both modes. Once: date + time. Repeat: every quick pick (every N minutes/hours/days, weekdays, weekly days, monthly, custom cron) with Ends Never / After N / On date. Clock-aligned picks save as cron; every 3 days, every 5 hours and every 45 minutes save as an exact gap that starts at the chosen time. Existing tasks of every kind open in the right mode. — **Verify by:** `ScheduleDraftTests` (draft → schedule → draft, one case per rule) + `bun test` for BE3 (cron Ends, interval start).
- [x] SC9: The next-runs preview matches what the scheduler does. — **Verify by:** `bun test`: preview output equals `nextOccurrences`, and equals real `claim` times for cron, interval and repeat in a fake clock.
- [x] SC10: When the agent saves a change from the chat sheet, a card shows each changed field (old → new) and the new next run, without leaving the sheet. — **Verify by:** `TaskChangeDiffTests` + a live chat on a scratch task in the simulator.
- [x] SC11: After closing the chat sheet, the task view already shows the saved change (no stale card or schedule). — **Verify by:** simulator: change the schedule by chat, close the sheet, check the status card and sentence.
- [x] SC12: Edit-chat sessions do not appear in the Sessions list. — **Verify by:** list API row carries `purpose`; simulator screenshot of Sessions before/after opening a chat.
- [ ] SC13: Desktop shows the same list, task view (every card state) and form (Once and every Repeat pick) in a 400pt window, and opens sessions and the edit chat in iTerm. — **Verify by:** `lfg --window-shot` for each screen + `lfg --open-session` for a run row.
- [ ] SC15: On the desktop, a needs-input run shows its question with only an "Answer in iTerm" button, and Change with chat opens the task's edit chat in iTerm. — **Verify by:** `--window-shot` of the needs-input view + `lfg --open-session <editSessionId>` and a `tmux list-clients` check.
- [x] SC14: Both apps build from a clean worktree at HEAD (see memory: main can be broken while every build is green). — **Verify by:** clean worktree, then FlowDeck iOS build and `desktop/build.sh`.

## Platform & Stack

- **Platform:** iOS (first), macOS desktop (phase 6), Bun server
- **Language:** Swift (SwiftUI, Swift Testing), TypeScript
- **Key frameworks:** SwiftUI, LFGCore package, croner, bun test, FlowDeck for simulator checks

## Steps to Verify

1. `bun test src/scheduled-*.test.ts`
2. `cd ios/LFGCore && swift test`
3. Start a scratch server on a spare port (never 8766) with a fixture `scheduled-tasks.json` that covers every state.
4. FlowDeck: build and run on iPhone 17 Pro, point the app at the scratch host, and walk list → task view (each state) → Edit → chat.
5. Desktop: `desktop/build.sh`, `lfg --window-shot 400 <png>` per screen.

## Implementation Phases

### Phase 0: Prepare (no behavior change)
- Scope: land or hand off the in-flight **finite repeat** work (it sits uncommitted in `ScheduledTasksView.swift`, `ScheduledTasks.swift`, `src/scheduled-*.ts`). Then split `ScheduledTasksView.swift` into `shared/Tasks/*` and add the files to `desktop/build.sh` and `ios/project.yml`.
- Covers: SC14 (baseline)
- Gate: both apps build; existing Swift and bun tests pass; screens look unchanged.

### Phase 1: Data
- Scope: BE1, BE2; `TaskPresentation.swift` (grouping, row model, status card model, timeline, `ScheduleDraft`); `ScheduledTasksClient` gains `preview`, `answer`, `send`.
- Covers: SC4, SC9, plus unit parts of SC1, SC2, SC5, SC8
- Gate: all new bun and Swift tests green.

### Phase 2: Mobile list
- Scope: sections, `TaskSectionHeader`, `TaskRowView`, host filter, dock badge.
- Covers: SC1, SC2, SC3
- Gate: tests + FlowDeck screenshots (dark and light).

### Phase 3: Mobile task view
- Scope: header, chips, `TaskStatusCard` (all states), answering in place, Retry, timeline, Ask bar (opens a placeholder until phase 5).
- Covers: SC5, SC6, SC7
- Gate: tests + live answer on a fixture run + screenshots.

### Phase 4: Mobile form
- Scope: BE3; `ScheduleModePicker` (Once · Repeat), the Once body, and the Repeat builder (`RepeatPresetChips`, `EveryNumberField`, `WeekdayPicker`, `CustomCronField`, `EndsControl` + `RunCountField`, `NextRunsPreview`); replaces today's kind picker, repeat fields and five cron rows.
- Covers: SC8, SC9
- Gate: round-trip tests + scheduler tests + screenshots.

### Phase 5: Edit with chat
- Scope: BE4 (task-edit chat session); `TaskChatSheet`, `TaskChangeCard`, `TaskChangeDiff`.
- Covers: SC10, SC11, SC12
- Gate: Swift tests + one live chat on a scratch task.

### Phase 6: Desktop
- Scope: use the shared list, task view and form in `ScheduledTasksPane`. Desktop chrome follows the `dA2-*` boards: switcher, + in the title bar, sessions and the edit chat in iTerm. Mac-only work: build list, `#if os(macOS)` styling, the Change with chat button, the question card without options. No backend work of its own.
- Covers: SC13, SC14, SC15
- Gate: window shots + iTerm open check + clean-worktree builds of both apps.

## Decision Log

- **One schedule engine on the server.** Upcoming runs and the form preview come from the server (BE1, BE2), not from Swift. Swift only formats. The alternative, a second cron engine in Swift, could disagree with the scheduler.
- **Retry = Run now.** There is no separate retry route. `POST /:id/run` already refuses when a run is active.
- **Answering in place reuses the session answer route.** The prompt is embedded in the task list response, so the task view needs no session fetch. `PromptPanelView` cannot be reused: it needs `SessionStore` and is iOS-only.
- **Chat edits save directly; no Apply, no Undo** (Eugene, 2026-10-15). The card is computed by the app from the task before and after. An Apply step would add a propose tool, a pending record and a waiting agent.
- **Edit chats are hidden from Sessions**, with one per task, reused.
- **Two form modes: Once and Repeat** (Eugene, 2026-10-15). Repeat is cron plus an Ends counter. When a gap does not fit the clock (every 3 days, every 5 hours), the form saves an exact-gap schedule instead, so nothing is lost and the user never chooses between cron and repeat.
- **Chat has no suggestion chips** (Eugene, 2026-10-15).
- **Paused tasks get their own section** (Eugene, 2026-10-15). Paused = switched off but can resume; Closed = no runs left.
- **List rows have no buttons** (Eugene, 2026-10-15). Actions live in the task view.
- **No mic button in the chat composer** (2026-10-15). The chat board draws one, but iOS has no API to start keyboard dictation from a custom button; a button would mean adding a speech-recognition feature. The keyboard's own dictation key already covers voice input. Recorded as a deliberate difference from the board.
- **Desktop list toolbar follows the dA2 board in the 360–499pt band** (2026-10-15). A badged Sessions | Tasks switcher (native segments cannot carry badges), and search and + as their own buttons. Manual setup moves onto the + button's menu, and the host filter moves into a host strip under the toolbar. Below 360pt and at 500pt and up, the verified fold behavior from the narrow-window work is unchanged. `--window-fit` 180–1200pt: no item dropped, Sessions and Tasks. The alternative was keeping "•••" at 400pt, which the board does not have.
- **Desktop matches the mobile screens except where iTerm does the work** (Eugene, 2026-10-15). Same list, pill, status cards and form. A run's question shows with one "Answer in iTerm" button; Change with chat is a button that opens the edit chat in iTerm. No answering in place, no Ask bar, no change card on the Mac (memory `desktop-client-scope`).
- **Runs fold to three rows per group, style B** (Eugene, 2026-10-15, after three options on the canvas row "Runs: Show more, and the model logos"). Upcoming runs sit on top, furthest first, with no "Next" label. Past three rows, a group shows its two nearest runs and a toggle row on the timeline: a disc with a chevron, "Show more" and the hidden count ("8 later", "21 earlier"); the rail turns dashed where runs are hidden. Upcoming opens all at once (the host now lists up to 10); past opens 10 per tap and fetches the next page when needed. Rules live in `RunGroupFold` (LFGCore, tested).
- **The model chip shows the agent's real logo** (Eugene, 2026-10-15): the app's own `agent-claude` / `agent-codex` SVGs. The Mac bundle gets them from `desktop/build.sh`; AppKit draws SVG natively.
- **The Every field hugs the right edge** (Eugene, 2026-10-15): the unit no longer reserves 64pt, so the field moves with the word ("1 day", "5 minutes"). The edit boards still draw the old fixed width.
- **Host is a dropdown, and changing it moves the task** (Eugene asked for the dropdown, 2026-10-15; the move is my call). Saving creates the task on the new host first, then stops the original, which keeps its past runs under Closed. A create failure (folder missing on that host) leaves the original untouched; a failed stop reports that both are on. Cron "after N runs" carries over the runs left when the schedule is unchanged. The open task page follows the task to its new id. No board draws the dropdown yet.

## Open questions for Eugene

1. **In-flight finite-repeat work** (uncommitted, same files): should I commit it as is before phase 0, or is another session finishing it?
2. **Ends for Daily/Weekly (BE3)**: build it in phase 4 (my recommendation; croner supports it), or ship the form with Ends only for Every few hours and Once?
3. ~~Desktop answering in place~~ Resolved 2026-10-15: no. The desktop shows the question and opens the session in iTerm.

## Verification Evidence

All independent checks used `claude-design-verifier` against the boards rendered locally. Reports are in `.claude/tasks-a2/evidence/`.

| Criterion | Evidence |
|---|---|
| SC1, SC2 | List PASS in round 4 (`verifier-list-and-view/evidence-r4.md`); `TaskPresentationTests` |
| SC3 | Badge equals the Needs input count across hosts (verifier rounds 1–4). **Hiding at 0 was not exercised**: the stand-in host always has a waiting run. The view draws the badge only when the count is above 0. |
| SC4, SC9 | `bun test src/scheduled…` 110 pass, including `scheduled-a2.test.ts` (preview matches `nextOccurrences`) |
| SC5 | Task view PASS in round 4, all six states |
| SC6, SC7 | Live: answer option 1 → `POST /api/sessions/fx-question/answer {"index":1}` and the card reads "Running again"; Retry now → `POST …/run` and the card reads "Retrying now" |
| SC8 | `ScheduleDraftTests`: 16 round-trip cases, including `0 8 * * 2-5`; form PASS in round 4 on all 14 variants (`verifier-form/evidence-form-r4.md`) |
| SC10, SC11 | Chat PASS in round 4 (`verifier-chat/evidence-r4.md`); the card shows each change and the next run; after Close the task view shows the new schedule. Ask to fix verified live. |
| SC12 | Live: the host lists the chat with `purpose: "task-edit"`; the phone's Sessions list omits it and keeps the host's other sessions. Mac: desktop check. Closed edit chats now keep the tag too (see Bugs; unit-tested, live after deploy). |
| SC13 | Desktop screens PASS in round 7 (`verifier-desktop/evidence-r7.md`). **Not verified live:** opening iTerm needs a host running the new server. |
| SC15 | The "Answer in iTerm" view is verified. The iTerm open itself is not verified, for the same reason as SC13. |
| SC14 | Clean worktree at `58f9f3d`: iOS build succeeded; desktop build and 183 checks pass; bun 1201 pass (3 fail, same at the previous HEAD); LFGCore 969 pass. |
| Runs fold (B) | `RunGroupFold` tests; live on the phone (`edits-1015/04`–`07`: folded, upcoming opened, past opened once with "11 earlier") and the Mac (`mac-01`). Verifier round 1 FAIL (`verifier-runs/evidence.md`): geometry within 0.33pt, but the task page used system greys instead of the board's (#A1A1A6 phone, #8A8A93/#C9CBD3/#F4F4F6 Mac), a brighter rail, a near-solid board dash drawn with gaps, the last toggle under the Ask bar's fade, Mac 12pt nodes in a 16pt rail (board 11 in 14), Mac chip fill. Fixed with board tokens (`TaskColors.grey/soft/rail/upcomingNode`, `TaskPalette.chip`, phone danger #FF453A) applied through `TaskTone`, so list and form text move to the board values too. Round 2 FAIL on one 2pt Mac toggle offset that came from a CSS quirk in my own board (a 16px disc stretched the 14px column); the board was corrected on the canvas. Also fixed: the phone's bottom fade now covers the strip under the Ask bar, and the Mac instructions colour, card label grey and 18pt page inset match. **Round 3 PASS** (`evidence-r3.md`). Not counted, unchanged since round 7: Mac status card title (225 vs 244) and subtitle grey, card 2pt lower, instructions Show more 3pt tighter. |
| Model logos | Live: Claude starburst on phone and Mac, Codex icon on the Mac (`mac-02-codex-chips.png`); verifier as above |
| Host move | `ScheduledTaskMoveTests` (create then stop, failed create, failed stop, runs left); live: "V long history" moved Pro → Air on the stand-in hosts, the page followed it, the original closed with its 23 runs (`edits-1015/09`–`12`) |
| Every field | Live on the phone (`08`) and the Mac (`mac-03`, captured on screen) |

## Bugs

- **Fixed: a closed edit chat reappeared in the Sessions closed list.** The `task-edit` tag lived only on the managed-session record, which is deleted when the session ends.
  - Server: the task store now keeps each task's last 20 edit-chat ids (`editSessionIds`), and `/api/sessions/resumable` and `/api/sessions/search` tag matching rows with `tagEditChats`. `sessions.ts` is untouched.
  - Clients: phone `ResumableSession.purpose` and Mac `ResumableAPISession.purpose` carry the tag into closed sessions, where the existing Sessions filters drop it.
  - Tests: bun (history and tagging), Swift decode plus cache round trip, one desktop check (183 pass). The `serve.ts` wiring is two lines and is not live-tested: that needs the real server, and a second `lfg serve` would send real pushes.
- Fixed during verification: an existing `repeat` every 1 day opened as Daily (would have converted it to cron on Save); `0 8 * * 2-5` opened as Custom instead of Weekly Tue–Fri; the chat's Saved card landed above the agent's reply; a duplicate "no session started" in failed timeline rows.

## Implementation log

Visual checks compare a simulator screenshot with the board rendered locally (`.claude/tasks-a2/design/`, served on port 8931). Test data comes from `.claude/tasks-a2/fixture-host.ts`: the real task routes over a seeded store, never launching agents. The session simulator also loads the bundled real hosts, so real tasks appear beside the test ones.

### Phase 1: Data — done 2026-10-15
- Server: `upcomingRuns`, `consecutiveFailures`, `succeededCount`, `pausedAt`, `needsInputAt`, `currentRun.prompt` on the list; `POST /api/scheduled-tasks/preview`; cron `maxRuns` and `endsAt`, interval `endsAt` and `at` (exact gap from a start); `scheduledRunCount`. Task tools and chat prompts know the new fields.
- LFGCore: new fields decoded (old hosts still decode); `TaskPresentation.swift` (sections, ordering, row text, time formats); `ScheduledTaskPrompt` (the Mac app does not compile `Models.swift`).
- Evidence: `bun test src/scheduled src/mcp` 84 pass (10 new in `src/scheduled-a2.test.ts`); `swift test` 290+ pass (16 new in `TaskPresentationTests`).

### Phase 2: Mobile list — done 2026-10-15
- `shared/Tasks/TaskListViews.swift` (row, section header, glyphs), list body in `ScheduledTasksView`, host filter in the ••• menu, Needs input badge on the Tasks tab (`RootView`). Both builds include `shared/Tasks/` (`ios/project.yml`, `desktop/build.sh`).
- Visual check: `.claude/tasks-a2/evidence/phase2-list/list-side-by-side.png` (board vs app), `app-list-closed-expanded.jpg`. Matches the board; differences are data wording only. Fixed during the check: row line heights (rows were 8pt short), past dates shown as weekdays.

### Phase 3: Mobile task view — done 2026-10-15
- LFGCore `TaskDetailPresentation.swift`: status card model (next, paused, running/retrying, waiting, failed, closed), runs timeline, count line; `ScheduledTasksClient.answer` / `send`. 9 tests in `TaskDetailPresentationTests`.
- `shared/Tasks/TaskDetailViews.swift`: header + chips, status card (answer in place on the phone; "Answer in iTerm" on the Mac), timeline, Ask bar. `ScheduledTaskDetail` rebuilt on it; Edit + ••• in one toolbar group. The Ask bar opens the existing edit chat session until phase 5.
- Live checks against the stand-in host: Retry now → `POST …/run`, card shows "Retrying now"; answering option 1 → `POST /api/sessions/fx-question/answer {"index":1}`, card shows "Running again"; Pause → paused card and "skipped while paused"; Resume; ••• menu; host filter.
- Visual check: `.claude/tasks-a2/evidence/phase3-detail/{detail,failed,input}-side-by-side.png`. Fixed during the check: upcoming runs were greyed (disabled buttons), failed view now lists one upcoming run as on the board, "Once · today at 9:58 AM" wording, compact running time in the list.

### Phase 4: Mobile form — done 2026-10-15
- LFGCore `ScheduleDraft.swift`: Once / Repeat picks, kind rule, Ends, sentence and "how it runs" line, problems that block Save, next-run chip text; `SchedulePreview` + `ScheduledTasksClient.preview`. `ScheduledTaskDraft.payload(schedule:)`, `save(_ payload:)`. 13 tests + 15 round-trip cases in `ScheduleDraftTests` (one per row of the variant table).
- `shared/Tasks/TaskEditorViews.swift`: When section (mode picker, presets, typed Every field, weekday dots, Starts, At/Time, Custom cron field, Ends, Number of runs, End date, Next runs from the host), instructions page. `ScheduledTaskEditor` now uses it; the old kind picker, cron rows and "Edit with chat" button are gone from the form. Inline title, blue Save.
- Server: preview accepts a past start for repeat/interval (an existing series), still rejects a past Once.
- Bug found by the live check and fixed: an existing `repeat` every 1 day opened as Daily, which saves as cron, so Save without changes would have turned it into cron with a fresh run count. `ScheduleDraft` now keeps a saved exact gap until the user picks something new (`keepsExactGap`), and keeps an older interval's missing start (`omitsStart`). Tests added.
- Live checks: every variant on "Daily repo review" (weekdays, once, 5 min, 7 min exact gap, hourly, 3 days, weekly Mon/Wed/Fri, monthly, custom, After N, On date); Save of "every 7 minutes, 10 times" stored `{kind: repeat, everyMinutes: 7, occurrences: 10, at: Fri 9:00}` on the host and the task view showed it.
- Visual check: `.claude/tasks-a2/evidence/phase4-form/` (one app shot per variant; side by side with the board for once, 3 days, After N). Fixed during the check: next-run chips overflowing the card, duplicate Time row on exact gaps, Save disabled for an existing series.
- Kept beyond the phone board: a Model row in Runs on (the board omits it; removing it would lose a working setting).

### Independent verification, round 1 (list + task view) — FAIL, fixed 2026-10-15
- `claude-design-verifier` against tA2d-list / -detail / -failed / -input (report: `.claude/tasks-a2/evidence/verifier-list-and-view/evidence.md`). 4 defects, 29 deltas.
- Fixed in LFGCore (tests added): board wording for schedules ("Weekdays at", "Fridays at", "Daily"), "· 5 runs" on finished finite tasks, paused line "on weekdays at", skipped row without a time, no duplicate "no session started", Retry on the newest failed run, no upcoming rows and no waiting row while a run is live.
- Fixed in views: "Show more" only when a whole line is hidden; 2-line, non-expandable instructions in the failed and waiting states; Runs section left out when the only run is the waiting one; header rows no longer inherit the 44pt row minimum; separators run to the edge; own row chevron (system one hidden); board color tokens (`TaskColors`, per platform); smaller card button glyphs; timeline line boxes; 22pt instruction pitch; answered line height; 130pt fade over the Ask bar; retry keeps the failure placeholder; dock icons, weight and badge color; footer removed from the list.
- Not changed, recorded as native: the failure reason wraps before "session" because iOS avoids a one-word last line. The top status bar is shared Sessions chrome, out of scope here.
- **Rounds 2–4 and final. List and task view: PASS in round 4, and again in the final regression (`evidence-final-2.md`) after the phone model chip began using `ModelName.display`.**
- Earlier detail: **Rounds 2–4. List and task view: PASS in round 4** (`evidence-r4.md`).
  - Round 2 overcorrected the colours: the lighter red and amber belong only to the failed and waiting card labels; everything else uses system red and orange.
  - Round 3: the task view keeps the sentence form ("Every weekday at…"); list rows use the short form ("Weekdays at…").
  - Round 4: the header chevron grey, the waiting dot, and the failed card's ✕ in system red.
  - Remaining minor items: the fixture's full error text; filled SF symbols where the board draws outlines.

### Phase 4 form: independent verification — in progress
- Round 1 FAIL, then round 2 PARTIAL. Fixed between them:
  - Chips: board formats and counts, shared with the Mac ("Fri 9:00", "Nov 1 · 9:00", "10:15"; 4 chips for clock-aligned minutes and day gaps, otherwise 3). Tests added.
  - Sentences: the custom one reads "At 8:30 AM on the 1st and 15th of every month"; weekly lists have no comma before "and". Tests added.
  - Layout: the When top block is one row with the board's gaps; the time zone line is inside the card; Once shortcuts wrap.
  - Colours: the board's blue on chips and Save.
  - Removed: the extra "Runs on" paragraph.
- After round 2: tighter row padding, Ends kept in one block with its sub-row, a bordered cron field, darker fields, a white monthly label, and a white Save label.
- Round 3 PARTIAL (spacing only), then the Form's row minimum went to 0 and the top block got exact insets.
- **Round 4: PASS** on all 14 variants (`verifier-form/evidence-form-r4.md`). The When card is 397pt (board 402); Host and Folder show on the first screen, as on the board.

### Phase 5: Edit with chat — implemented, verification running
- Live check on a second simulator against the variant host (8933):
  - Ask bar → sheet → "skip mondays and run at 8 instead. use codex for this one".
  - The scripted agent replies, and the card shows "Saved · 3 changes": Schedule "Every weekday at 9:00 AM → Tue–Fri at 8:00 AM", Agent, Model, and the next run.
  - The header updates to "Tue–Fri at 8:00 AM".
  - The change card wraps the new value onto its own line, as on the board.
- **Ask to fix** (live, main simulator, 8932 host): Ask to fix on the failed card opens the sheet and sends "Why did the last run fail? Fix the task if you can." on its own. The scripted agent switches the model, and the card shows "Model: Opus → Claude default" with "Next run: Fri, Oct 16 at 2:00 AM". Evidence: `.claude/tasks-a2/evidence/phase5-ask-to-fix.jpg`.
- **Edit chats hidden from Sessions** (live): the host lists the chat with `purpose: "task-edit"`. The phone's Sessions list shows the host's other sessions but not that one. The Mac filters the same way (desktop check).
- Model names on the change card read as people write them ("GPT-6 Astra"), via `ModelName.display` (tests added).
- `claude-design-verifier` against `tA2d-chat`: round 1 FAIL (surfaces, bubble, header glyphs, composer, two copy items); round 2 PARTIAL (thread spacing, which I had misread, plus the Send look and the star outline); round 3 FAIL (the Saved card landed above the reply, because the agent saves before it replies). **Round 4: PASS** (`verifier-chat/evidence-r4.md`). A 16 s recording shows the order bubble, reply, card in every frame, also after reopening. Not verifiable here: scrolling under the composer (one exchange does not scroll), and the keyboard-up layout (the simulator has no on-screen keyboard).

### Phase 6: Desktop — in progress 2026-10-15
- Edit is a pushed page on the Mac (`ScheduledTaskRoute.edit`), with Cancel, a centered title and Save. Task pages hide the Sessions/Tasks switcher and show their own Back (AppKit's never appeared for this stack); Back moves into ••• below 300pt.
- Mac task view bottom: "Change with chat" button + caption; opens the edit chat in iTerm, passing "Ask to fix" text as the first message.
- Mac edit form: cards on a scroll view (no grouped Form), board metrics (`TaskFormMetrics`), own segmented control, time/date pills with popovers, month calendar for Once, Agent row (Claude Code / Codex) and Model menu.
- Screenshot harness: `.claude/tasks-a2/mac_shot.sh` (signed scratch bundle; `--onscreen` uses screencapture because cacheDisplay draws glass toolbar items blank). Variant host: `FIXTURE_VARIANTS=1 PORT=8933` adds one task per edit variant. Evidence: `.claude/tasks-a2/evidence/phase6-desktop/`.
- **Independent verification: PASS in round 6** (`claude-design-verifier`, `.claude/tasks-a2/evidence/verifier-desktop/evidence-r6.md`). Covers the list with its toolbar, three task-view states, and all 14 edit variants. Rounds 1–5 fixed:
  - surfaces: page and card surfaces
  - colors: the edit form's accent, the Mac's own red, amber and green, and the timeline dot colours
  - the failed and waiting cards: tint, border and copy
  - "↗" where a run opens in iTerm
  - the edit form: chip text and counts, card rhythm, the monthly label, the cron field, and the calendar
  - the list: the host strip, row insets, and the badged switcher with search and + buttons
  Left as non-blocking: spacing differences under 6pt in four edit variants. Not reachable with this harness: the active-window toolbar colour, interactive states, and the "2nd in a row" and "Open session in iTerm" states.
- Edit chats are hidden from the Mac's Sessions list and menu bar (`SessionStore.visible`), but still open from their task (`liveItem`). New desktop check; 182 checks pass.
