# lfg web frontend — screen captures (basis for iOS app design)

Captured by driving the real lfg web PWA (`bun run serve` → `http://127.0.0.1:8766`)
with multiple live agent sessions running. Mobile shots are at an **iPhone
viewport (393×852)**; wide shots at **iPad-landscape (1366×1024)**.

Setup used: `LFG_REPOS_ROOT=~/dev/personal`, `LFG_USERS=eugene,benny`, sessions
spawned across repos (`lfg`, `dinonuggets`) on claude (sonnet) and codex (gpt-5.5).

## Index

| # | File | Screen / state |
|---|------|----------------|
| 01 | `01-live-empty-light.png` | **Live** tab, empty state — "No running sessions", New session CTA, bottom pill nav (Live/Auto/Term) + FAB |
| 02 | `02-session-connecting.png` | A session card right after creation — "Connecting to live transcript…", message composer |
| 03 | `03-live-list-multi-light.png` | **Live list with multiple sessions** — grouped by state ("Idle 3"), per-card agent icon + title + model badge (sonnet / gpt-5.5) + status dot + ⋯ menu, rendered transcript (markdown, code spans, collapsible tool groups, "Actions:" footer) |
| 04 | `04-session-menu.png` | Per-session ⋯ menu — Assign to (Unassigned/eugene/benny), Stop, End session |
| 05 | `05-new-session-drawer-light.png` | **New session** bottom drawer — task field, agent picker, model/repo/owner pickers, Resume, Start |
| 06 | `06-new-session-composer-filled.png` | New session drawer with a task typed in |
| 07 | `07-new-session-agent-picker.png` | New session — **agent-family picker expanded** (CLI vs ai-sdk: claude / codex / opencode) |
| 08 | `08-auto-agents-empty-light.png` | **Auto agents** tab, empty state — "it's just a prompt and a schedule", New auto agent |
| 09 | `09-auto-agent-editor.png` | **Auto agent editor** sheet — name, Schedule (Every day / time), Based-in repo, Enabled toggle, Prompt field |
| 10 | `10-auto-agent-editor-cron.png` | Auto agent editor — **Advanced (cron)** schedule mode |
| 11 | `11-terminal.png` | **Terminal** tab — embedded shell ("terminal · main · open") with key toolbar (Esc/Tab/^C/arrows/Enter) + Paste |
| 12 | `12-live-list-dark.png` | Live list — **dark mode** (true-black). Note: top card shows a session awaiting the user's reply ("Which one?") rendered inline |
| 13 | `13-new-session-drawer-dark.png` | New session drawer — dark mode |
| 14 | `14-resume-recent-session.png` | New session → **Resume a recent session** expanded — list of resumable past sessions with repo + relative time |
| 15 | `15-auto-agents-empty-dark.png` | Auto agents empty — dark mode |
| 16 | `16-wide-railstage-dark.png` | **Wide layout (iPad landscape)** — session rail (left) + tiled transcript stage (right), dark |
| 17 | `17-wide-railstage-light.png` | Wide layout — light |

## Design-relevant notes
- **Two themes**: light (off-white surfaces, blue accent) and dark (OLED true-black). Both shipped; capture both.
- **Three primary tabs**: Live · Auto · Term, in a floating pill nav with a blue "+" FAB beside it.
- **Session card anatomy**: agent icon · clipped title · model badge · live status dot · ⋯ menu · streamed transcript · message composer (text + mic + send).
- **Transcript rendering** is rich: markdown headings, lists, tables (with copy/download/fullscreen), inline `code`, collapsible tool-call groups ("3 Read · 3 Bash · 6 results"), and an "Actions:" summary footer.
- **Responsive**: phone = single-column stacked cards; ≥1024px (iPad landscape) = rail + multi-column stage.

## Known gap — the "needs input" / prompt-action panel (NOT captured)
lfg surfaces an agent's interactive prompt (AskUserQuestion / plan-approval /
trust dialog) as a **tappable action panel** in the session card. I could not
reproduce it as a UI screenshot **on this macOS host** because:
- lfg's session enumeration (`src/sessions.ts` `listSessions`) reads
  **`/proc/<pid>/cwd`** — Linux-only. macOS has no `/proc`, so CLI/tmux claude
  sessions (the ones that produce the interactive selector) are **not
  enumerated**; only control-plane **ai-sdk** sessions list.
- The ai-sdk backend does **not** surface `AskUserQuestion` as a blocking prompt
  — the agent just writes the question as transcript text (see shot 12).

The interaction is real; it just needs lfg running on **Linux** (a VPS) to render.
What the panel would contain, captured directly from the agent's tmux pane:

```
 ☐ API style
Which API style should we use for the new API?
❯ 1. REST      — Standard HTTP endpoints…
  2. GraphQL   — Single endpoint with a query language…
  3. REST + GraphQL — …
  4. Type something.
  5. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
```

For the iOS design, treat this as: a card-embedded **question header + a vertical
list of tappable option rows** (each with a title + one-line description), plus
"type your own" and "chat about this" affordances. To capture it as a real
screenshot, re-run this exercise with lfg deployed on a Linux box.
