# Diagnosis — "pending messages often don't get picked up"

## Symptom (user, confirmed)
A message to a (raw-claude-in-tmux) session is stuck at `pending`, flips to
`failed`, and **keeps failing on retry**. Happens "most of the time."

## Path
iOS send → `POST /api/sessions/:id/send` → `enqueueMessage` → `sendq.ts:deliver()`
types into the Claude composer via `tmux send-keys`, then **screen-scrapes the
pane** (`inputBoxText` → text between the bottom two `─` rule lines) to confirm
the text is in the composer *before* it presses Enter, and again after to confirm
it left. Confirmed delivery, in theory.

## Live evidence
Caught two failing sends in the act (`.claude/send-fail-capture.txt`). Both:
- error: **`message never left the input box after retries`** (attempts=3)
- pane: Claude **busy** (`esc to interrupt`, `Canoodling…`), composer **empty**
  (`❯ ` blank). The user's typed messages showed up instead as Claude's own
  **queued-message** lines (`❯ We don't need that…`, footer `↓ to manage` /
  `Press up to edit queued messages`).
- **Every failing message was multi-line.** The one single-line send observed
  ("We don't need that…") landed fine as a queued message.

## Two compounding root causes

### 1. Multi-line messages submit prematurely
`tmuxType` = `tmux send-keys -t … -l <text>`. `-l` sends the string **literally,
byte-for-byte, including `\n`**. Claude's composer treats LF/CR as Enter, so a
3-line message submits (or fragments) at the first newline. The full text never
sits in the composer as one draft, so `boxHasNeedle` (needle = first 48 norm
chars) never matches → the type-settle loop never confirms → after 3 attempts,
`"message never left the input box after retries"`. Deterministic per message →
identical on every retry. This is why *multi-line* sends fail "most of the time."

**Verified fix on the real seam:** `tmux load-buffer` + `tmux paste-buffer -p`
(bracketed paste) into an idle session's composer holds all 4 lines without
submitting — Claude renders it collapsed as `❯ [Pasted text #1 +3 lines]`.
(Implication: post-paste confirmation can't look for the needle in the composer;
it must confirm via the transcript / composer-cleared instead.)

### 2. Confirmation is gated on a brittle composer scrape
Even single-line: when Claude is busy/streaming, the composer is empty (typed
text goes into Claude's *own* queue, rendered as a `❯` line in the body, not the
composer) and the pane redraws every ~1s. `inputBoxText` reads only the composer
region, so `boxHasNeedle` rarely returns `true`, the type-settle loop never
passes, and Enter is never pressed — `deliver()` fails even though the message
often *did* reach Claude's queue (false failure).

## Fix (planned)
1. **tmux.ts** — add `tmuxPaste(target, text)` (load-buffer + paste-buffer -p).
2. **sendq.ts deliver()** —
   - Insert via paste when the text contains a newline (else keep send-keys -l).
   - Stop gating Enter on `boxHasNeedle === true`. Confirm the composer is
     non-empty (needle present for single-line, or pasted-marker for multi-line),
     press Enter, then treat **transcript growth** (idle→processed) OR
     **composer-cleared** (busy→Claude's queue ⇒ `queued`, `reconcileQueued`
     promotes later) as the authority. Only fail if the text never entered the
     composer after retries.
3. **Observability** — append failure reason + a pane snapshot to `data/sendq.log`
   so the next regression is diagnosable without catching it live.

Activation requires restarting the Bun server (drops in-memory queue state +
reconnects SSE streams; the tmux claude procs themselves survive).
