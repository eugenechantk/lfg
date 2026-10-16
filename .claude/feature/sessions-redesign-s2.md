# Feature: Sessions redesign S2 (phone) + Desktop sessions list

Design: "LFG UI Map" canvas, page **Sessions redesign (Oct 15)** —
https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD

- Row **S2** (y=1300): the phone screens, files `s2-*`. This is the direction to build.
- Row **Desktop** (y=2600): `dA2-sessions`, the desktop sessions list in a 400pt window. Moved here from the Tasks page on 2026-10-15.
- Row S1 (y=0) is the superseded first pass. Its "Needs from the server" sticky still applies where S2 did not remove it.

**Review surface:** the canvas page **S2 build plan (Oct 15)**. It has 13 boards, each showing a live S2 design with numbered pins and the FE/BE work for every pin. This file is the working copy of the same plan.

Status (2026-10-16): **Phases 1–5 done; shipped.** Phases 1–4 verified and committed; `main` at `8aaffc7`, pushed. TestFlight 202610161522 (v1.3.0) is VALID and in internal testing; both servers run `8aaffc7`; the desktop app is installed on both Macs. Phase 5 found and fixed an older server bug in `/api/events` (see Phase 5). Worktree `worktree-sessions-redesign-s2`, based on local `main` at `8b0be91`.

Tier: **product** (lfg ships to TestFlight and both Macs).

---

## How to read this plan

Each design screen gets a table. Every row maps one thing you can see in the design to:

- **Frontend**: the view or component to build or change. IDs start with `F` (phone) or `DF` (desktop).
- **Backend**: what the server already gives (**exists**) or what we must add. New server work has a `B` ID.

