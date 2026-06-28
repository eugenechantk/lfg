# lfg — Web App Feature Document

> Scope: every feature exposed through the **web app** (the Vite/React PWA in
> `web/`, served by `lfg serve`). Backend/CLI features are included only where
> the web UI drives them. Grounded in `web/src/App.tsx`, `src/commands/serve.ts`,
> and the captured screens in [`.claude/web-screen-captures/`](./web-screen-captures/).

---

## 1. Overview

lfg's web app is **mission control for self-hosted AI coding agents**. It lists
and streams live agent sessions, lets you start/steer/answer them from any
device, runs scheduled "insight" agents, and gives raw terminal access — all
over a single Bun server reachable privately over Tailscale.

- **Installable PWA** — manifest + service worker; installs to a phone home
  screen and runs standalone.
- **Two themes** — light and dark (OLED true-black), user-toggled from the header.
- **Responsive** — phone = single stacked column; ≥1024px (iPad landscape /
  desktop) = a session **rail + tiled stage** workspace.
- **Native-feeling** — haptic feedback (`web-haptics`), bottom sheets/drawers
  (vaul), pull interactions, hold-to-dictate.
- **Three primary tabs + extensions** — Live · Auto · Term, plus any nav tabs
  contributed by runtime extensions.

---

## 2. App shell & navigation

| Feature | Detail |
|---|---|
| **Tab bar** | Floating pill nav: **Live**, **Auto**, **Term** (+ extension tabs). |
| **New-session FAB** | Blue "+" next to the nav. **Tap** opens the composer; **hold** to dictate a session by voice. |
| **Header** | App title; on Live, a **user filter**; a **theme toggle** (sun/moon). |
| **Loading skeleton** | `AppShellSkeleton` renders while the first session list loads. |
| **Error boundary** | Recoverable full-screen message instead of a blank page if a view throws. |
| **Extension nav tabs** | `LFG_EXTENSIONS` bundles can `registerExtension(...)` to add bottom-nav tabs and UI. No extensions → clean core. |

*Screens: `01-live-empty-light`, `12-live-list-dark`.*

---

## 3. Live — session management

The core surface. Lists live sessions, streams each transcript, and exposes the
full steering loop.

### 3.1 Creating sessions
*Screens: `05-new-session-drawer-light`, `06-new-session-composer-filled`, `07-new-session-agent-picker`, `13-new-session-drawer-dark`.*

- **Task field** — free-text prompt for the new session.
- **Agent family picker** — switch between **CLI** and **ai-sdk** backends, and
  choose **claude / codex / opencode**.
- **Model picker** — model list adapts to the agent (e.g. opus/sonnet/haiku/fable
  for Claude; gpt-5.5/5.4/… for Codex).
- **Repo picker** — populated by scanning `LFG_REPOS_ROOT` for git repos
  (`/api/repos`).
- **Owner picker** — assign the session to a user from `LFG_USERS`.
- **Voice dictation** — mic in the composer; hold-to-dictate from the FAB.
- **Start** — spins up a detached tmux session lfg owns end-to-end.
- **Claude usage readout** — 5-hour + 7-day utilization shown in the composer
  (via the OAuth usage endpoint, cached ~60s).

### 3.2 Resuming sessions
*Screen: `14-resume-recent-session`.*

- **Resume a recent session** — expandable list of resumable/closed sessions
  (`claude --resume`), each showing repo + relative time. Reopen a past session
  with its full context.

### 3.3 The live list
*Screens: `02-session-connecting`, `03-live-list-multi-light`.*

- **State grouping** — sessions grouped by status (Idle / Working / needs-input),
  with a count per group.
- **Session card** — agent icon, clipped title, **model badge**, **live status
  dot**, and a **⋯ menu**.
- **Streamed transcript (SSE)** via `/api/live/stream` and per-session
  `/messages`:
  - Markdown rendering — headings, lists, inline `code`, block quotes.
  - **Collapsible tool-call groups** — e.g. "3 Read · 3 Bash · 6 results".
  - **Tables** with **copy / download / view-fullscreen** controls.
  - **Tool lines** and **message bubbles** for user/assistant turns.
  - **"Actions:" footer** summarizing what the turn changed.
- **Connecting state** — "Connecting to live transcript…" until the stream binds.

### 3.4 Steering a session
- **Message composer** — send a follow-up turn (`/send`); **voice dictation**
  available. With auto-submit, a dictated transcript can send itself.
- **Message queue** (`QueuePanel`) — outbound messages show **confirmed-delivery
  status** and can be **retried**; tracked over the `queue` SSE event.
- **Interactive prompt panel** (`PromptPanel`, `/answer`) — when an agent raises a
  **permission / plan-approval / trust dialog / AskUserQuestion**, it surfaces as
  a **question header + tappable option rows** (each option a title + one-line
  description), plus "type your own" / "chat about this". *(Renders when lfg runs
  on Linux; see §9.)*
- **Mid-session model switch** (`/model`) — change the model for the rest of the
  session; a re-read-history confirmation surfaces in the prompt panel.
- **Rename** (`SessionTitleSheet`, `/title`) — edit a session's title via a bottom
  sheet that shares the send pipeline.

### 3.5 Session menu & lifecycle
*Screen: `04-session-menu`.*

- **Assign to** — Unassigned / any `LFG_USERS` member (`/user`); tag survives
  session-id rotation.
- **Stop** — interrupt the running turn.
- **End session** — close the session (`/close`); lfg handles the
  lingering-process grace window so it doesn't flicker back.
- **Paused banner** (`PausedBanner`) — when a session is **blocked**, an inline
  warning explains why and offers a fix:
  - *model unavailable* → **"Resume on Opus"** one-click relaunch (respawns the
    pane on a working model);
  - *out of credits* → explains and prompts to top up.

