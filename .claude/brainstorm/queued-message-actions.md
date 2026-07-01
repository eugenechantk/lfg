# Feature — Tap a queued message: Remove / Edit / Send now (interrupt)

## Goal (user)
In the iOS client, tap a queued (in-flight) message and choose to:
- **Remove** it (it should not run),
- **Edit** it (pull text back to composer, re-send after editing),
- **Send now + interrupt** (stop the current turn and run this message immediately).

## Core decision — where does the queue live?
Today `deliver()` eagerly types a busy-time send into **Claude's own native queue**
(status `queued`). Pulling it back out (Remove/Edit) then requires driving the
tmux pane (`Up` + `Ctrl-U`) — fragile, racy, ambiguous with multiple queued.

**Chosen model: hold-in-lfg (deliver on idle).** While the agent is busy, lfg
keeps the message in **its own** queue and does NOT type it into Claude. A message
is typed+submitted only when the agent is idle (reusing the idle-detection from
the re-drive fix) or immediately on "Send now + interrupt".

Why: Remove/Edit/Send-now all become trivial and robust (the message is lfg's
until the moment of delivery), and it removes the whole "dropped/stranded in
Claude's native queue" failure class.

Tradeoff: a held message no longer shows in Claude's *native* tmux queue mid-turn;
it shows only in the lfg app queue strip until delivered. Invisible to app users.

## Server changes (`sendq.ts` / `serve.ts`)
- `deliver()`: if the agent is **busy**, do not type — leave the message `queued`
  (now meaning "held by lfg, waiting for idle") and return. Only type+submit when
  the agent is idle; confirm via transcript growth (the existing idle path).
- Idle-driven delivery: when the per-session idle-poll sees the agent idle and a
  held `queued`/`pending` message exists, `kick()` the delivery loop. (reuse the
  reconcile/idle plumbing.)
- `DELETE /api/sessions/:id/queue/:msgId` — remove a held message (drop from
  lfg's queue). No pane driving needed because it was never in Claude's queue.
- `POST /api/sessions/:id/queue/:msgId/send-now` — interrupt the current turn,
  then deliver this message immediately (move it to the head + kick after the
  agent idles from the Escape).
- Guard races: if the message already `delivered`/surfaced, the actions no-op and
  the queue snapshot refreshes.

## iOS changes
- Pending/queue strip rows become tappable → confirmationDialog:
  - **Send now (interrupt)** → `POST …/send-now`
  - **Edit** → load text into the composer draft + `DELETE` the queue item
  - **Remove** (destructive) → `DELETE` the queue item + drop the optimistic bubble
  - Cancel
- Only offer Remove/Edit while the item is still pending/queued (not delivered).
- `LFGClient`: add `deleteQueued(id, msgId)` and `sendNow(id, msgId)`.

## Verification — DONE (2026-07-01, live against the real send path)
Server restarted onto the hold-in-lfg code (pid 87261; both new endpoints return
409 not 404). Throwaway tmux Claude session `a1042813`, driven via the real
`POST /send` path (identical to the iOS client's).

- **Core hold-in-lfg — PASS.** Sent `whiskey613november` while the agent was busy
  → lfg queue status `pending` (HELD), and Claude's native pane showed
  `esc to interrupt` but **not** "edit queued messages" → it was NOT pushed into
  Claude's own queue. When the agent idled, the server pump delivered it: status
  → `delivered` (`redeliveries=0`, i.e. a clean idle-delivery, not a re-drive),
  the agent went busy, the message surfaced as a real user turn, and it replied
  `whiskey613november`. Transcript shows **no `queue-operation enqueue`** for it —
  confirming it never touched Claude's native queue (unlike the old eager model).
  Not dropped, not left as an unsubmitted draft.
- **Remove — PASS.** Held `xray404kilo` → `DELETE …/queue/:id` (200) → gone from
  the queue; after the agent idled it had **0 occurrences** in the transcript —
  never delivered.
- **Send now (interrupt) — PASS.** Held `sierra888tango` during a 200-item task →
  `POST …/queue/:id/send-now` (200) → `delivered` within ~2–4s; the message
  surfaced and was answered while the long task was interrupted (didn't complete).
- **Edit** — server-side is Remove (verified) + a pure-client composer repopulate.

Not re-run this round: the in-simulator tap-UI (confirmationDialog → actions).
The disk cleanup wiped all sim runtimes (0 installed; restoring needs an ~8 GB
download). The iOS send path itself was already exercised from the real simulator
earlier this session (PICKEDUP-OK; re-drive `bravo915echo` redeliveries=1), the
app builds clean with these changes, and the new `SessionStore` methods are thin
wrappers over the endpoints verified above.
