# Why the question-preamble fix didn't work, and the fix that does

**Date:** 2026-08-09 · **Host:** eugenes-macbook-pro-2 · **Status:** root-caused + fixed + verified live
**Prior round:** `.claude/diagnosis-question-preamble-invisible-20260807.md`

Third report of the same symptom. The 2026-08-07 fix was verified against a session I created
through the lfg API — **which is not the kind of session Eugene uses.** That is the whole story.

## The reported session: `cy-222428-68989`

```
tmux display-message -t cy-222428-68989 '#{window_width} #{window_height} #{session_attached}'
→ w=78  h=60  attached=1
```

Every one of its 28 journaled prompt events carried `context` of length **0**.

## Why the 2026-08-07 fix could never have applied

Both halves of it miss this session class, for independent reasons.

1. **`paneSizeArgs()` never ran.** `cy-*` sessions are not created by lfg. They come from Eugene's
   own shell function (`~/.zshrc:173`):

   ```sh
   _lfg_tmux_agent() { … tmux new-session -s "${tag}-$(date +%H%M%S)-$$" "$@"; }
   cy() { _lfg_tmux_agent cy claude --dangerously-skip-permissions "$@"; }
   ```

   No `-d`, no `-x/-y` — it attaches immediately and takes its size from the iTerm window.

2. **`ensurePaneRows` deliberately skips attached panes** ("a human is looking at it"). A `cy`
   session is attached by definition. So the reconciler that was supposed to be the load-bearing
   half never touched it either.

The Aug-7 verification used a detached, API-spawned session at 120x200. It proved the code worked
on a session shape that does not occur in Eugene's workflow.

## The deeper problem: a single capture is structurally insufficient

Fixing the size wouldn't have been enough anyway. Reproduced faithfully — a tmux session at 78x59
with a real attached client (`pty.fork` + `TIOCSWINSZ`), running the same kind of long-preamble
question:

| | |
|---|---|
| ground truth (transcript, after answering) | 4,447 chars / 753 words |
| best-case single-capture scrape | 1,664 chars, **starts mid-sentence**, no `⏺` bullet |

At 78 columns a ~700-word answer is taller than the pane, so by the time the selector renders the
top of the turn has been overwritten. And Claude Code runs in the **alternate screen** —
`history_size == 0`, so `capture-pane -S -N` returns the visible grid and nothing more. Re-confirmed
on the current Claude Code build that the turn is still absent from the transcript while the
question is live.

So the parser was never the problem. **The source was.**

## The fix: rebuild the scrollback the alternate screen refuses to keep

The head *was* on screen — earlier. While the model streams, the message grows from the top, and the
pump already captures the pane about once a second. Sampling one real turn (35 captures):

- **frame 5** contained `⏺ STITCHMARK — the push versus pull decision…` — the answer's first words
- **the final frame** contained no bullet at all

The information isn't missing; it just wasn't retained. `src/pane-history.ts` (`PaneStitcher`)
retains it: fed every capture the pump already takes, it reconstructs the text that scrolled away.
No extra tmux calls, no resizing, nothing visible in Eugene's terminal.

Design notes worth keeping:

- **Dedup by line content in first-seen order, not by frame-to-frame overlap.** The bottom rows
  (spinner, token counter, composer) change every capture, so the tail is never a stable anchor.
- **Blank lines are paragraph breaks and must be emitted positionally.** Deferring a blank to the
  next *new* line lands it mid-sentence — that produced a break every ~2 pane rows (31 paragraphs
  for a 6-paragraph answer). A blank is honored only when it sits exactly at the reconstruction's
  tail.
- **Cut each frame above an open selector** (`contentAboveSelector`). The question text and option
  descriptions are plain indented lines below the prose; without this they're recorded as preamble
  and the client shows the options twice (+30% spurious text, measured).
- **Reset on the idle→busy edge**, not on the prompt clearing. `busy` stays true while parked at a
  question, which is exactly the window the preamble must survive.
- Bounded at `MAX_LINES = 600` (~4,500 words, tens of KB per session) — this box has OOMed before.

## Verification

Fidelity against ground truth, same turn:

```
ground truth       4,447 chars / 753 words
last-frame scrape  1,664 chars — starts mid-sentence
STITCHED           4,556 chars — 100% word coverage, +2% extra, first sentence matches
```

Then end-to-end through the restarted server, on a 78x59 attached session:

```
pane contains "LIVEPROOF" (the answer's first word): 0 occurrences
GET /api/sessions → prompt.context: 4,406 chars, starts at "LIVEPROOF", 7 paragraphs
```

Plus 15 unit tests in `src/pane-history.test.ts`; 428 tests pass overall.

## What this does NOT need

No iOS change and no new TestFlight build — the client already renders `prompt.context` as an
assistant bubble (`PromptPreamble`, shipped in `202608071644`). The server change alone is the fix,
and it is live now.

## Lesson

The Aug-7 round verified the mechanism, not the user's situation. "Create a session the way the
product creates one" is not the same as "create a session the way Eugene creates one" — his sessions
come from a shell function that predates and bypasses lfg's spawn path. Before claiming a
pane-related fix works, enumerate the *actual* live sessions and check their geometry and
attachment, rather than constructing a fresh one.