The `B` items are collected in [Backend work](#backend-work), and the `F`/`DF` items in [Component inventory](#component-inventory). The [Phases](#phases) section orders all of it.

---

## User story

As Eugene, I run many agent sessions across two Macs. I want the session list to tell me **what state each session is in**, and the session view to show **state, questions and tools without hunting through a menu**, so I can triage and answer from my phone in seconds and see the same picture on the desktop.

## User flow

**Phone**

1. Open Sessions. Groups show Needs input, Working, Unread, Idle and Closed, with counts.
2. Each row says what state it is in: the question being asked, "Working" with its running time, or "New reply".
3. Tap a Needs input row. The session opens with the question in a bottom panel, laid out for its kind (question, permission, plan, sign-in).
4. Answer. The status under the title turns to "Working · 4s".
5. While it works, type a follow-up. The Stop button turns into Send. The message shows as a dashed "Queued" bubble until the agent picks it up.
6. Tap the tools button for the session sheet: Terminal, Files & links, Subagents, Sign in, previews, Model, Effort, Host, Fork, Stop, End.

**Desktop (400pt window)**

1. The Sessions tab shows Needs input, Working and Recent, each with a time column.
2. Rows on an offline host stay visible, dimmed.
3. Click a row. The session opens in iTerm (no change).

---

## Screen-by-screen annotation

### 1. S2 · Sessions list (`s2-list`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Host dots "● Pro ● Air" top-left | **F1** `SessionListTopBar`: always dots + names, also with one host. Replaces the "Connected · N running" text in `HeaderStatusLine` (`SessionListView.swift:889`). | Exists: host reachability is client state (`MultiHost`). |
| Glass capsule: Search + ••• | **F1**: one capsule with two buttons. Today they are two separate toolbar items (`:766`, `:825`). The ••• menu keeps Filter directories, Group by, Sort by, Settings. | None. |
| Groups: Needs input · Working · Unread (Mark all read) · Idle · Closed | **F2** group changes in `SessionStore.Group` (`SessionStore.swift:3186`). Rename "Needs you" → "Needs input". Fold **Paused** (API error) into Needs input and **Restarting** into Working, as the S1 note says. Remove child-agent rows and the orphan "Agents" section: subagents live in the session. Persist which groups are collapsed (Idle and Closed collapsed by default). "Mark all read" exists (`markAllRead`). | Exists: the ladder `closed → prompt → blocked → busy`, unread is client-side (`ReadState`). |
| Status dot colour per group | **F3**: amber needs input, green working, purple unread, blue idle, grey closed. New dark tokens (**F16**). | None. |
| Row line 1: title, **bold** when needs input or unread | **F3** `SessionRow` v2 (`SessionListView.swift:1147`). | Exists: `title`. |
| Row line 2, needs input: "Asks: upload build 205 now?" with a chat icon | **F3** + **F17** `SessionRowLine` presenter in LFGCore (pure function: group + prompt + busy + reply → icon, text, colour). | Exists: `prompt.question`. |
| Row line 2, sign-in: "Sign in to search.google.com" with a key icon | **F17**. | Exists: `prompt.signIn.website`. |
| Row line 2, working: "● Working · 3m" in green | **F17**. No live step text: dropped 2026-10-15 (not needed, and it would add server load). | Exists: `busy`; the time is the running duration the list already shows (`SessionListTime.runningSince`, from `startedAt`). |
| Row line 2, unread: "New reply". No last-reply text in the list (your call, 2026-10-15) | **F17** fixed copy. | Exists: unread is client-side (`ReadState`). |
| Row line 2, idle: "Ready for your next message" | **F17** fixed copy. | None. |
| Row line 2, closed: "Ended yesterday · send a message to resume" | **F17**. | Exists: `closed`, `lastActivityAt`. |
| Row line 3: project · model · "2 subagents" · time · host | **F3**. Host moves from a chip on the right into the meta line, always shown. | Exists: `project`, `model`, `runningChildAgentCount`, `lastActivityAt`, host from `/api/info`. |
| Row line 3: repeat icon when the session came from a scheduled task | **F3**. | **B6** `task: {id, name}` on the row. Only the reverse link exists today (`TaskRun.sessionId`). |
| No buttons in rows | **F3** keeps swipe actions (read/unread, hide directory), no inline buttons. | None. |
| Floating tab bar with badge counts + floating "+" | **F4**: badges on both tabs. The dock exists (`RootView.swift:241`); badges are new. Sessions badge = Needs input count. Tasks badge = tasks whose run needs input or failed. | Exists: both counts can be derived from data the client has. |

### 2. S2 · Session view, working (`s2-view`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Glass back button, glass tools button | **F5** `SessionTopBar`. The tools button opens the session sheet (**F12**). Today the title bar has a ••• menu. | None. |
| Title + status line "● Working · 3m 12s · Pro · lfg" | **F5** + **F18** `SessionStatusLine` presenter (LFGCore). The elapsed time ticks with a `TimelineView`. Replaces `SessionTitleActivity` (`SessionDetailView.swift:1176`) and the separate paused, offline and error banners. | None: the elapsed time starts at the newest user message in the transcript the view already loads. |
| User bubble (blue) and assistant prose | Exists: `TextBubble` (`Components.swift`). Restyle to S2 tokens. | Exists. |
| "Read 6 files, ran 3 commands" step, expands to each command | **F6** `ToolStepGroup` view + **F19** `TranscriptStepGrouper` (LFGCore, pure). It folds consecutive tool calls and results into one step with counts. Today `ToolLineView` (`Components.swift:316`) shows one raw row per call and per result. | **B11** structured tool fields on each message: `tool: {name, target}`. Today the text is `"Edit: {json}"`, which is fragile to parse. Codex rows already carry "Ran / Explored / Edited". |
| "Edited 2 files" step | **F6**/**F19**: edits get their own step. No diff counts (design rule). | **B11**. |
| Expanded states (boards `s2-tools-group`, `s2-tools-single`) | **F6** `ToolCallCard`. Expanding a group lists its calls (verb, target, duration); tapping a call opens a card with its input (command, or file + lines) and its result (commands show the last 8 lines, reads the first 6), plus "Show all N lines". A single call opens straight to its card, with no list in between. | **B11** pairing (`useId` ↔ `toolUseId`). Result text and `ts` exist. |
| Pills above the composer: Subagents (ring, "1 running · 3/4 done"), Files 4, Terminal | **F7** `ComposerPillRow`. Replaces the full-width `ChildSessionsComposerBar` (`SessionDetailView.swift:1977`) and the sign-in cards (sign-in moves to the needs-input panel). | Exists: `childAgents` statuses; the files count comes from `TranscriptResourceIndex` on the client. |
| Composer placeholder "Add to this turn…" while working | **F8** `MessageComposer` v2 (`MessageComposer.swift:24`). | Exists: `busy`. |
| Attach button | Exists: `AttachmentTray`. | Exists. |
| Model + effort chip "Opus 5.5 · High" in the composer | **F8**: chip opens Model and Effort pickers. Disabled with a hint while the agent works or asks, because the server refuses a change then. | Exists: `POST /model`, `POST /effort` (409 while busy, queued or prompting). |
| Send button is Stop while working; typing turns it into Send | **F8**. Stop calls `store.interrupt` (today only in the ••• menu). | Exists: `POST /interrupt`. |

### 3. S2 · Message queued (`s2-queued`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Status line "Working · 3m 40s · 1 queued · Pro" | **F18**: queued count from `pendingSends`. | Exists. |
| Queued message in today's soft strip above the input bar; the transcript does not move (your call, 2026-10-15) | **F9** keeps `PendingStripView` (`Components.swift:561`), restyled to S2 colours. | Exists: `QueuedMsg.status` `pending | sending | queued`. |
| Tap a row → its menu opens right at the row: Send now ("Stops the current step first") / Edit / Remove | **F9**: one `Menu` per strip row already anchors to the tapped row (`Components.swift:578`). **Edit and Remove only while lfg still holds the message** (`pending`). Once Claude has it in its own queue (`queued`), the server refuses removal (409), so the menu shows Send now only, with "Already with Claude". See [D4](#d4-queued-messages-that-claude-already-holds). | Exists: `POST /queue/:id/send-now` (works for `pending` and `queued`), `DELETE /queue/:id` (pending only). Edit = delete + resend on the client. |
| After Send now: the message becomes a normal bubble in the transcript | **F9**. | Exists. |

### 4. S2 · Message not sent (`s2-queued-failed`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Status line "Air offline · 2m" in the top bar | **F18**. Needs an "offline since" time per host. | None: the client records when a host went offline (`MultiHost`). |
| Waiting row in the strip: clock + "Queued" | **F9** state `offlineQueued` (exists in `OutgoingSendPresentation`). | Exists (client outbox). |
| Failed row in the same strip: red mark + "Not sent", no reason (your call, 2026-10-15) | **F9**: the failed strip row's inline Retry button becomes a menu. | Exists: failed status. No new field. |
| Tap the row → menu at the row: Retry / Edit / Delete | **F9**. Delete is new. | Exists: `POST /queue/:id/retry`, `DELETE /queue/:id` for failed rows. |

### 5. S2 · Needs input: question / permission / plan (`s2-question`, tweak `kind`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Panel docked at the bottom, transcript above it | **F10** `NeedsInputPanel`. Today `PromptPanelView` (`Components.swift:359`) renders inside the transcript as its newest row. | Exists: `prompt` on the row and as a journal delta. |
| Header "Claude is asking · 1 of 1" / "Claude needs permission" / "Plan ready for review" | **F10** picks a layout by kind. | **B4** `prompt.kind`: `question | permission | plan | trust | signIn`. Today only sign-in is distinguishable. |
| Status line "Needs input · 2m" | **F18**. | **B3** `prompt.askedAt`. |
| Question: numbered options, "Type something else…", Dismiss | **F10** question layout. Options call `answer(index)`. | Exists: `POST /answer {index}`, `POST /dismiss`. **B5** free-text answer for "Type something else…". |
| Permission: command card "bundle exec fastlane beta…", "In ~/dev/personal/lfg on Pro", Allow once / Deny / Always allow | **F10** permission layout. Buttons map to the matching option index. | **B4** `permission: {command, cwd}` from the pane. Today `question` is just "Do you want to proceed?". |
| Plan: numbered summary, "Read the full plan ›", Approve / Keep planning | **F10** plan layout + a sheet with the full plan. | **B4** `plan: {text}` from the stitched pane preamble (`PaneStitcher`). The plan is not in the transcript while it is live. |
| After an answer: status turns to "Working · uploading · 4s" | **F18**. | Exists. |

### 6. S2 · Needs input: sign-in (`s2-signin-prompt`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Status "Needs sign-in · 5m · Air · inbox" | **F18**. | **B3** `askedAt` (or the request's `createdAt`, which exists). |
| Panel: "Sign in to search.google.com", "To Chrome on Eugenes-MacBook-Air", "Sign in on iPhone", no Dismiss | **F10** sign-in layout, same anatomy as a question. Replaces `signInPanel` (`Components.swift:381`) and the sign-in cards above the composer. | Exists: `prompt.signIn {url, website, targetName}`; `/dismiss` already refuses sign-in prompts. |

### 7. S2 · Sign-in browser (`s2-signin`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Address pill holds the context: "accounts.google.com · For Search Console audit · goes to Air" | **F11** `PhoneSignInView` header (`PhoneSignInView.swift:77`). Today: back, host text, spinner, reload. | None. |
| "I'm signed in" → review sheet "Send this sign-in to Air?" with a switch per domain and "Send N cookies" | **F11**: add the review step to the agent-request path. Today "Done" sends every cookie with no review. | Exists: `POST …/requests/:id/complete {cookies}` derives the domains from the cookies sent, so the client filters by domain. |
| Result "Signed in on Air · picked up the sign-in and is working again" | **F11** copy. | Exists: request `state`/`result`. |

### 8. S2 · Session sheet (`s2-menu`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Title with rename, "Pro · ~/dev/personal/lfg · started 2h ago" | **F12** `SessionSheet`. It replaces `SessionOptionsMenu` (`SessionDetailView.swift:1525`). | Exists: `PUT /title`, `cwd`, `startedAt`. |
| 6 tiles: Terminal, Files & links (6), Subagents (2), Sign in, Browser preview, iPhone preview | **F12** tile grid with badges. Each tile opens what the menu opens today. | Exists. |
| Model row | **F12**. | Exists: `POST /model`. |
| Effort segmented: Low · Med · High · Max | **F12**. Levels come from `SessionEffort.known` for the current model (not always four). | Exists: `POST /effort`. |
| Host row "Pro · move to Air" | **F12**. Uses today's move flow and its confirm. | Exists (client-driven move). |
| Fork session · Mark as unread · Stop current turn · End session | **F12**. | Exists: fork, `interrupt`, `close`; unread is client-side. |
| Footer "tmux lfg-fork-3 · id 7f3a…c21 · tap to copy" | **F12**. | Exists: `tmuxName`, `sessionId`. |

### 9. S2 · Subagents sheet (`s2-subagents`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Header "1 running · 2 done · 1 failed" | **F13** restyled `ChildAgentSessionsSheet` (`SessionDetailView.swift:2038`), renamed "Subagents". | Exists: `childAgents[].status`. |
| Row: status, title, "Running" or the result, "general-purpose · 1m 12s". No current step (your call, 2026-10-15) | **F13**. Duration from start/finish times. | Exists: `description`, `agentType`, times, status. **B8** `result` per finished subagent. |
| Detail: Task prompt, steps summary, result | **F13** child detail, with a link to today's full transcript view. | **B8** `prompt` (the server hides the Agent input today) and a steps summary from **B11**. |

### 10. S2 · Files & links sheet (`s2-files`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Segmented "Files 5 · Links 2" | **F14** restyled `AttachmentsSheet` (`AttachmentsSheet.swift:11`). | None. |
| Files tab: three sections, Images · Videos · Documents, all plain rows (name · folder · age), no previews (your call, 2026-10-15). Links tab: mark · title · domain | **F14**: group the file list by extension. | Exists: `TranscriptResourceIndex` (client), `GET /api/file`. |

### 11. S2 · Terminal (`s2-terminal`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Extra keys: esc, tab, ctrl (sticky), ⌥, arrows, `|`, `/`, `~`, ⌘V paste | **F15**: add ⌥ and ⌘V paste to the SwiftTerm accessory row. The others exist. | Exists: the terminal WebSocket passes raw bytes. |
| Fit / Wide toggle, keyboard show/hide | Exists (`TerminalScreen.swift:115`). Restyle. | None. |
| Title "Terminal · Shell on Pro": a shell on the host, as today, not the session's pane (your call, 2026-10-15) | **F15** keeps today's `TerminalScreen` (shared `lfg-term-phone` shell); title change only. | Exists: `/api/term`. See [D3](#d3-terminal-stays-a-shell-on-the-host). |

### 12. Desktop · Sessions list (`dA2-sessions`)

| Design element | Frontend | Backend |
| --- | --- | --- |
| Centered Sessions / Tasks switcher with amber count badges | **DF1**. Builds on the other session's narrow-window work (uncommitted, see [Risks](#risks-and-collisions)). Badges: Sessions = Needs input count; Tasks = tasks needing input or failed. | Exists. |
| Search button; no "+" | **DF1**: search is always the button; remove `createSessionButton` (desktop scope: no session creation). | None. |
| Host strip "● Pro ○ Air offline · 3 working" | **DF2**: a row under the title bar, not toolbar chips. Offline = hollow amber ring + "offline". | Exists (client host state). |
| "By status" dropdown | **DF2**: text menu over today's `GroupMode` (status / directory). | None. |
| Groups: Needs input · Working ("by last activity") · Recent 43, collapsible | **DF3**: reuse `MenuBarSessionProjection` (`LFGSessions.swift:436`), which already splits needs input (oldest first), running (newest first) and recent. Make status headers collapsible. | **B12** `total` on `GET /api/sessions/resumable` so "Recent 43" is a real count; today pages hold 100 rows. |
| Time column "2m ago" (amber / green / grey) | **DF4** `SessionRow` v2 (`LFGSessions.swift:4282`). | Exists: `lastActivityAt`. |
| Meta "fiftystrong · Pro · Claude Code opus · from a task" | **DF4**. | **B6** `task`. |
| Needs input line "Asks: which launch page direction first?" | **DF4**: decode `prompt` in `APISession` (it is in the payload, not decoded). | Exists: `prompt`. |
| Working line "● Working" | **DF4**. No live step text (dropped 2026-10-15). | Exists: `busy`. |
| Recent line "Closed". No last reply (your call, 2026-10-15) | **DF4**. | Exists: `closed`. |
| Offline host rows dimmed to 50% with "Air is offline" | **DF5**: keep each host's last good snapshot. Today a failed host's rows disappear (`fetchHost`, `:1584`). | None. |
| Click opens iTerm | Exists (`Opener.open`). | Exists. |

---

## Backend work

All additive: new optional fields and one new endpoint mode. Old clients ignore them.

| ID | What | Shape | Where | Used by |
| --- | --- | --- | --- | --- |
| **B3** | When the prompt appeared | `prompt.askedAt` | Stamp the first time the pump sees a prompt identity (`PumpDeltas`); sign-in uses the request's `createdAt`. | Status line "Needs input · 2m" |
| **B4** | Prompt kind + details | `prompt.kind`, `prompt.permission {command, cwd}`, `prompt.plan {text}` | Classify in `parsePrompt` (`tmux.ts:1132`) from the selector wording; transcript AskUserQuestion = `question`; sign-in = `signIn`. Extract the command from the box above the selector; take the plan from the stitched preamble. Cover Claude and Codex prompts. Fixture tests from real pane captures. | Needs-input panel |
| **B5** | Free-text answer | `POST /answer {index, text}` | Select the "Type something" option, type the text, press Enter, confirm by the transcript (same rules as sendq: no pane read may gate the Enter). | "Type something else…" |
| **B6** | Scheduled-task origin | `task: {id, name}` on live and closed rows | In-memory `sessionId → task` map from the scheduled-task runs store. | Phone repeat icon, desktop "from a task" |
| **B8** | Subagent detail | `result`, `prompt` per subagent | `GET /api/sessions/:id/subagents`, read only when the sheet opens: the result is a finished subagent's last assistant text; expose the Agent prompt on this endpoint only. No current step. | Subagents sheet |
| **B11** | Structured tool fields + call/result pairing | Calls: `SessionMsg.tool: {name, target, useId}`. Results: `toolUseId`, `isError` | Set where tool rows are built (`sessions.ts:2491`, Codex `:1416`). `target` = file path, command, pattern or URL. Today nothing links a result to its call, and failures are not flagged. The result text is already sent in full, and every message has `ts`, so duration = result `ts` − call `ts`. | Step grouping, expanded call cards, B8 |
| **B12** | Closed-session total | `total` on `GET /api/sessions/resumable` | Count while enumerating. | Desktop "Recent 43" |

Not needed (already exist): answer by index, dismiss, interrupt, close, fork, rename, model, effort, queue send-now / retry / delete, sign-in complete with filtered cookies, subagent list, file serving, terminal byte bridge.

Not in this plan: server-side unread sync across devices.

Dropped 2026-10-15: **B1 / B1b**, the live "current step" line (`activity` + `turnStartedAt` + a journal delta). You do not need it, and it would add a per-tick server cost for every working session. Working rows say "Working" with the running time the list already has. Subagent rows say "Running".

Dropped 2026-10-15: **B2**, last-reply text in any list (phone unread rows say "New reply", desktop Recent rows say "Closed").

Dropped 2026-10-15: **B7**, the failure code behind "Not sent · Air is offline". Unsent messages show "Not sent" with no reason.

---

## Component inventory

**Phone (iOS app + LFGCore)**

| ID | Component | New / changed | File(s) |
| --- | --- | --- | --- |
| F1 | `SessionListTopBar` (host dots + glass Search/••• capsule) | changed | `SessionListView.swift` |
| F2 | Group rules (rename, fold Paused/Restarting, drop child rows, persisted collapse) | changed | `SessionStore.swift`, `SessionListView.swift` |
| F3 | `SessionRow` v2 (3 lines, bold, meta with host and task icon) | changed | `SessionListView.swift` |
| F4 | Dock tab badges | changed | `RootView.swift` |
| F5 | `SessionTopBar` (glass back/tools, title, status line) | changed | `SessionDetailView.swift` |
| F6 | `ToolStepGroup` (collapsible step row) | new | `Components.swift` |
| F7 | `ComposerPillRow` (Subagents ring, Files, Terminal) | new | `SessionDetailView.swift` |
| F8 | `MessageComposer` v2 (placeholder, model/effort chip, Stop↔Send) | changed | `MessageComposer.swift` |
| F9 | `PendingStripView` restyle: queued, waiting and not-sent rows, each with a menu at the row (Delete is new) | changed | `Components.swift` |
| F10 | `NeedsInputPanel` (question / permission / plan / sign-in) | new (replaces `PromptPanelView`) | new `NeedsInputPanel.swift` |
| F11 | Sign-in browser header, review step, result | changed | `PhoneSignInView.swift` |
| F12 | `SessionSheet` | new (replaces `SessionOptionsMenu`) | new `SessionSheet.swift` |
| F13 | Subagents sheet + child detail | changed | `SessionDetailView.swift` |
| F14 | Files & links sheet (segmented; Images · Videos · Documents as plain rows) | changed | `AttachmentsSheet.swift` |
| F15 | Terminal: host shell as today, keys ⌥ and ⌘V, S2 styling | changed | vendored SwiftTerm accessory, `TerminalScreen.swift` |
| F16 | S2 dark tokens (with light counterparts) | changed | `Theme.swift` |
| F17 | `SessionRowLine` presenter | new, pure, tested | `LFGCore` |
| F18 | `SessionStatusLine` presenter | new, pure, tested | `LFGCore` |
| F19 | `TranscriptStepGrouper` | new, pure, tested | `LFGCore` |

**Desktop (`desktop/LFGSessions.swift`)**

| ID | Component | New / changed |
| --- | --- | --- |
| DF1 | Switcher with badges, search button, no "+" | changed |
| DF2 | Host strip row + "By status" menu | new |
| DF3 | Three collapsible groups from `MenuBarSessionProjection` | changed |
| DF4 | `SessionRow` v2 (time column, 3 lines); decode `prompt`, `task` | changed |
| DF5 | Keep last good snapshot per host; dim offline rows | changed |

---

## Success criteria

- [x] SC1: `GET /api/sessions` returns `task` for sessions a scheduled task started, and `GET /api/sessions/resumable` returns `total`. *(2026-10-16: `total` measured in-process on the Pro's real transcripts (null, then 3,982); `task` covered by `src/task-origin.test.ts`. Live on the Pro after the Phase 5 restart: `total` 4,001 on the first page, `task` on 8 scheduled-task rows, `lastUserAt` on every row.)* — **Verify by:** curl on the live host after restart; one task session shows its task, and the total matches a count of closed transcripts.
- [x] SC2: Working rows show "Working" and the running time, with no new server field or journal event for it. — **Verify by:** `SessionRowLine` test for a working session; the diff adds no journal event type.
- [x] SC3: The phone list shows the five groups with the right members: Paused sessions in Needs input, Restarting in Working, no child-agent rows. Collapse state survives a relaunch. — **Verify by:** LFGCore tests on the group rules; simulator screenshot against the live server; relaunch check.
- [x] SC4: Each row's line 2 matches its state (question, sign-in, Working + time, New reply, idle copy, closed copy). — **Verify by:** `SessionRowLine` tests, one per state; screenshot.
- [x] SC5: The session top bar shows Working + ticking elapsed, Needs input + age, Needs sign-in, host offline + age, and the queued count. — **Verify by:** `SessionStatusLine` tests; screenshots of a working and a waiting session.
- [x] SC6: Consecutive tool calls show as one step row with correct counts, and expand to each call. — **Verify by:** `TranscriptStepGrouper` tests on real Claude and Codex transcripts; screenshot.
- [x] SC7: Stop is the send button while working and turns into Send when you type; Stop really interrupts. — **Verify by:** tap Stop on a live working session on the simulator; transcript shows the interrupt.
- [x] SC8: A message sent mid-turn shows as a row in the strip above the input bar, and the transcript does not move; the row's menu opens at the row; Send now works; Edit/Remove appear only while lfg holds it; a failed send shows "Not sent" and Retry/Edit/Delete work. — **Verify by:** live send to a busy session; seed a failed outbox row (per memory: loopback stubs hide failures).
- [ ] SC9: The needs-input panel shows the right layout for a question, a permission, a plan and a sign-in, and each button answers the prompt. — **Verify by:** `parsePrompt` fixture tests from real pane captures (all four kinds); live answer of a real permission prompt. *(2026-10-16: question, permission (Allow once and Deny) and plan answered live; sign-in is answered with SC11 in Phase 3.)*
- [x] SC10: "Type something else…" answers a question with free text. — **Verify by:** live AskUserQuestion in a test session; the answer lands in the transcript.
- [ ] SC11: The sign-in flow has a review step on the agent path, and only the switched-on domains are sent. — **Verify by:** live request; server log shows the domain list. *(2026-10-16: review step and per-domain send count checked on the fixture; the delivery leg needs a connected Chrome target and is not yet exercised live.)*
- [x] SC12: The session sheet holds every action of the old ••• menu, and each one works. — **Verify by:** checklist walk on the simulator, one tap per item. *(2026-10-16: 15/15 walked on a throwaway session; fork's refusal was the rig's two-host claim, `phase3-live/live-checks.md`.)*
- [x] SC13: The desktop list at 400pt shows Needs input / Working / Recent with the time column and status lines from live data; offline-host rows stay visible and dimmed. — **Verify by:** `--window-shot 400` for layout plus a live-data probe (memory: window shots render fixtures); stop the Air's server briefly or use the stub host.
- [x] SC14: No regression in send delivery, prompt answering or the Live Activity. *(2026-10-16: bun 1,240 and LFGCore 644 + 415 green; live answer + send in the S2 app on the Pro pass after the `/api/events` fix; Live Activity slices computed with no failures after both restarts. See Phase 5.)* — **Verify by:** existing `bun test` and LFGCore suites green; one end-to-end send + answer on a real session.

## Steps to verify

1. Server: `bun test`; restart the Pro server by port; curl `/api/sessions` and `/api/sessions/resumable`.
2. LFGCore: `swift test` in `ios/LFGCore`.
3. iOS: FlowDeck build + run on the iPhone 17 Pro simulator pointed at the Pro; drive each screen by tapping.
4. Desktop: `desktop/build.sh`; `lfg --window-shot 400 …` and a live-data probe.
5. Independent audit: `ios_visual_evidence_auditor` for phone, `verification-auditor` for server + desktop.

---

## Phases

Each phase ends green before the next starts.

| Phase | Scope | Covers | Gate |
| --- | --- | --- | --- |
| **P0 Prereqs** | Rebase this worktree onto the latest `main`. Add S2 dark tokens (F16). | — | Clean rebase; app builds. |
| **P1 Phone list** | F1–F4, F17 + B6 (task origin on rows). | SC1 (task), SC2–SC4 | Server and LFGCore tests; simulator on live data; **visual verifier PASS against `s2-list`**. |
| **P2 Session view** | F5–F10, F18, F19 + B3, B4, B5, B11: top bar and status, tool steps (collapsed and expanded), composer, queued strip, needs-input panel (question, permission, plan, sign-in). | SC5–SC10 | Tests; live send, Stop, queue and prompt checks; **visual verifier PASS against `s2-view`, `s2-tools-*`, `s2-queued*`, `s2-question` (3 kinds), `s2-signin-prompt`**. |
| **P3 Sheets and menus** | F11–F15 + B8: session sheet, subagents, files & links, terminal keys, sign-in browser. | SC11, SC12 | Checklist walk; **visual verifier PASS against `s2-menu`, `s2-subagents`, `s2-files`, `s2-terminal`, `s2-signin`**. |
| **P4 Desktop list** | DF1–DF5 + B12. Starts after the other session commits its narrow-window desktop work. | SC1 (total), SC13 | Window shot at 400pt + live probe; **visual verifier PASS against `dA2-sessions`**. |
| **P5 Ship** | Audit, TestFlight, desktop install on both Macs. | SC14 | Auditor PASS; only with your go-ahead. |

Order set by Eugene (2026-10-15). Every phase ends with the visual verifier comparing the build against its canvas boards; the canvas is the only design reference.

---

## Open decisions

### D1. No live activity line (decided 2026-10-15)

You decided working rows do not show the current step. Working rows on the phone and the desktop say "Working"; the phone adds the running time it shows today. The session view's elapsed time comes from the transcript it already loads. No server work.

### D2. Desktop keeps three groups

**Recommended: keep Needs input / Working / Recent, as drawn.** The desktop has no read state, so Unread and Idle have nothing to sort by. The phone keeps five groups.

### D3. Terminal stays a shell on the host

Decided 2026-10-15: the terminal opens a shell on the host, as today, and does not attach to the session's pane. (Attaching is possible later with tmux's `attach-session -f ignore-size`, which keeps the phone from resizing the pane; about a day of work.) No server work in this plan.

### D4. Queued messages stay in the strip; Edit and Remove only while lfg holds them

Decided 2026-10-15: queued messages keep today's soft strip above the input bar, outside the transcript, and the menu opens at the tapped row. Once a message reaches Claude's own queue, the server cannot remove it (it is absorbed at the next step). **So Edit and Remove show only while lfg holds the message.** After that, the menu offers Send now only, with "Already with Claude". This is a server limit, not a choice; the design needs that one-line state.

### D5. Free-text answers ship last

B5 drives the TUI with keystrokes, the riskiest change here. It sits in P5 with live tests. Until it lands, "Type something else…" falls back to today's behaviour: the text goes as a new message, which closes the selector first.

### D6. Dark-first, light kept

The app follows the system appearance today. **Decision: S2 tokens become the dark values; light values are derived, not redesigned.** You use dark mode; light stays usable.

---

## Risks and collisions

- **Another session has uncommitted work in the files this plan changes** (main checkout, 2026-10-15): `desktop/LFGSessions.swift` (about 330 changed lines: the 180pt narrow window, fork routing), `src/tmux.ts` (55), `src/sessions.ts` (16), `src/commands/serve.ts` (11), plus scheduled-task files. This worktree branched from committed `main`, so it does not have those edits. P0 waits for them to be committed. Server edits stay additive to keep rebases small.
- **Pane parsing (B4, B5)** is the most fragile seam in lfg. Real sessions come from the `cy`/`cx` shell functions and are attached at about 78 columns; tests must use captures from those, not from API-spawned panes.
- **Closed-row cost (B2, B12):** reading a reply for 100 closed transcripts per page must be cached by mtime, or the list endpoint slows the single event loop.
- **`SessionStore.swift` (4,899 lines) and `SessionDetailView.swift` (2,221 lines)** are shared hot spots. New views go into new files.

---

## Decision Log

- 2026-10-15 — Moved `dA2-sessions` from the Tasks page to the Sessions page (canvas version 42), at x=0, y=2600, renamed "Desktop · Sessions list (400pt window)". No content change.
- 2026-10-15 — Worktree reset from stale `origin/main` (`9b6a684`) to local `main` (`8b0be91`), per the known worktree quirk.
- 2026-10-15 — Paused (API error) folds into Needs input and Restarting into Working, carried over from the S1 note, since S2 shows neither group.
- 2026-10-15 — Child-agent rows leave the list; subagents show in the session (pill + sheet), per S2.
- 2026-10-15 — Plan published to the canvas as page "S2 build plan (Oct 15)" (version 53), in the same format as the A2 build plan page. Pin positions are estimated from the design source; not checked visually (the canvas page switcher did not respond to synthetic clicks).
- 2026-10-15 — Eugene dropped the live "current step" line on working rows (B1, B1b): not needed, and it adds server load. Working rows show "Working" (+ running time on the phone). The design boards `s2-list` and `dA2-sessions` were updated to match.
- 2026-10-15 — Added two design boards for expanded tool steps (`s2-tools-group`, `s2-tools-single`, canvas version 57). B11 grows a call/result pairing (`useId`, `toolUseId`) and `isError`, because the server sends neither today.

- 2026-10-15 — Review round 2: queued and unsent messages stay in today's strip (menu at the row); no failure reason (B7 dropped); no current step on subagent rows; Files & links lists Images · Videos · Documents with no previews; the terminal attaches to the agent's pane (B13). Canvas version 59.
- 2026-10-15 — Reversed: the terminal stays a shell on the host (B13 dropped). The `s2-terminal` design now shows a host shell. Canvas version 62.
- 2026-10-15 — Unread rows say "New reply"; no last-reply text in the phone list. B2 now serves only the desktop Recent line. Canvas version 63.
- 2026-10-15 — B2 dropped: no list shows last-reply text. Canvas version 64.
- 2026-10-15 — Phases reordered by Eugene: phone list → session view → sheets and menus → desktop. A visual verifier checks every phase against the canvas boards (not the claude-design skill).
- 2026-10-16 — "Working · time" means time since the newest genuine user message, on the list and in the view. The server sends `lastUserAt` (one new session field); absorbed mid-turn messages and Claude's interrupt marker do not restart it. Alternative was a server busy-flip clock, which resets on every server restart.
- 2026-10-16 — An answered question is its own step kind, "Asked · <question>", in the prose font. Not on any board; the boards never show an answered question, and "Used" with no target said nothing.
- 2026-10-16 — Every Claude question offers the typed answer, even when the transcript's options omit "Type something." (the host types into that row from the pane). Codex questions still need the option listed.
- 2026-10-16 — Terminal Wide follows the board: it shrinks the type to 10.5pt and fits the width (about 58 columns on the iPhone 17 Pro). The old Wide kept 13pt type and scrolled a 120-column grid sideways; that is gone. Alternative: keep the 120-column scroll and deviate from the board. Chosen because the canvas is the reference; easy to restore if 120 columns matter more.
- 2026-10-16 — Terminal header fills use the colour the canvas draws (#313132) rather than SwiftUI's blend of the CSS `rgba(255,255,255,0.12)` (#28282A).
- 2026-10-16 — The terminal's keyboard key hides and shows the keyboard, as the board's does ("Hide keyboard" / "Show keyboard"), instead of swapping in SwiftTerm's F-key and symbol panel, which is no longer reachable. Hidden keeps the key row on screen at the board's height; iOS draws its keyboard backdrop below it.
- 2026-10-16 — Phase 5: fixed the deaf `/api/events` resync on the server, not in the app. One server change fixes every shipped client on both hosts at once; an app-side reconnect would need a new build and still leave older builds deaf.
- 2026-10-16 — Desktop: the window keeps the native macOS window buttons (14pt, macOS 26 spacing) rather than moving them to the board's drawn 12pt traffic lights; system chrome, like the phone's sheets and glass buttons. The switcher's 24pt centring offset is from the board's numbers.

## Phase 1 — phone list (implementation notes) — VERIFIED 2026-10-15 (verifier round 5 PASS)

Files:
- Server: `src/task-origin.ts` (+ test) — session → task map from the run log, read at most once per 5 s; `src/commands/serve.ts` adds `task` to `/api/sessions` and `/api/sessions/resumable` rows.
- LFGCore: `SessionListRow.swift` — `SessionListSection` (folding, titles, default fold), `SessionListCollapse` (persisted fold state), `SessionRowLine` (line 2), `SessionRowMeta` (line 3), `TaskOrigin`; `Models.swift` — `task` on `Session` and `ResumableSession`.
- App: `SessionListView.swift` — S2 tokens, five status sections, persisted fold (search ignores folds), one header style, three-line `SessionRow`, host dots for every host; `RootView.swift` — amber dock badges; `SessionStore.swift` — closed rows carry `task`; debug fixture `LFG_S2_LIST_FIXTURE=1`.

Decisions (Phase 1):
- The Tasks badge counts sessions a task started that need input. A task whose last run failed is not counted yet: that needs the task list, which the Tasks redesign session owns.
- Closed rows show no host: a closed transcript is synced to both Macs, so "its host" is ambiguous (the board shows one; the app has none to show).
- Model names show as the host reports them (`opus`, `gpt-6.1-sol`); the board's prettified names are sample text.
- The background-process count stays on the meta line as "N background" (the board has no example; dropping existing info silently is the mistake logged earlier).
- Collapse state persists in `@AppStorage`; Idle and Closed start folded. Search shows every match regardless of folds.
- Rows keep relative times ("5h"), task rows included. The board's "9:00 AM" on one task row is sample copy with no rule behind it.
- The search/more capsule's 44pt height and button spacing come from the system toolbar's glass grouping; only its glyphs are drawn to the board.

## Phase 2 — session view (implementation notes) — VERIFIED 2026-10-16 (visual rounds 13–14 PASS; live checks PASS after 7 fixes)

Files so far:
- LFGCore: `TranscriptStepGrouper.swift` (tool steps; edits get their own step, split only once every earlier call has its result), `SessionStatusLine.swift` (top-bar line), `SubagentPill.swift` (pill ring and tally), `ModelChipLabel.swift` ("Opus 5.5 · High" from raw ids), `QueuedStripRow.swift` (strip row icon, tag and menu per state); `Models.swift` — `AgentPrompt.askedAt` (B3 client side, server pending), `SessionMessage.toolUseId/tool/isError` (B11).
- Server: `src/sessions.ts` — B11 structured tool fields (`tool {name, target}`, `toolUseId`, `isError`) on Claude and Codex rows.
- App: `Components.swift` — `ToolStepGroupView`, `ToolCallCard`, `ToolOutputSheet`, S2 `PendingStripView`; `SessionDetailView.swift` — transcript renders steps, S2 title bar with status line, `ComposerPillRow` (Subagents ring, Files, Terminal), `ComposerModelChip`, tools glyph on the options button; `MessageComposer.swift` — S2 mode (solid surface, chip slot, Stop↔Send); `Theme.swift` — shared `S2` palette; `SessionStore.swift` — `offlineSinceMs`, debug view fixture `LFG_S2_VIEW_FIXTURE=working|queued|failed`.

Decisions (Phase 2):
- The Subagents pill shows whenever the session has any subagent. The old full-width bar hid finished agents after the next send; the pill is small enough to stay, and "3/4 done" needs the finished ones.
- The offline notice above the composer is gone. The status line says "Air offline · 2m" and the composer placeholder says "Message · sends when Air is back" (board `s2-queued-failed`).
- The paused banner stays in the transcript, because it carries the "Resume on Opus" action. The status line also says "Paused · reason".
- The transient error banner (failed Stop, failed send) stays: it reports an action that failed, not session state.
- The model chip opens while the agent works, but its items are disabled under "Change the model when this turn ends" (the host refuses a change mid-turn).
- The strip menu is the system menu, anchored at the tapped row. Failed rows now open the same menu (Retry / Edit / Delete) instead of an inline Retry button.
- The new-session screen keeps its current composer; only the session view uses the S2 composer mode.
- The sign-in request cards above the composer stay for requests the panel is not showing (a second waiting request).
- Tool steps end after edits: explore → edit stays one step, and the commands after an edit start the next. This is the one rule that fits all three boards (`s2-view`, `s2-queued` "Edited 2 files" then "Ran bun test…", `s2-question` "Ran 7 commands, edited 1 file").
- The question header says "Claude is asking · <header>" from the question's own chip, not "1 of 1": the client does not know how many questions a call bundles.
- "Chat about this" is not offered in the panel (the board omits it); "Type something." becomes the typed-answer field.
- The strip row's menu is drawn by the app, not the system menu: the system menu centred over the row and hid the message; the boards put it 8pt above, right-aligned. A clear layer behind the bottom chrome closes it on any other tap.
- Transcript body text is now 17pt (was 16pt, the old GitHub theme) everywhere the transcript renders prose.
- The boards disagree on the gap between transcript items (14pt on `s2-view`, 12pt on `s2-question`, `s2-signin-prompt`, `s2-tools-*`). The app uses 14pt everywhere; on the 12pt boards a step row under a bubble therefore sits ~2–4pt lower than drawn.
- The call card's input wraps at words (SwiftUI), not anywhere (the board's `word-break: break-all`).

Phase 2d (needs-input panel) — server:
- `src/prompt-kind.ts` (+ test, from real pane captures of Claude Code 2.1.280): `classifyPanePrompt` (question / permission / plan from the pane), `permissionFromToolUse`, `PromptClock` (B3 `askedAt`, first seen per prompt identity).
- `src/sessions.ts` `pendingToolUse` — the transcript's open tool call. A permission dialog's call IS on disk while it waits (unlike AskUserQuestion's turn and ExitPlanMode), so the card shows the exact command.
- Plans: ExitPlanMode is NOT in the transcript while live, but the dialog footer names `~/.claude/plans/<slug>.md`; the server reads that file (home `.claude/plans` only, 32 KB cap) for the full plan.
- `src/tmux.ts` `answerPromptWithText` + `POST /answer {text}` (B5). Probed live: moving to "Type something." and typing replaces the row's label; Enter submits. Newlines collapse to spaces.
- Sign-in prompts carry `kind: "signIn"` and `askedAt` = the request's `createdAt`.
- Trust dialogs now render unnumbered options ("❯ No, exit" / "Yes, I trust this folder"), so `parsePrompt` does not see them at all. Not fixed here (pre-existing); noted for later.

Self-check before the Phase 2 verifier (2026-10-15), fixed:
- The S2 composer filled the screen: a `Spacer` inside the bottom chrome takes all offered height. Now fixed gaps (11 + line + 19 + 34 + 10 = 96pt).
- The bottom chrome sat 16pt high: `.safeAreaPadding(.bottom)` with no length adds 16pt. Now 0 while the keyboard is down (composer 28pt and panel 8pt from the edge, as on the boards).
- Strip menu: iOS flipped the order when opening upward and dropped the subtitle. Now `.menuOrder(.fixed)` and a title/subtitle/image label.
- The send-failure banner ("Message not sent. Tap Retry…") is gone: it showed only while the same failed row was on screen, and you asked for no failure reason.
- The status line no longer counts an unsent message as queued.
- Step summaries list the most frequent kind first (boards: "Read 4 files, ran 2 commands"). Reads preview their first 6 lines, commands their last 8. Call targets truncate at the end. Read cards show "· lines A–B". Step, call, Files and Terminal icons are drawn from the boards.
- Permission "always" option says "this folder" for the session's folder.
- Debug fixtures: fixture sessions never send to a host; fixture outbox rows are dropped.

Phase 2d — client: `NeedsInputPanelModel` (LFGCore, tested), `NeedsInputPanel` (Components.swift) replacing `PromptPanelView`; it takes the composer's place and the pills hide. `PlanTextSheet` (RichContent.swift). Fixture modes `question`, `permission`, `plan`, `signin`.

Phase 2 live checks (2026-10-16), fixed — full report `…/phase2-live/live-checks.md`:
- A message absorbed mid-tool split a call from its result and drew an empty "Used" step. A late result now joins its call's step.
- The list timed "Working" from the process start (list 3m, view 45s). The server now sends `lastUserAt`; list and view share `SessionStore.turnStartedAt`, which also reads messages streamed since the last refresh.
- Send now on a message Claude already held typed it twice: the server did not recognise "[Request interrupted by user for tool use]". Fixed in `claudeInterruptResolution`.
- One app hang at 100% CPU in lazy-stack layout, right after that duplicate briefly re-showed the queued row; not reproduced. The strip spinner no longer uses `withAnimation(.repeatForever)` (now a `TimelineView`). Root cause unproven — residual risk.
- The "Always allow" link was cut mid-path by the pane wrap; now rejoined ("Always allow access to this folder").
- An answered question showed as "Used"; it is now "Asked · <question>".
- Questions read from the transcript had no typed-answer field; it now shows for every Claude question.

## Phase 3 — sheets and menus (implementation notes) — VERIFIED 2026-10-16 (verifier rounds 2–5: all five boards PASS; live walk 15/15)

Files:
- LFGCore (tested): `SessionSheetModel.swift` (subtitle, tiles and badges, Host row, footer, effort short labels), `SubagentRow.swift` (row status, result line, "type · 1m 12s"; `SubagentPill.sheetSummary`), `FilesSheetModel.swift` (Images / Videos / Documents, "folder · age", links). `ChildAgentSession.result`; `PhoneSignInTarget` public init.
- Server: `src/subagents.ts` — each Claude subagent row carries `result`, the first line of its final report (B8); the list keeps its safe-field contract otherwise (the prompt stays behind the child's messages endpoint).
- App: `SessionSheet.swift` (new; replaces the ••• pull-down — the toolbar button now opens it), `SessionDetailView.swift` (sheet case, follow-up after dismissal, S2 Subagents sheet), `AttachmentsSheet.swift` (S2 Files & links), `TerminalScreen.swift` (header, Fit/Wide switch, colours), vendored SwiftTerm patch 4 (`ios/Vendor/SwiftTerm/PATCHES.md`: one scrolling key row with ⌥ and ⌘V), `PhoneSignInView.swift` (review step on the agent path; S2 browser chrome). Debug fixtures `LFG_S2_VIEW_FIXTURE=menu|subagents|files`.

Decisions (Phase 3):
- Sheets are system sheets. iOS 26 draws a partial-height sheet inset at ~96% scale; measurements divide by 0.9602 (memory `ios26-partial-sheet-scales-96`).
- Tiles that cannot act dim in place (Subagents with none, Browser preview without a frame, Terminal while the host is offline); Terminal and Sign in are hidden for sessions another frontend owns, as in the old menu. Stop shows only while the agent works.
- Long values wrap like the board's CSS: the subtitle, and the Host value (which then starts 10pt after "Host").
- Effort segments use the CLI names, falling back to short names only when a model's levels do not fit.
- The footer splits into two copy targets: the tmux name and the session id (the old menu copied each).
- The sign-in agent path now reviews before sending: "I'm signed in" → the domain switches → "Send N cookies"; only switched-on domains go. The review title names the host as the address pill does ("Mac"), not by its URL.
- The session sheet's tile grid stays 96pt below the sheet top as on the board; a wrapped subtitle eats the gap, and only a third line (under 10pt of gap) pushes the grid down (verifier round 2, D1).
- Separators are 0.5pt (board `border-bottom: 0.5px`); the Links tab follows the board: the domain's letter on a 30pt tile, title over domain, an external-link arrow.
- Terminal: the output sits 12pt in from each side and 10pt under the header; the header fills use the colour the canvas draws (#313132), because Chrome renders the board's white-at-12% brighter than SwiftUI blends it. Key labels stay SF Mono Semibold as the CSS declares (Chrome draws them in Menlo Bold).
- Terminal key row: one scrolling row; it scrolls when a swipe starts on a key (`KeyRowScrollView` cancels the key's touch).

## Phase 4 — desktop sessions list — VERIFIED 2026-10-16 (verifier round 3 PASS, all five fold states)

Reference: board `dA2-sessions` (400 × 860 window content), spec dumped to the scratchpad `specs/dA2-sessions.txt`.

Scope (DF1–DF5 + B12), in this order:
1. **B12 server:** `total` on the first page of `GET /api/sessions/resumable`. Counting closed rows needs a lease read per transcript (~3,000 on the Pro), so a background count runs at most once a minute per hidden-folder set and the request returns the cached number (null until the first count lands; old hosts omit it). Pure counting function, tested with injected inputs.
2. **Data (desktop):** decode `prompt` (question, kind) and `task` on live rows; `total` on resumable pages; keep each host's last good snapshot when a fetch fails (DF5) and mark its rows offline.
3. **Window chrome (DF1):** traffic lights, the centred Sessions/Tasks switcher with badges (exists; restyle to the board), a round search button on the right. Gone from the toolbar: the connection bar, the inline search field, the group picker and the "+" (desktop does not create sessions).
4. **Host strip (DF2):** a 30pt row under the toolbar: a dot and name per host (offline: hollow amber ring + "<name> offline"), "· N working", and a "By status" menu on the right (By status / By directory, plus Hidden directories…).
5. **List (DF3):** three collapsible groups: Needs input (paused folds in; oldest first), Working ("by last activity"; newest first), Recent (idle + closed; newest first; count = idle + the hosts' closed total). Child-agent rows leave the list, as on the phone. Directory mode keeps its groups in the same style.
6. **Rows (DF4):** time column ("2m" / "ago", amber / green / grey), title, meta "project · host · agent model · from a task", status line ("Asks: …" with a chat icon, "● Working", "Closed", "Ready for your next message" for idle, "<host> is offline" on a dimmed row). No buttons in rows; click opens (Opener), the context menu keeps every action.
7. **Fixture:** `--window-shot` gets the board's sample (8 rows, Air offline, task badge) so the shot compares 1:1.

Verification: tests (LFGCore, bun incl. the B12 count), desktop build, `--window-shot 400` measured against a board render, a live-data probe on the real hosts, then the visual verifier against `dA2-sessions`.

Implementation notes (2026-10-16):
- Files: `src/resumable-total.ts` (+ test; B12 count and cache) wired into `listResumable`; LFGCore `DesktopSessionList.swift` (+ `DesktopSessionListTests`, groups / lines / ages / meta) and `SessionListRow.swift` are compiled into the Mac app by `desktop/build.sh`; `desktop/SessionsListS2.swift` (colours, glyphs, search button, host strip, group header, row, `SessionItem` facts); `desktop/LFGSessions.swift` (prompt / task / total decoding, DF5 carry-over, `SessionItem.hostOffline`, the S2 list in place of `List`, title bar, `--window-shot --board` and `--live [--refresh-twice s]`).
- Decisions: every group sorts newest first (the board shows 2m above 6m; the menu-bar projection's oldest-first was not carried over). Idle rows say "Ready for your next message" (the phone's copy; the board shows no idle row). An offline host's rows are idle for every count and sit in Recent. Child-agent rows leave the list (as on the phone). "· N working" hides at 0. Hidden directories moved into the "By status" menu. The "Unreachable: …" footer is gone (the host strip says it). The window-shot colours are read after converting its Display P3 profile to sRGB.

## Phase 5 — ship — DONE 2026-10-16

What shipped:

- **Servers.** Pro restarted from the main checkout (S2 fields live), then again for the stream fix (`8aaffc7`). Air: `git reset --mixed origin/main` on the synced tree, the three fix files taken from git because Syncthing had not delivered them after 4.5 minutes (its `serve.ts` matched `7ae892f` byte for byte first), `bun install --frozen-lockfile`, restart by port under `serve-forever.sh`.
- **TestFlight 202610161522** (v1.3.0) from the clean worktree at `7ae892f`. Upload 70 s over Surfshark (utun5, 10.14.x), not LetsVPN. Verify lane: VALID, train 1.3.0 highest, internal IN_BETA_TESTING, IPA bundles Cloudflare Access for both hosts. The iOS code is unchanged since; the fix is server-only.
- **Desktop app** on both Macs at `/Applications/lfg.app`, launched by path. Old bundles: `~/Library/Application Support/lfg-desktop-backups/20261016-s2-sessions/`.

**Bug found by the end-to-end check, and fixed (server, `8aaffc7`).** The first live answer in the S2 app left the question panel up for 40 s, and a later reply never appeared until the session was reopened. The server had delivered every event; the app's stream was connected the whole time. Cause: when the app's saved cursor is too old, `/api/events` sent one `resync` frame and then only heartbeats. The resync branch never subscribed to the journal. The app reads heartbeats as "caught up" and keeps the connection, so busy, prompt and message events after it were lost until the connection dropped. A fresh install or a phone that has not opened the app within the 14-day retention hits it. It predates S2 (`649f3c7`). An old-build comparison first looked like an S2 regression, because that run started from a valid saved cursor. Proof: a stale-cursor curl got 0 events while the head moved 7; a current-cursor control got 11. Fix: `src/events-stream.ts` subscribes from the head it announces, in the same tick. 4 new tests; the resync test fails on the old code. After deploy: stale-cursor probes deliver events on the Pro (95 in 25 s) and on the Air (5, with a session running). A fresh install of the S2 app (RESYNC on both hosts at launch) then cleared an answered question and drew both replies live.

Other observations (pre-existing, not fixed): a new session appears in the app's list only after the 60 s refresh, because the app refreshes for an unknown session's message events but not its prompt or busy events. The scraped preamble above a question can show the agents-md hook line. `GET /api/sessions/resumable` takes 17–21 s on the Pro (about 4,000 transcripts), on later pages too, which do not count the total; the two real-corpus tests timed out the same way before Phase 4.

## Method from Phase 3 on (after Eugene's correction, 2026-10-16)

Phase 2 took 10 verifier rounds because the verifier was my measuring tool. From Phase 3:
1. **Spec from the board's DOM.** `spec-dump.js` (served with the boards) dumps every element's box, type, colour, radius, padding, gap, border, shadow and SVG paths; specs are saved to the scratchpad `specs/<board>.txt` (all five Phase 3 boards done). Where boards disagree, decide once and write it down before building.
2. **CSS line boxes converted explicitly.** `View.cssLineBox(size:lineHeight:)` (Theme.swift) adds the half-leading and line spacing SwiftUI lacks. `line-height: normal` already matches SwiftUI's natural line.
3. **Measure myself to 1pt.** `appmeasure.py` (colour runs, text line tops/bottoms, pixels, in points) on recording frames, at the same reference points as the spec. Every delta written "board X / app Y" before touching code.
4. **One verifier round**, called only when my own measurements already match.

## Verification Evidence

| Phase | Check | Result | Artifact |
| --- | --- | --- | --- |
| P1 | `bun test src/task-origin.test.ts` | 7 pass | — |
| P1 | `swift test` (LFGCore), new suites | 18 pass | `SessionListRowTests.swift` |
| P1 | `swift test` (LFGCore), full | 289 Swift Testing + 644 XCTest pass (1 skipped) | — |
| P1 | `bun test` (full) | 1177 pass, 3 fail — all 3 in `sessions-resumable-closed.test.ts` (5 s timeouts; imports only `sessions.ts`/`leases.ts`, which this branch does not change — pre-existing). `codex-bin` failed once in the full run and passed alone (flaky). | — |
| P1 | Simulator, live data | List renders with host dots, one Search/••• capsule, S2 headers and rows | — |
| P1 | Visual verifier round 1 (`s2-list`) | PARTIAL — header height, tab tint, closed dot, glyphs, Load more | `.claude/evidence/sessions-redesign-s2/phase1-list/` |
| P1 | Visual verifier round 2 | PARTIAL — board glyphs, Tasks glyph, Load more colour | `…/phase1-list-r2/` |
| P1 | Visual verifier round 3 | PARTIAL — Sessions tab glyph, host-dot inset (+8pt), repeat glyph; lower list unverified (simulator evicted mid-run) | `…/phase1-list-r3/evidence.md` |
| P1 | Round 3 fixes | Board-drawn Sessions and repeat glyphs; header leading −4pt | — |
| P1 | Visual verifier round 4 (full board, recordings) | PARTIAL — search/more glyphs ~34% large, chevrons ~1pt large, selected tab fill lighter than the board; capsule height (system), task-row clock time raised as questions | `…/phase1-list-r4/evidence.md` |
| P1 | Round 4 fixes | Board-drawn magnifier, ••• and chevrons; solid #3A3A3C selected tab; ••• ink fixed (rendered grey as a toolbar Menu label) | — |
| P1 | **Visual verifier round 5 (full board)** | **PASS** — every component within 2pt; notes: Tasks badge +1.7pt, "Mark all read" inset +1.3pt, row pitch 87.7 vs 88, Load more's loading label shifts left (app-only polish) | `…/phase1-list-r5/evidence.md` |
| P2 | `swift test` new suites (status line, pill, chip label, strip row, grouper edit split) | 7 + 5 + 4 + 6 + 11 pass | `ios/LFGCore/Tests/LFGCoreTests/` |
| P2 | `bun test src/prompt-kind.test.ts` (B3/B4 from real captures) + related suites | 9 pass; with tmux-prompt, journal, phone-sign-in: 42 pass | — |
| P2 | B5 live probe: `answerPromptWithText` against a real Claude 2.1.280 AskUserQuestion (private tmux socket) | Answer recorded: "Teal, with a second line" | — |
| P2 | `swift test` NeedsInputPanelModel | 6 pass | `NeedsInputPanelModelTests.swift` |
| P2 | `bunx tsc --noEmit` | clean | — |
| P2 | Visual verifier round 1 (7 boards) | PARTIAL — structure, copy, colours, states match; deltas: body text 16 vs 17pt, bubble max width, top scroll edge not opaque, code line pitch 14 vs 16, step spacing, gap above pills, disabled sends dimmed by `.disabled`, strip menu covering its row, permission copy, minor chevrons/spacing/shadows | `…/phase2-view-r1/evidence.md` |
| P2 | Round 1 fixes | 17pt prose on a 24pt line; bubble caps text at 290pt with a `CappedWidth` layout (short bubbles hug); solid top fade (opaque to bar−21, clear by bar+14); 14pt transcript spacing and 1pt clearance (anchor row + spacing = 16); output lines 16pt pitch and clipped; disabled sends use `allowsHitTesting`; strip menu drawn by the app 8pt above the row, right-aligned; "Always allow fastlane in this folder"; board chevrons; panel shadow on its shape only; fixture skips history fetch | — |
| P2 | Visual verifier round 2 | PARTIAL — boards 3, 4, 5 PASS; left: step rows ~4pt low after prose, faint content under the status line, question title-to-body gap, sign-in footnote pitch, send arrow glyph | `…/phase2-view-r2/evidence.md` |
| P2 | Round 2 fixes | Step rows −4pt top / +2pt bottom; scrim opaque to the bar's bottom then its gradient tail over 12pt; question title gap 1pt; sign-in card 59pt and footnote on an 18pt line; drawn send arrow; permission command box 38pt; call rows 29pt apart; fixture queued state shows Files | — |
| P2 | Visual verifier round 3 | FAIL (stricter) — permission, plan, queued PASS; left: text visible behind the pills, gap below the last item (+4 / +14 offline / +6 panel), call rows 30 vs 28, question body too close to title, sign-in card 63 vs 59; I had moved four round-2 values the wrong way (read "board vs app" backwards) | `…/phase2-view-r3/evidence.md` |
| P2 | Round 3 fixes | Solid bottom scrim (transcript cut 10pt above the chrome); no pill row when no pill applies; bottom margin trimmed 4pt (6pt under a panel); call rows 28pt; card input 17pt line; rows/cards at the board's x; question body gap and options; text field 46pt; sign-in card 59pt; bubble text on a 22pt line; composer placeholder 2pt lower; chip after a 22pt paperclip | — |
| P2 | Visual verifier round 4 | FAIL on minor deltas only — tools-group, tools-single, question ×3 PASS; left: offline gap to strip board 24 / app 21.3, sign-in card board 59 / app 61 and bottom inset board 29 / app 26.3, paperclip was the SF symbol, menu pencil (same path, rasterised) | `…/phase2-view-r4/evidence.md` |
| P2 | Round 4 fixes | Bottom trim per chrome (pills 4, panel 6, no pills 1.3); sign-in card 11.8 padding, footnote bottom room, title 25pt line and 5pt gap; board-drawn paperclip | — |
| P2 | Visual verifier round 5 | FAIL on two minor deltas — boards 1, 2, 3, 6 ×3, 7 PASS; left on boards 4/5: strip menu shadow missing (the card's clip cut it off), ⋯ dots half size (board dots also take the 1.8 stroke) | `…/phase2-view-r5/evidence.md` |
| P2 | Round 5 fixes | Menu card unclipped with a second, tighter shadow (strip under the menu measured 33 vs board 32 at its top); ⋯ dots 3.6 units wide | — |
| P2 | Visual verifier round 6 (boards 4, 5) | FAIL — ⋯ dots fixed; the menu shadow overshot (strip top board Δ16 / app Δ36): my extra layer was tuned on a lighter sample spot | `…/phase2-view-r6/evidence.md` |
| P2 | Round 6 fix | Back to the board's single shadow, unclipped; measured at the verifier's spot: strip top Δ16 / bottom Δ4 vs board Δ16 / Δ3 | — |
| P2 | Visual verifier round 7 (boards 4, 5) | FAIL on one 1pt delta — menu card, ⋯ mark and shadow match; composer board 96 / app 95 | `…/phase2-view-r7/evidence.md` |
| P2 | Round 7 fix | Gap under the composer's text field 17 → 18pt; measured composer 96pt, 28pt from the bottom | — |
| P2 | Visual verifier round 8 (boards 1, 4, 5) | FAIL — composer now 96 = 96 and board 4 PASS; two older sub-3pt gaps re-measured at 3x: last step to pills board 19.67 / app 17.33, one-line bubble board 40 / app 39 | `…/phase2-view-r8/evidence.md` |
| P2 | Round 8 fixes | Trim above the pills 4 → 1.7pt; bubble vertical padding 9 → 9.5 (measured 40.0pt) | — |
| P2 | Note | From round 9 the brief states the measurement tolerance explicitly (≤1.5pt is an observation, not a delta); earlier rounds applied a 1.7pt limit implicitly, and passes flipped between 1x and 3x board renders | — |
| P2 | Visual verifier round 9 (all boards, 1.5pt tolerance) | FAIL — boards 1, 4, 5 PASS; card label board 12.67 / app 14.67 (my round-1 padding change, misread); step row after a bubble on the question/sign-in boards (those boards use a 12pt gap, `s2-view` 14pt); break-anywhere wrapping | `…/phase2-view-r9/evidence.md` |
| P2 | Round 9 fix | Card padding back to 10pt top. Accepted: board gap conflict (12 vs 14pt, app follows `s2-view`), word wrapping in the card input | — |
| P2 | Self-check (new method, 2026-10-16) | Board specs from the DOM, boards at 3x, same script on both images; all boards within 1pt or explained by board conflicts A/B; fixed bubble gap and card input line box | `…/phase2-selfcheck/selfcheck.md` |
| P2 | Visual verifier round 11 | FAIL — colours/styles my self-check skipped: prose ink, dimmed last preview line, pills clip edge, panel gap, call-row pitch (all fixed, then self-measured) | `…/phase2-view-r11/evidence.md` |
| P2 | Visual verifier round 12 | FAIL — titles/menu/panel/option text must be pure white (only prose, pills, secondary buttons are #F2F2F7); sign-in footnote gap (fixed, self-measured against the clock's white) | `…/phase2-view-r12/evidence.md` |
| P2 | Visual verifier round 13 | Boards 1, 2, 3, 5, 6 (×3), 7 **PASS**; board 4 FAIL on a step row directly under a step (pitch 34 vs 36) | `…/phase2-view-r13/evidence.md` |
| P2 | **Visual verifier round 14 (boards 3, 4)** | **PASS** — step pair 36.0 = 36.0; strip, menu, card, composer within tolerance | `…/phase2-view-r14/evidence.md` |
| P2 | **Live checks on throwaway Claude sessions (SC7, SC8, SC9 ×3 kinds, SC10)** | **PASS** after 7 fixes — Stop, mid-turn strip, menu at the row, Send now (one delivery), offline Edit/Remove/auto-send, Not sent + Retry/Delete (seeded outbox row), permission Allow/Deny, option tap, plan Approve, typed answer | `…/phase2-live/live-checks.md` |
| P2 | Tests after the fixes | LFGCore 333 Swift Testing + 644 XCTest pass; bun 1197 pass, 3 known failures (2 resumable-closed timeouts, flaky codex-bin) | — |
| P3 | Self-check, session sheet (`s2-menu`) | All positions within 1.2pt after converting the 0.96 sheet scale | `…/phase3-menu-selfcheck/selfcheck.md` |
| P3 | Visual verifier round 1 (`s2-menu`) | FAIL on one data-dependent delta: the long real host name truncated where the board's CSS wraps | `…/phase3-menu-r1/evidence.md` |
| P3 | Self-check after round 1 + Subagents + Files | Subtitle and Host value wrap; Subagents and Files rows within 0.8pt | `…/phase3-sheets-selfcheck/selfcheck.md` |
| P3 | Visual verifier round 2 (`s2-menu` long host, `s2-subagents`, `s2-files`) | Subagents PASS, Files PASS; session sheet FAIL: grid flowed 17pt under a wrapped subtitle (board pins it at 96). Notes: Links tab not built to the board, 0.5pt separators | `…/phase3-sheets-r2/evidence.md` |
| P3 | Live walk on a throwaway session (SC12, 15 actions) | PASS: rename, terminal (⌥ latch, Fit/Wide, key-row scroll, ⌘V), files, subagents with a real subagent and its result, sign-in requests, browser preview dimmed, iPhone preview, model, effort, host info, mark unread, stop, end (tmux session gone), copy. Fork reached the server and was refused 409 (prod also claims the synced transcript: rig artifact) | `…/phase3-live/live-checks.md` |
| P3 | Self-check before round 3 | Round-2 fixes measured (grid 96.3/96.5, Links tab within 0.6pt of the spec, separators); sign-in browser fixed (pill lines, 8pt above the bottom bar, error placement, review title) and SC11 review step on the fixture; terminal header and keys measured, fill and output insets fixed | `…/phase3-r3-selfcheck/selfcheck.md` |
| P3 | Visual verifier round 3 (all five boards) | Session sheet, Subagents, Files & links (both tabs) **PASS**; terminal FAIL: type 13 vs 12pt and line 1.22 vs 1.45, Wide scrolled a 120-column grid instead of shrinking the type, blinking cell-sized caret, an extra "-" key; sign-in FAIL: disabled arrows faded the button fill | `…/phase3-r3/evidence.md` |
| P3 | Round 3 fixes, self-measured | SwiftTerm patch 5 (CSS line height, centred text and caret); 12pt Fit / 10.5pt Wide on 1.45 rows; steady #D1D1D6 block; rows sit on the bottom edge (last row 10.3pt above the keys); "-" removed; sign-in arrows dim only their ink | `…/phase3-r4-selfcheck/selfcheck.md` |
| P3 | Visual verifier round 4 (terminal Fit + Wide, sign-in) | Sign-in **PASS**; terminal FAIL on one glyph: the keyboard key was an SF Symbol (board draws its own, 20 × 15.3). All round-3 terminal findings confirmed fixed | `…/phase3-r4/evidence.md` |
| P3 | Round 4 fixes, self-measured | Board-drawn keyboard icon (20.0 × 15.33); the key hides/shows the keyboard with the board's labels, row at the board's height when hidden (840 / 840); 0.5pt row border; sign-in arrows keep `.disabled` with a non-fading style | `…/phase3-r4-selfcheck/selfcheck.md` |
| P3 | **Visual verifier round 5 (terminal Fit/Wide × keyboard up/hidden, sign-in)** | **PASS** — nothing above 1.5pt. Observations: SF Mono vs Menlo widths and arrows (accepted), hidden key row 1.0pt high, "I'm signed in" label 6pt narrower (SF Pro). Not exercised: ctrl latch, review and result sheets (do-not-tap). With rounds 2–4 every Phase 3 board has passed | `…/phase3-r5/evidence.md` |
| P3 | Tests after Phase 3 fixes | LFGCore 348 Swift Testing + 644 XCTest pass; bun subagents / sessions-last-user-at / sendq-delivery-policy 48 pass | — |
| Merge | `main` (`2672dad`) into this branch | 5 conflicts, all additive (Models/SessionStore `task` + `purpose`; serve.ts origins then edit-chat tags; RootView: S2 dock + Sessions badge, main's Tasks badge count; improvement log). tsc clean; LFGCore 408 Swift Testing + 644 XCTest; iOS build green; bun 1230 pass after rewriting the 2 menu-safety tests for the S2 options button (`src/ios-session-menu-threading.test.ts`); remaining failures: 2 known resumable-closed timeouts, codexBin (a newer Homebrew/npm codex 0.159.2 is installed on this Mac). Smoke on the simulator against the real hosts: list, Tasks tab (main's A2) in the S2 dock, a real Codex session view | — |
| P4 | Self-check (`dA2-sessions`, board fixture, 1x) | Separators identical; every element within 1pt except two 1x rounding cases (≤2pt); colours within 2 levels in sRGB; B12 total 3,982 live; DF5 probe keeps Air's row offline; a live click collapses and expands Recent; LFGCore 414 + 644, desktop feature tests 183, bun 1234 (2 known timeouts), iOS build green | `…/phase4-selfcheck/selfcheck.md` |
| P4 | Visual verifier round 1 (`dA2-sessions`) | FAIL on one fix: the time column lacked tabular digits ("1m", "1d" 3pt off the column). Raised: a hairline under the title bar (off-screen inactive render only), native window buttons vs the board's drawn ones, collapsed state not checkable | `…/phase4-r1/evidence.md` |
| P4 | Round 1 fixes | Tabular digits (every unit letter at x=26, as on the board); title-bar separator off (on screen, active and inactive: one surface, no line); `--window-shot --collapse <groups>` (Working collapsed: separators 421/496 vs board 420/496); native window buttons kept | `…/phase4-r1-fixes/checks.txt` |
| P4 | Visual verifier round 2 (open + every fold state) | FAIL on one delta: the Working hint "by last activity" stayed when the group folded (the board hides it). Round-1 fixes confirmed; title-bar line only in the off-screen render | `…/phase4-r2/evidence.md` |
| P4 | Round 2 fix | The hint shows only while Working is open (open: ink 290–299 vs board 289–299; folded and all-folded: none) | — |
| P4 | **Visual verifier round 3 (open + each fold + all folded)** | **PASS** after closing two gaps with captures of the current build: on screen the title bar is the board's #1A1A1E with no line (active and inactive); a real click folds Working (chevron ›, hint and rows gone) and a second click restores it byte-identically. Remaining observations ≤1.5pt (1x rounding, SF widths) | `…/phase4-r3/evidence.md`, `…/phase4-r3-gaps/` |
| P5 | Deploy + TestFlight | Pro and Air servers on `8aaffc7`; TestFlight 202610161522 VALID, internal IN_BETA_TESTING; desktop installed on both Macs | `ios/fastlane/deploy-202610161522.log`, `verify-202610161522.log` (worktree) |
| P5 | End-to-end answer + send (before the fix) | Answer delivered (server got it at once) but the panel stayed 40 s; reply "received" never drew until reopen. Old build on a valid cursor drew its reply in ~1 s | `…/phase5-e2e/` (`answer-and-send.mov`, `send-strip.png`, `base-send-strip.png`) |
| P5 | Stream fix proof | Stale cursor before: resync + 0 rows while head moved 7; control: 11 rows. After: Pro 95 rows, Air 5 rows (head moved) | commit `8aaffc7`, `src/events-stream.test.ts` |
| P5 | End-to-end answer + send (after the fix, fresh install) | RESYNC on both hosts at launch; answering cleared the panel and drew "You picked Autumn."; the reply "fourth" drew live without reopening | `…/phase5-e2e/fixed-answer-and-send.mov`, `fixed-after-answer.jpg`, `fixed-after-send.jpg` |
| P5 | **Independent audit (verification-auditor)** | **PASS** on all six checks: both servers started after `8aaffc7` with matching `events-stream.ts`; SC1 live (26 rows with `lastUserAt`, 8 task rows matching their run records, `total` 3,990); stale-cursor streams on both hosts delivered the same events as a control stream over 10–15 min; TestFlight VALID / IN_BETA_TESTING; desktop signed and running on both Macs with S2 code; clean-copy bun 1,240/1,240 and LFGCore green. Its own scope excluded sends, so the live send + answer evidence is the row above | `…/phase5-audit/evidence.md` |
| P5 | Suites at `8aaffc7` | bun 1,240 (2 slow real-corpus tests need `--timeout 60000`; they fail the same way before Phase 4), LFGCore 644 XCTest + 415 Swift Testing | — |

## Bugs

Fixed during the Phase 2 live checks: see the list under Phase 2. Open, pre-existing (logged, not in S2 scope):
- The scraped preamble above a question can include pane chrome (spinner lines, a tip, the tail of the user's prompt). Server `contextAbovePrompt`.
- The pane path misses the question's "☐ Header" chip, so the label reads "Claude is asking" without the header.
- A deep link to a session the app has not listed yet waits for the 60s refresh ("Opening session…").
- An interrupt renders as a user bubble "[Request interrupted by user for tool use]".
- Residual: the one-off layout hang (see Phase 2 notes).