### 3.6 Multi-user
*Header control on Live.*

- **User filter** (`UserFilterMenu`) — All / Unassigned / per-user; filters the
  live list by owner. Driven by `LFG_USERS` and `/api/users`.

---

## 4. Wide-screen workspace (iPad landscape / desktop)
*Screens: `16-wide-railstage-dark`, `17-wide-railstage-light`.*

At ≥1024px the Live view becomes a **rail + stage** (`RailStage`, `RailGroup`):

- **Session rail** (left) — compact, groupable session list; collapsible (`\`).
- **Tiled stage** (right) — open a session in a **preview column**; **pin**
  multiple sessions side by side into columns.
- **Keyboard-driven** — vim-style: `j`/`k` move, `Enter`/`o` open, `p` pin, `x`
  close column, `Esc` clear, `?` shortcuts help (`ShortcutsHelp`), `\` toggle
  rail. Cursor auto-scrolls into view.

---

## 5. Auto — scheduled insight agents
*Screens: `08-auto-agents-empty-light`, `09-auto-agent-editor`, `10-auto-agent-editor-cron`, `15-auto-agents-empty-dark`.*

A pluggable engine for **Markdown agents** that run on a schedule, gather their
own context, and emit a report + actionable follow-ups (`AutoManageView`,
`/api/auto/*`, `/api/agents`).

- **Empty state** — "it's just a prompt and a schedule" + **New auto agent**.
- **Agent editor sheet** (`AgentEditorSheet`):
  - **Name**.
  - **Schedule** — simple ("Every day at 9:00 AM", with next-run preview in the
    box's timezone) or **Advanced (cron)** expression.
  - **Based in (repo)** — which repo the agent runs against.
  - **Enabled** toggle.
  - **Prompt** — "the entire agent": describe what to watch for and what to flag;
    runs as a real read-only Claude session.
- **Inputs / collectors** (declared in agent frontmatter): `git_log`,
  `repo_files`, `github_issues`, `github_prs`, `openrouter_models`,
  `security_scan`.
- **Findings** (`FindingSheet`, `AutoFindingCard`, `/api/auto/findings`) —
  produced findings surfaced as cards/sheets.
- **Reports** (`/api/reports/<date>`) — dated reports browsable in the UI.
- **Actions panel** (`ActionsPanel`, `/api/actions/execute`,
  `/execute-combined`) — execute a report's **action blocks** (single or
  combined) to turn an insight into a follow-up session/command.
- **Shipped examples** — `model-watch`, `repo-review`.

---

## 6. Term — embedded terminal
*Screen: `11-terminal`.*

- **Full web terminal** (`TermView`, `/api/term`) — a PTY over WebSocket attached
  to a tmux session ("terminal · main · open").
- **Mobile key toolbar** — Esc, Tab, ^C, arrow keys, Enter.
- **Paste** button.
- **Scan** (`/api/term/scan`) for terminal discovery.

> Note: the embedded terminal holds a PTY websocket on the single-process server;
> capture/use it last in heavy multi-session sessions.

---

## 7. Voice
- **Dictation** in the composer and **hold-to-dictate** from the FAB
  (`MicButton`, `createVoiceSession`).
- **TTS / STT proxy** (`/api/voice/tts`, `/api/voice/stt`) — optional
  self-hosted voice via `TTS_UPSTREAM` / `TTS_TOKEN`.
- **Speaker identification** (`/api/voice/identify`).
- **Auto-submit** — a finished dictation can route straight to the agent instead
  of just filling the box.

---

## 8. Cross-cutting UX primitives (design-relevant)
- **Themes** — light + dark, persisted; both shipped.
- **Haptics** — imperative haptic feedback on key interactions.
- **Bottom sheets / drawers** — new-session composer, finding sheet, agent
  editor, title editor (vaul `Drawer` + `BottomSheet`).
- **PWA** — manifest, service worker, installable, standalone, offline shell.
- **Pills, badges, status dots, skeletons** — consistent design-system
  components (`web/src/components/ui/*`, incl. a "dotmatrix" motif).
- **Live status** — green dot = live; model badge per card; group counts.

---

## 9. Known constraint — interactive prompt panel on macOS
The **needs-input / prompt-action panel** (§3.4) only renders when lfg's session
enumeration can see CLI/tmux sessions. `listSessions` (`src/sessions.ts`) reads
**Linux `/proc/<pid>/cwd`**, so on **macOS** CLI sessions aren't enumerated and
only control-plane ai-sdk sessions list — and the ai-sdk backend writes an
AskUserQuestion as plain transcript text rather than a blocking prompt. To see /
capture the tappable prompt panel, run lfg on **Linux** (its intended VPS home).

---

## 10. Screen ↔ feature cross-reference

| Screen file | Feature section |
|---|---|
| `01-live-empty-light` | §2 shell, §3 Live empty |
| `02-session-connecting` | §3.3 connecting state |
| `03-live-list-multi-light` | §3.3 live list + transcript |
| `04-session-menu` | §3.5 session menu |
| `05-new-session-drawer-light` / `06` / `07` | §3.1 create session |
| `08-auto-agents-empty-light` / `15` | §5 Auto empty |
| `09-auto-agent-editor` / `10-...-cron` | §5 agent editor + cron |
| `11-terminal` | §6 Term |
| `12-live-list-dark` / `13-new-session-drawer-dark` | §2 themes |
| `14-resume-recent-session` | §3.2 resume |
| `16-wide-railstage-dark` / `17-...-light` | §4 wide workspace |

*Not yet captured (needs Linux host): the interactive prompt-action panel (§9),
the auto-agent findings sheet, and the report/actions panel.*
