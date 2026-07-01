# Diagnosis & Fix — "queued messages left pending, never picked up ever"

## Symptom (user)
On the iOS client a sent message shows a muted "pending" bar that never clears —
the message is never picked up, even **after the agent finishes its turn and is
ready** to pick it up.

## Ground truth (live, not theorized)
Scanned every tmux session's outbound queue on the running server (`:8766`) and
read the relevant transcripts/panes.

Stuck item (session `49e14373…`, AutoClipping): `queued | "Actually never mind we
can use dc instead"`, while later messages in the same FIFO queue delivered fine.
Transcript:
```
queue-operation enqueue  12:30:32  "Actually never mind we can use dc instead"
queue-operation remove   12:30:50      ← removed, NO user turn ever follows
```
→ it entered Claude's own queue and was **removed without being processed**.

And on the same session's **idle** pane (the real "agent is ready but nothing
happens" case):
```
✻ Cogitated for 3m 44s          ← turn finished, agent IDLE/ready
❯ create a github repo and push it   ← message sits UNSUBMITTED in the composer
```

## The real failure mode
A message that goes into Claude's busy-queue can end one of two unrecoverable
ways once the agent idles:
1. **Dropped** — Escape/interrupt/edit/supersede removes it from Claude's queue
   (`queue-operation remove`, no following user turn).
2. **Stranded** — the Enter was swallowed by the busy TUI, so the text sits as an
   unsubmitted composer draft; an idle agent never auto-runs a draft.

Either way Claude's native queue is **not a reliable delivery guarantee**.

## Root cause
`deliver()` classifies a send `"queued"` when the composer clears while Claude is
busy, then **fire-and-forgets into Claude's native queue**. `reconcileQueued()`
only ever transitioned `queued → delivered` on the text surfacing as a transcript
turn. There was **no recovery when Claude doesn't run it** — so it sits `queued`
forever and the iOS pending bar (driven off queue status via `correlatePending`)
hangs. The fix must *deliver* the message when the agent is ready, not give up.

## Fix (`src/sendq.ts`) — re-drive on idle
- `reconcileQueuedCore(msgs, recentUserTexts, {idleConfirmed, now})` (pure,
  unit-tested) → `{changed, kick}`. Per queued message:
  - surfaced in transcript → `delivered` (unchanged; wins over re-drive).
  - else `idleConfirmed && age > 10s grace`, under the re-drive cap → reset to
    `pending` (attempts→0, redeliveries++) and signal `kick`. The agent is now
    ready, so re-running `deliver()` **submits the stranded draft** (it skips
    re-typing when the composer already holds the needle) **or re-types**, then
    confirms via transcript growth → `delivered`.
  - cap (`MAX_REDELIVERIES = 2`) exhausted → `failed` ("the agent never picked
    this up after retries — resend"), so the UI shows Retry instead of looping.
- `reconcileQueued()` confirms idle via `capturePane` + `!isBusy(pane)`, **only**
  when there's an aged candidate (probe cost gated). Idle is the authority: an
  idle Claude has drained/won't-self-run its queue. Busy → never re-drive (the
  message may legitimately be waiting; re-driving would double-send). Unreadable
  pane → treated as not-idle. On `kick` it re-runs the delivery loop (`kick()`
  no-ops if already busy).
- 10s grace guards the sub-second window where Claude *does* auto-run a queued
  message — within grace it surfaces and is promoted, never re-driven.

Also: `GET /api/sessions/:id/queue` now `await reconcileQueued()` before
snapshotting, so the iOS poll safety-net (`reconcilePendingViaQueue`, used when
SSE stalled) self-heals too, not just the live SSE path.

## Known edge
A Claude build that holds queued messages without auto-running *and* without
dropping them could, after re-drive, run both the native copy and our resend
(duplicate). Modern Claude Code auto-runs queued messages sub-second, so the 10s
idle window makes this rare; a duplicate is strictly better than never-delivered.

## Client
No iOS change needed — `QueueItem.isFailed` / `correlatePending` already turn a
`failed` queue item into Retry; a re-driven message just flows pending → delivered.

## Verification
- `bun test src/sendq.test.ts` — 8 cases: promote-on-surface, promote-wins-over-
  redrive, redrive-when-idle+aged (→pending, attempts reset, kick), fail-after-cap,
  no-redrive-when-busy, no-redrive-within-grace, terminal-untouched, prefix match.
  Full suite green.
- **Live end-to-end VERIFIED (2026-07-01):** server restarted onto this code
  (`serve-forever.sh` supervisor relaunches on child exit). Throwaway tmux Claude
  session + iOS app in the simulator (FlowDeck), host pointed at `127.0.0.1:8766`.
    1. Happy path — message sent from the simulator while the agent was busy
       entered Claude's queue, surfaced when the agent finished, agent replied
       `PICKEDUP-OK` (native auto-run; `redeliveries=0`).
    2. **Re-drive path** — sent `bravo915echo` from the simulator while busy
       (→ `queued`), then dropped it from Claude's queue (`Up` → `Ctrl-U`;
       transcript records `queue-operation popAll` with no processing) and idled
       the agent. `reconcileQueued` detected queued+idle+aged+unsurfaced and
       re-drove it: queue showed `status=delivered, redeliveries=1`, the agent
       went busy, the message surfaced as a real user turn, and it replied
       `bravo915echo`. Under the old code this message would have stayed `queued`
       forever — this is the exact bug, now fixed.
- Note observed during testing: Claude's native queue reliably auto-runs queued
  messages sub-second on idle in this CLI build, so re-drive is genuinely a
  safety net for the drop/strand edge cases, not the common path.
- Latent (pre-existing, not introduced here): `reconcileQueuedCore`'s promote
  check uses substring `.some()`, so a *duplicate-text* queued message can be
  false-promoted by an earlier identical turn. Surfaced only because the test
  reused identical message text; real duplicate consecutive sends are rare.
