# Diagnosis — queued messages "fail" once the session goes idle (2026-09-07)

**Report (Eugene):** "When I queue a lot of messages the session ends and then I need to retry
sending the message. Sometimes there is this 502 error when I try to resend. After a message is
done, the session will turn idle and all the queued messages will fail to send. But it should keep
sending the message one by one."

## Verdict

Claude Code 2.1.259 no longer runs mid-turn messages "one by one" as separate turns. It **absorbs**
them into the running turn (the transcript records `queue-operation` lines with
`reason: "absorbed_mid_turn"`), and an absorbed message never becomes a standalone `user` text turn.
lfg's send queue only recognises delivery by finding that standalone turn, so every message queued
while the agent was busy was (1) actually received by Claude, (2) re-typed into the pane up to two
more times by lfg when the session looked idle, and (3) finally shown on the phone as
"the agent never picked this up after retries — resend". Eugene then resent them by hand, they were
absorbed again, and "failed" again at the next idle. Nothing was ever lost; the queue was lying, and
duplicating.

Secondary: lfg's own typing into the pane makes `isBusy` flicker false mid-turn for 1–2 s, and one
false-idle capture was enough to re-drive the whole batch (07:36:08Z, 17 minutes before the turn
actually ended).

The 502s are not from this path: today's server log has no 5xx on send/retry. The tunnel log shows
Cloudflare returning "connection refused" to the origin during each `lfg serve` restart (three
SIGTERM restarts on 2026-09-06: 18:43, 19:04, 02:12 HKT) — a resend that lands in that ~2 s window
is a Cloudflare 502. Restarts are other agents deploying; not fixed here.

## Evidence

Session `038215e0-c074-4a4d-aafc-91e672d6e5b4` (fiftyworkout app-quiz worktree, Pro host).

- `~/.lfg/sendq.log`: ten messages enqueued 07:29–07:38Z while a turn ran 07:28:26→07:53:40Z. All
  went `deliver-queued` (composer cleared while busy). At 07:36:08Z `reconcile-pending ×7,
  idleConfirmed:true` → re-driven; again at 07:53:42Z; `reconcile-failed ×6` at 08:00:13Z. The
  manual retries at 08:34 / 08:37 / 08:38Z repeat the same cycle.
- Transcript `queue-operation` lines: each of those texts has `enqueue` followed seconds later by
  `remove … "reason":"absorbed_mid_turn"`; a `dequeue` (normal next-turn pop) never appears for
  them. The absorbed text appears **nowhere else** in the jsonl — not as a user turn, not inside
  the tool_result it rode along with.
- Transcript user turns after 07:28:26Z: only the ones lfg re-typed at idle (07:53:42, 08:00:13,
  08:34:24, 08:37:28, 08:38:29Z) — i.e. every "successful" delivery was a duplicate of a message
  Claude had already absorbed.
- `journal.db` busy events: `busy:false` at 07:36:07Z, `true` 07:36:09, `false` 07:36:10, `true`
  07:36:16 — each flip coincides with a sendq `deliver-start` (our own paste into the composer).
- Claude Code binary (`/opt/homebrew/Caskroom/claude-code@latest/2.1.259/claude`) contains
  `consume(e,{reason:"absorbed_mid_turn"})` in the query loop; consumption reasons present:
  `absorbed_mid_turn`, `delivered_to_agent`, `delivered_as_tool_result`.
- `reconcile-failed` count in `sendq.log`: 3 in August, 83 in September — the behaviour changed
  with the Claude Code update, not with lfg (`src/sendq.ts` last touched 2026-08-16; running server
  started 2026-09-07 02:12 HKT, newer than every relevant source file — not a deploy gap).
- Server log `/private/tmp/lfg-serve.log`: no 5xx today except a codex resume; `[pump] poll sweep
  took 10–17s` lines show the event loop is already under load.
- Tunnel log `~/.cloudflared/lfg-pro.err.log`: `dial tcp 127.0.0.1:8766: connection refused` at
  2026-09-06 11:04Z and 18:12Z — both match `[serve-forever] restarting` lines.

## What the disconfirming checks said

- "Claude dropped the native queue" — no: `absorbed_mid_turn` removes prove consumption.
- "Deploy gap" — no: process start 02:12 HKT > all source mtimes.
- "Server 502 on retry" — no: `/queue/:id/retry` can only 404; no 502 logged today.

## Fix (see `.claude/feature/sendq-absorbed-mid-turn.md`)

1. Normaliser synthesises a user text turn from `queue-operation` remove lines whose reason is a
   consumption reason → the message shows in the transcript at the moment it was absorbed, and
   every existing "did it surface?" check (sendq, iOS pending strip) works unchanged.
2. The journal pump hands each newly-journaled user text turn to sendq, which promotes the matching
   `queued` row to `delivered` immediately, independent of the 40-message reconcile window.
3. Reconcile re-drives only on **sustained** idle (≥3 s across polls), never while sendq itself is
   typing into that pane, and never when the transcript window it read does not reach back to
   when the message was queued.
