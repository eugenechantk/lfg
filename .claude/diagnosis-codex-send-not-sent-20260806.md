# Codex sends: "running → queued → not sent", retry never works

**Reported:** iOS client, follow-up message to a **codex** session. The session shows running,
the message flips to *queued*, then to the *not sent* error. Retrying fails the same way.

**Verdict:** not a transport bug. The message really is delivered (often more than once). The
defect is that `src/tmux.ts`'s pane parsers assume **Claude's TUI shape**, so for a codex pane
lfg mis-reads both "is the agent busy" and "what is in the composer". `sendq.ts` contains zero
codex awareness — every codex send runs through Claude-shaped confirmation.

## Ground truth

Live capture of a busy codex pane (`sendqrepro:0.0`, scratch session created for this):

```
 13      "• Running the requested command now."
 14      ""
 15      "• Working (1m 16s • esc to interrupt) · 1 background terminal running · /ps to"
 16      ""
 17      "• Messages to be submitted after next tool call (press esc to interrupt and se"
 18      "  immediately)"
 19      "  ↳ run the shell command: sleep 120; then reply DONE2"
 20      ""
 21      "› Write tests for @filename"          ← the codex composer
 22      ""
 23      "  gpt-5.6-sol high fast · ~/dev/personal/lfg-sendq-repro"
```

`isBusy(pane)` → **false**, while the pane plainly says `Working (1m 16s • esc to interrupt)`.

## Defect B — busy detection misses codex (the one that causes the reported failure)

`busyChromeRegions` locates chrome by pairing the composer box's `─` borders. A codex pane has
**no bordered composer**, so it takes the `i < 0` fallback: both the meter and footer regions
become the last `METER_LOOKBACK_LINES = 6` lines.

Six lines is enough for a *plain* busy codex pane. It is **not** enough once codex renders its
own queue notice ("Messages to be submitted after next tool call", 3 extra lines) — that block
pushes the `Working (…)` meter to 6 lines above the composer, outside the window. `ESC_HINT` is
only tested against `footer`, so the marker is never seen.

This is self-reinforcing, which is why the bug looks intermittent: **the queue notice only
appears once a message has been queued** — so the very first queued message makes lfg blind to
codex being busy, and every judgement after that inverts.

The failure chain:

1. `agentBusy()` is false → the hold-in-lfg gate does not hold. `deliver()` types into a codex
   that is mid-turn.
2. Codex takes the text into its **own** queue and clears the composer → `held === false` →
   sendq marks the message **`queued`**. The session shows running. ✔ matches the report
3. `reconcileQueued` computes `idleConfirmed = pane != null && !isBusy(pane)` → **always true**
   for codex. After the 10s grace it concludes codex "never picked this up" and **re-drives** —
   retyping the same message into codex, so codex's native queue accumulates duplicates.
4. After `MAX_REDELIVERIES = 2` it marks the message **`failed`**:
   "the agent never picked this up after retries — resend". ✔ matches the "not sent" error
5. Retry re-enters the identical state (the queue notice is still on screen) → fails again.
   ✔ matches "retrying does not work"

Confirmed live: a follow-up sent while the meter was inside the 6-line window sat correctly at
`pending` for 100s and then delivered. The same send with the queue notice on screen is the
failing path.

## Defect A — the composer is misread on codex panes with ≥2 rule lines

`inputBoxFromPane` scans bottom-up and pairs the two nearest `─` rule lines. A codex pane has no
composer box, but it *does* contain rule lines — codex prints a `─ Worked for 1m 17s ─` separator
after every completed turn, plus plain `─` runs in agent output. On a real session pane:

```
RULE at 18, RULE at 50, RULE at 73 ("─ Worked for 1m 17s ─")
inputBoxFromPane => "\n• The app was still running the pre-fix process from 17:30. …"
```

It pairs 73 with 50 and returns **the assistant's own output** as "the composer". The codex `›`
branch already in the function is never reached, because it is only a fallback for when the
border pairing fails.

Consequence: `composerHoldsInput` returns `false` (readable, needle absent) →
`insertionOutcome` → `"retry"` → clear + retype ×3 → `"message never left the input box after
retries"`. A second, distinct way a codex send fails. It needs ≥2 visible rule lines, so it hits
long-running sessions.

## Fix

Recognise the codex TUI as a first-class shape instead of letting Claude-shaped border pairing
claim it.

**Discriminator:** a `›` composer line that lies **below the last rule line**. In Claude the
composer content sits *between* two rule lines; in codex the `›` line is strictly below every
rule line.

1. `inputBoxFromPane` — check the codex shape *first*, return the `›` line's text.
2. `busyChromeRegions` — for a codex pane the chrome region is the block from the last rule line
   (or a bounded lookback) down to the end of the pane: meter, queue notice, composer, status.
   Bounding by the last rule line keeps the scan out of scrollback, which is the constraint the
   original 6-line window existed to enforce.
3. `isBusy` — for the codex region match codex-specific chrome markers rather than the bare
   `esc to interrupt` hint, which is too loose for a region that can include agent prose:
   - `(1m 16s • esc to interrupt)` — a parenthesised timer, chrome-only in practice
   - `Messages to be submitted after next tool call` — only renders mid-turn

Fixing `isBusy` also corrects the running/idle indicator for codex sessions, which shares the
same primitive via `journal-pump`.

## Scratch rig

`tmux` session `sendqrepro` in `/Users/eugenechan/dev/personal/lfg-sendq-repro`. Delete both when
done — no other agent uses them.
