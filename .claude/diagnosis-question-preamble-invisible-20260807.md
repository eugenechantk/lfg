# The assistant's text before a question is invisible until the question is answered

**Date:** 2026-08-07 · **Host:** eugenes-macbook-pro-2 · **Status:** root-caused + fixed

## Symptom (reported repeatedly)

> "When Claude Code asks a question, the response before the question is cut off and not
> visible to the iOS client. It only appears after the question is answered — but that last
> response often contains the most important information needed to answer."

## Root cause — TWO independent bugs

There were two, which is why single fixes kept half-working. **Bug A** truncated the preamble;
**bug B** hid the whole panel. Both had to go.

---

# Bug A — the preamble was scraped from a 24-row pane

### 1. Claude Code does not flush the turn containing an interactive tool

Verified live. A test session (`f191b4c4`) was parked at a real `AskUserQuestion`. At that
moment:

- the tmux pane showed the full two-paragraph preamble + the selector;
- `GET /api/sessions/:id/messages?full=1&limit=5000` returned **only the user message**;
- the raw `~/.claude/projects/.../f191b4c4….jsonl` contained **no assistant line at all**
  (`last-prompt`, `mode`, `attachment`, one `user` — nothing else);
- `grep -rl "translation layer" ~/.claude` (a phrase unique to the assistant's prose) matched
  **nothing on disk**.

So while a question is live the prose exists only in Claude Code's memory and in the pane.
This is upstream behaviour lfg cannot change, and it is *specific to interactive tools*: a
normal `Bash` tool_use flushes its text block immediately (measured — text landed 22s before
the tool returned), which is why only questions show the symptom.

The existing mitigation was right in principle: `PanePrompt.context` (`src/tmux.ts`) scrapes
the prose above the selector and `PromptPanelView` (`ios/LFG/Components.swift`) renders it.

### 2. …but the pane it scrapes is only 24 rows, and there is no scrollback

That mitigation was being starved of input.

```
tmux display-message -p '#{alternate_on} #{history_size} #{pane_height}'
→ 1  hist=0  h=24
```

`tmux new-session` was called with no `-x`/`-y` anywhere in `src/tmux.ts` (5 call sites), so
every lfg pane was tmux's default **80x24**. Claude Code runs in the **alternate screen**, so
`history_size` is 0 and `capture-pane -S -500` returns exactly the same 24 rows as a plain
capture — the scrollback trick is unavailable.

A two-paragraph preamble is ~16 wrapped rows and the AskUserQuestion selector box is ~14, so
the top of the turn — including the `⏺` bullet `contextAbovePrompt` keys off — had already
scrolled out of existence. The scrape therefore returned a **mid-sentence fragment**:

```
context = 'migration is hard to reverse, so a wrong guess about the shape is expensive to
           undo later.\n\nOPTION BETA keeps both shapes alive behind…'
```

Literally "cut off". And in the more common case the fallback refuses to guess (it cannot tell
a bullet-less block from the user's own prompt) and returns `undefined` — which is why a scan
of ~50 journaled prompts showed `context = null` for nearly all of them.

## Fix

Make the pane big enough to hold a whole turn, and keep it that way.

1. **Create every lfg-owned tmux session at `-x 120 -y 200`** (all 5 `new-session` call sites:
   claude agent, managed claude, codex, aisdk, codex-aisdk/opencode). tmux records this as the
   session's `default-size`, so it persists for a detached session. Capture cost barely moves —
   `capture-pane` emits blank rows as empty strings, so a 120-row pane of the same content is
   3.5 KB vs 2 KB at 24 rows.

2. **Reconcile the size continuously** (`ensurePaneRows`). Measured trap: after a client
   attaches and detaches, tmux does **not** restore `default-size` —

   ```
   before: w=200 h=60 → during attach: w=80 h=23 → after detach: w=80 h=23
   ```

   so one visit to the Terminal tab or an `iTerm` attach would silently re-break this forever.
   That is almost certainly why earlier fixes appeared to work and then regressed. The pump
   now notices a short pane for free (a capture returns exactly `pane_height` lines) and
   resizes it — but only when no client is attached, so a human's terminal is never yanked.

3. **Raise `contextAbovePrompt`'s 40-line scan cap** to 400. Without this the taller pane buys
   nothing past 40 rows.

4. **Retro-fix live sessions** on pump adoption, so existing sessions get the size too rather
   than only ones created after the deploy.

## Verification (live, before any code was written)

Resized the parked test session's window and re-ran the real parser against the real pane:

```
h=24  → context = 'migration is hard to reverse, …'     (466 chars, starts mid-sentence)
h=120 → context = 'OPTION ALPHA front-loads the cost: …' (834 chars, starts at the beginning)
```

and the pump journaled the grown context through to clients:

```
15:31:48  len(ctx)=466  'migration is hard to reverse, so a wrong guess about the shape is expe'
15:35:01  len(ctx)=834  'OPTION ALPHA front-loads the cost: it demands a full schema migration '
```

---

# Bug B — a prompt asserted before the client connected was never re-stated

Found only because the simulator was actually driven. With bug A fixed and the pump journaling a
complete 1,259-char context, a freshly-launched client opening the parked session still showed
**"Running", no panel, and only the user bubble** — the exact reported symptom, now with no
truncation left to blame.

Prompt state reached clients **only** as a journal `prompt` event. That event is a *delta*, and a
client's cursor starts at the journal head (`/api/events/page?since=0` answers `canServe: false` —
history is pruned). So any client that connects, is installed, is force-quit and relaunched, or has
its cursor pruned **after** the question was asked never receives it. And `/api/sessions` carried no
`prompt` key at all:

```
keys: [agent, assignedUser, busy, cmd, cwd, last, lastActivityAt, lastUserText, managed,
       model, pid, project, sessionId, startedAt, status, statusDetail, statusReason,
       title, tmuxName, tmuxTarget, transcriptPath]        ← no prompt
```

There was therefore no baseline to recover from, and no transcript copy either. This is exactly the
class of bug `busyStatedAt` was introduced to fix for `busy` (see
`.claude/diagnosis-codex-stuck-running-20260806.md`) — `prompt` never got the same treatment.

**Fix.** `/api/sessions` now carries `prompt`, read from the pump's last durable statement via
`Journal.latestPrompt` (one indexed row per session — re-scraping panes per caller would not be
affordable). `Session.prompt` decodes it leniently, and `SessionStore.refresh` seeds `prompts[sid]`
from it under the same `JournalFreshness` arbitration `busy` uses, with a new `promptStatedAt` so a
fresh journal event still out-votes the snapshot.

## Verification — the real client, on the real seam

Same live parked session, same server, only the build differs.

| | before | after |
|---|---|---|
| list group | **Working** | **Needs you** |
| detail view | user bubble only, no panel | panel with the complete preamble |
| first words shown | *(nothing)* | `PARAGRAPH-ONE-STARTS-HERE …` |

Evidence: `.claude/evidence/question-preamble-20260807/` — `before-no-panel.png`,
`after-list-needs-you.png`, `after-panel-full-context.png`, `after-panel-top.png`.

Throughout, the transcript endpoint returned **only the user message** and the prose matched nothing
under `~/.claude` — so the panel was demonstrably the only possible source.

---

# Follow-up — the preamble renders as prose, not as panel chrome

Eugene, on seeing the fix: *"Is it not possible to render the prose before the question as regular
response text, rather than being in the need-input box?"* Right call. It **is** the model answering —
usually the reasoning you need in order to choose. Inside the card it read as a caption on a form,
got the panel's flat `.subheadline`, and sat visually subordinate to the options it exists to
explain.

`prompt.context` is now synthesized into an ordinary assistant turn (`PromptPreamble` in `LFGCore`)
and rendered through the normal `TranscriptMessageView` immediately above the panel. Same markdown,
typography and media handling as any other turn; the thread reads continuously into the question,
and the panel shrinks to just the question and its options.

The one hazard is the handover. On answering, Claude flushes the real turn and the server clears the
prompt as **two independent events in no guaranteed order**, so a naive synthesis shows the prose
twice for the interval between them. `PromptPreamble.shouldSynthesize` stands the synthetic turn
down as soon as the real one is in the transcript tail, comparing whitespace-normalized (the scrape
rejoins the pane's hard wrap, so it can never match byte-for-byte) and by containment (the real turn
is a superset whenever the pane clipped its top). Verified by answering in the app: exactly one copy,
no flicker.

**Known fidelity gap.** `capture-pane` reads the TUI's *rendered* output, so markup is already
flattened — the live preamble is plain text even where the model wrote `**bold**` or `` `code` ``.
When the answer lands, the flushed turn replaces it with correctly formatted markdown. Same words,
richer rendering afterwards. Visible in `handover-no-duplicate.png` (`lru-cache` as inline code,
**more than one instance** in bold) versus `preamble-as-normal-prose.png`. Recovering markup live
would mean capturing with `-e` and parsing ANSI back into markdown — not worth it.

## Residual limit (honest)

The preamble is still bounded by the pane — a turn longer than ~200 rows (~1,600 words) before
a question will still be clipped at the top. There is no other source while the question is
live: the text is not on disk anywhere. The full turn always appears as a normal transcript
bubble the moment the question is answered.
