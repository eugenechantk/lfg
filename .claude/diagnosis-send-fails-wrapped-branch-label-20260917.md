# Diagnosis — sends to cy-134704-39300 fail with "message never left the input box after retries" (2026-09-17)

## Symptom

Every follow-up sent from the client to the AiTinder session (`50aa4d46…`, tmux `cy-134704-39300`,
idle since 13:57) failed within ~11s: `message never left the input box after retries`. Eugene retried
six times between 06:01 and 06:15 UTC; the same text was enqueued twice. No send to this session ever
succeeded. `~/.lfg/sendq.log` shows `enqueue → deliver-start → deliver-failed` with attempts=3 each time,
and the failure-time pane tail shows an EMPTY composer plus Claude's `Ctrl+Y to paste deleted text` hint.

## Root cause (three layers)

1. **The composer's top border was unrecognisable.** The session is a numbered branch view, so Claude
   labels the top border with the branch title: `… holds the app project (Branch 2) ─`. Claude draws its
   chrome ~83 cols wide while the tmux pane is 79 (the bottom border wraps into `─×79` + `─×4` for the
   same reason), so the label wrapped with `(Branch` on one line and `2) ─` on the next. `isRuleLine`
   only knew the single-line `(Branch N) ─` form (commit 7245a07, 2026-09-16), so neither half counted
   as a border.
2. **The dead Codex `›` fallback returned transcript content.** With no border pair, `inputBoxFromPane`
   fell through to a trailing "scan bottom-up for a `›` line" fallback and returned
   `[image] kai-gpt.jpg (202.6KB)` — a line from Claude's own SendUserFile listing — as "the composer".
   That fallback was strictly dominated by `codexComposerIndex` (which already handles every pane where
   a `›` line can be the composer), so the only thing it could ever add was a false positive.
3. **A wrong non-null answer drives the wipe-and-retype loop.** `composerHoldsInput` returned `false`
   ("composer readable, draft absent") on every settle check, which `insertionOutcome` maps to `retry`:
   Ctrl-U, retype, three times, then fail. The keystrokes had landed each time; sendq erased them itself.
   Had the parser returned `null`, the send would have gone out `unconfirmed` and the transcript probe
   would have confirmed it — the graceful path `insertionOutcome` was designed for.

Verified by running `inputBoxFromPane` over a `capture-pane` of the live pane: old code →
`"[image] kai-gpt.jpg (202.6KB)"`, new code → `"❯ "`.

## Fix (`src/tmux.ts`, tests in `src/tmux-composer-border.test.ts`)

- `ruleAt(lines, i)`: a line ending in `─` also counts as a border when `lines[i-1] + lines[i]` matches
  the branch marker (`/\(Branch\s*\d*\)\s*─+\s*$/` — `\s*` because capture-pane trims the space at the
  wrap column). The border scan in `inputBoxFromPane` uses it everywhere it used `isRuleLine`.
- The trailing `›` fallback is removed; unpaired borders now return `null`.
- Fixture `NUMBERED_BRANCH_WRAPPED_LABEL` is the verbatim capture; plus a test that a `›` transcript line
  is never returned as the composer, and wrap-point cases for `ruleAt`.

## Deploy + live verification

Server restarted by port (pid 1376 → 62828, 14:20:13). Queue rows do not survive a restart, so the failed
row could not be retried by id; the exact text was re-sent via `POST /api/sessions/:id/send`:
`enqueue 06:20:48.481 → deliver-queued 06:20:48.975 → surfaced-delivered 06:20:49.466`, and the user turn
is in the transcript (lines 579 → 582). Same pane, same geometry, no retype.

## Still open

- Claude renders chrome wider than the attached `cy` pane (83 vs 79 cols). Every border-parser bug so far
  has been a wrap. Nothing here changes that; the parser just tolerates one more wrap shape.
- First diagnostic for any future "never left the input box": `tmux capture-pane -p -t <target>` into a
  file and run `inputBoxFromPane` on it with `bun -e`. It answers in one step whether the parser is
  reading the composer at all.
