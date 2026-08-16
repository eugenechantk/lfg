# Diagnosis — pending rows stuck at the bottom of `codexy-153628-89613`

**Date:** 2026-08-16
**Reported:** "There are my own messages stuck at the bottom even though the message is sent above and the session is not running."
**Session:** `codexy-153628-89613` → rollout `019fff33-6f44-7e00-8b36-b57f762833ce` (codex, `~/dev/personal/fiftyworkout`)

## Ground truth collected

| Source | What it says |
| --- | --- |
| `GET /api/sessions` | session is bound, `busy: false`, 1290 transcript messages (54 user turns) |
| `GET /api/sessions/<id>/queue` | **empty** — nothing is stuck server-side |
| `~/.lfg/sendq.log` (67 lines for this session) | On **2026-08-14, 09:34 → 10:38** the same text (`"I think the character emotions is too sad…"`) produced **six distinct queue items** and **32 `deliver-failed` events**, all with `error: "message never left the input box after retries"`. One copy (`a60ac112…`) finally delivered at 10:38:21. Two more messages that day followed the same pattern. |
| transcript | All three texts **did land** as real `user/text` turns: ts `1786703901458`, `1786705759805`, `1786707178900`. |

So: nothing is pending on the host. The stuck rows are **client-side optimistic rows** (`SessionStore.pendingSends`), restored from the durable outbox, that the client cannot prove have landed.

## Root cause

`OptimisticSendReconciliation.containsMatchingUserTurn` — the function that decides whether an
optimistic row may retire — used to scan only the **newest 30 user turns**.

Position of the landed turns in this transcript:

| landed turn | user turns after it |
| --- | --- |
| `1786703901458` "I think the character emotions…" | **40** |
| `1786705759805` "Never mind can you help generate…" | **39** |
| `1786707178900` "Next we need to generate audio…" | **38** |
| `1786814611160` "Can we create the first session schema…" | 0 |

All three sit outside the 30-turn window, so the client answered "not landed" forever and the rows
never retired. Verified by running both algorithms against the **real 1290-message transcript**
(Python port of the Swift function, real timestamps):

```
character emotions     old=False new=True
Never mind             old=False new=True
Next we need           old=False new=True
session schema         old=True  new=True     <- recent turn, reconciles either way
```

Two conditions had to coincide, which is why only this session shows it:

1. **The 08-14 codex send storm** left several *non-delivered* outbox rows for texts that a sibling
   copy did deliver. Non-delivered rows are deliberately restored into the pending strip on every
   launch (so a failed send is never silently lost).
2. **The reconcile window couldn't see 40 turns back**, so those rows could never be proven landed.

## Fix status

The timestamp-aware reconciliation (scan back until turns predate the send, instead of a fixed
30-turn tail) is **already written** — uncommitted, in the working tree, from the
`.codex/feature/historical-optimistic-message-reconciliation.md` session — and it **is present in
the last archive**: build `202608152131` (1.2.0), archived 2026-08-15 21:34; its dSYM contains the
new `clockSkewAllowance` symbol. Nothing was shipped for it after that.

⇒ If the phone is on a build older than `202608152131`, this is a **deploy gap**, not a live bug.

## Remaining defect (not fixed by the above)

`reconcilePending` / `correlatePending` retire an optimistic row when the turn is found in the
transcript, but **never delete the row's durable outbox entry**. Only a `delivered` queue ack
(`applyQueueAck` → `markOutboxStateEventually("delivered")` → `deleteOutbox`) removes it.

Consequences:

- Every cold launch re-appends these rows (`replayPendingOutboxOnStart` → `retryableOutbox()`
  returns everything with `state <> 'delivered'`), and they are only *masked* again once the full
  transcript fetch completes. Between launch and that fetch they are visible at the bottom.
- If the fetch is slow, fails, or the host is unreachable, they stay visible for the whole session.
- Rows older than 24h are re-marked `failed`, so they persist indefinitely as "Not sent" rows whose
  only defence is a text match against a transcript that may not be loaded.

The text match is a mask, not a resolution. A row proven landed should drop its outbox entry.

## Fix applied (2026-08-16)

`SessionStore.retireOutbox(_:)` — reconciliation now **deletes the durable outbox row** (and its
attachment sidecars) whenever it retires an optimistic send, from both `reconcilePending` and
`correlatePending`. A row proven landed is finished; it must not survive to be restored and
re-POSTed on the next launch.

## Verification (live, real data)

Stub host on `:8801` serving the **real 1290-message transcript** for this session (never the live
server — the outbox replay POSTs, and must not touch the real codex pane). Two outbox rows seeded
directly into the simulator's `lfg-store.sqlite`, both `state='sent'`:

| row | text | expected |
| --- | --- | --- |
| A | the real 2026-08-14 turn, 40 user turns back | retires + row deleted |
| B (control) | text that appears nowhere in the transcript | stays visible + row kept |

Result — `improvement-log/stuck-detail.png`:

- **B renders as a blue bubble appended below the last transcript message** — the exact symptom
  reported, so the repro is faithful.
- **A is absent from the UI and gone from the `outbox` table**, and was never re-POSTed (stub log
  records one POST, B's).
- After a relaunch (`improvement-log/stuck-detail-relaunch.png`) A stays gone and B comes back —
  the durable state now distinguishes "landed" from "still owed".

`swift test`: 308 XCTest + 58 Swift Testing cases pass. `flowdeck build`: green.

Shipped as TestFlight build **202608161241** (1.2.0).

## Known residual

`replayPendingOutboxOnStart` and reconciliation race at launch. Reconciliation won here (history
loads before the deferred replay), but if the replay wins, a landed row is re-POSTed once before
being retired. The server's `duplicateByClientId` dedupe absorbs that as long as the queue row is
still persisted; past the prune horizon it would re-deliver. Pre-existing, not introduced here.

---

# Round 2 — `cy-011521-59885` still showing bubbles after 202608161241

**Session:** `cy-011521-59885` → `8c444fb3-c8e2-46e9-973d-85279338f9ec` (claude, `fiftyworkout`), `busy: false`.
Two bubbles at the bottom: *"Can we change the timezone to us timezone?"* (sent 03:18) and *"So we need
to store the person's timezone…"* (sent 03:51). A third send between them (03:47) reconciled fine.

## What the ground truth ruled OUT

- **Not a text mismatch.** The sendq-logged bytes and Claude's recorded turn are byte-identical for
  all four sends of that session (compared with `startswith` + `==` over the logged prefix).
- **Not the 30-turn window.** These turns are ~5–8 user turns from the tail; the old algorithm would
  have matched them too.
- **Not a stale transcript in the view.** The assistant message rendered directly above the bubbles
  is `ts 1786857499321` — the newest message in the whole transcript. The client was current.
- **Not the fix failing.** Replayed on build 202608161241 against this session's real 2717-message
  transcript with both real texts seeded as `state='sent'` outbox rows: **both retire and both outbox
  rows are deleted**; only the control row survives (`improvement-log/cy-repro.png`).

The interleaving (03:18 stuck, 03:47 fine, 03:51 stuck) is the tell: which rows survive is decided by
whether the app was alive to take the `delivered` ack, not by anything about the message.

## Remaining hole, now closed

`ensureHistory` fetched the transcript with `try?` — **a failed fetch was silently swallowed**, and
`hydrateTranscriptFromStoreIfEmpty` does nothing when the transcript is merely *partial* rather than
empty. Nothing retried until the user left the session and came back. A client sitting on a partial
transcript cannot prove any send landed, so every restored optimistic row stays on screen. This
session's history is **2.39 MB** over a 15s-timeout request, so the failure is not hypothetical.

Fix: log the failure to `ConnectionLog` (category `PRB`) and retry once after 2s.

**Verified live:** stub configured to reject the first `/messages` request. Stub log shows the reject
at `05:31:05.775` and the client's retry at `05:31:07.900` (2.1s later) — a second request that the
old code never made — after which the real stuck text reconciled and disappeared
(`improvement-log/retry-after.png`). `swift test`: 317 XCTest + 58 Swift Testing pass.

Shipped as **202608161332**.

## Still unresolved

Whether the phone was on 202608161241 when the screenshot was taken. The app writes its
version+build to the Connection Log at every launch (Settings → Connection Log, with a share
button), so that log answers both this and whether history fetches are failing in the field.

---

# Round 3 — the bubble that cannot be deleted

**Reported:** "so many user messages hanging at the bottom, and a queued message I cannot
delete and is probably delivered" — `cy-011521-59885`.

## Ground truth (host side, 2026-08-16 16:4x)

| Source | What it says |
| --- | --- |
| `GET /api/sessions/8c444fb3…/queue` | 3 rows, **all `delivered`** (06:01, 08:23, 08:32) — nothing stuck |
| `~/.lfg/sendq.log` | every send for this session reached `reconcile-delivered`; no failures today |
| `GET …/messages?limit=5000&full=1` | 2.5 MB, 2923 messages, **0.06 s** locally; all five candidate texts present as real `user/text` turns |

So the host is clean and the transcript proves every message landed. The "hanging" bubbles
are client-side optimistic rows, as in rounds 1–2.

## The new, separate defect: Remove is a dead end

`removeMessage` (`src/sendq.ts`) refused to remove a row whose status was `delivered`, and the
route answered **409**. `SessionStore.removeQueued` reads any non-success as "the agent has
committed to it, keep the row visible" — the right rule for `queued`, the wrong rule for a
receipt. So the one manual escape hatch the UI offers is guaranteed to fail on exactly the rows
that get stuck. That is the literal "I cannot delete it".

A second, adjacent hole: once a queue row ages past `KEEP_TERMINAL = 12` the server 404s that id.
The client treated 404 the same as 409 — permanently undeletable, for an id no host has ever
heard of.

## Fix

- **Server** — `removeMessage` now blocks only `sending` (mid-keystroke) and `queued` (in the
  agent's native next-turn queue). `delivered` and `failed` are terminal receipts and can be
  dismissed. The route 404s an unknown id explicitly instead of folding it into the 409.
- **Client** — `QueuedMessageRemovalOutcome` replaces the `serverRemovalSucceeded: Bool`:
  `removed` / `unknownToServer` (404) → remove locally *and delete the durable outbox row*;
  `rejected` (409) / `requestFailed` (offline) → keep the bubble.

Note the asymmetry that matters for cleanup speed: **the 200 path works with the app build
already on the phone.** Only the 404 path needs a new TestFlight build.

## Verification (live, real gestures)

Stub host on `:8802` (`.claude/evidence/20260816-undeletable-queued/stub-host.ts`) — never a second
`lfg serve`. It accepts a send, reports that queue row as `delivered`, and **never** adds the turn
to the transcript, which is precisely the state that strands a bubble. `POST /__delete_status/<n>`
switches the DELETE answer so all three cases run against one live app.

| Case | DELETE answers | Result | Evidence |
| --- | --- | --- | --- |
| repro | — | "Stuck bubble repro" sits above the composer with a spinner | `01-stuck-bubble.png` |
| A | 409 | Remove tapped, row **stays** (correct: still committed) | `03-409-stays.png` |
| B | 404 | Remove tapped, row **gone** | `04-404-removed.png` |
| C | 200 | Remove tapped, row **gone** and dropped from the host queue | `05-200-removed.png` |
| durability | — | cold relaunch: neither removed row returns (outbox rows deleted) | `06-relaunch-still-gone.png` |

`bun test`: 629 pass / 0 fail. `swift test`: 323 XCTest + 58 Swift Testing pass.
`flowdeck build`: green.

## What this does and does not fix

It gives Eugene a Remove that always tells the truth. It does **not** explain why reconciliation
failed to retire these rows on its own — the host serves the full transcript in 60 ms and every
text is in it, so the remaining suspect is still client-side (partial history, or a build older
than `202608161332`). The Connection Log (Settings → Connection Log) remains the only thing that
distinguishes those two.

## Why the 404 path is the common case, not the edge case

`SendqStore.recoverable()` (`src/sendq-store.ts`) selects `WHERE status IN ('pending','sending','queued')`.
**Terminal rows are never recovered.** So every `lfg serve` restart makes every `delivered` queue id
invisible to `listQueue`/`getMessage` — the row is still in sqlite, but the API 404s it.

Observed directly: before the 16:48 restart `8c444fb3…`'s queue held 3 `delivered` rows; immediately
after, `GET …/queue` returns `[]`.

Consequences:

- A phone holding a `serverQueueID` from before any restart gets **404**, not 409. The 200-on-delivered
  server fix therefore does *not* help a bubble that outlived a restart — the **client-side 404
  handling is the load-bearing half**, and it needs a shipped build.
- It also means `correlatePending` sees the queue item "vanish" after every restart, which routes it
  down the `needsHistory` branch — the branch that depends entirely on a successful full-transcript
  fetch, which is the fragile part rounds 1–2 were already fighting.

Follow-up worth considering (not done here, deliberately out of scope): recover terminal rows too, so
a restart stops erasing delivery receipts. `pruneTerminal` already caps them at 12 per session, so the
memory cost is bounded — but it changes pump/recovery semantics and deserves its own pass.

## Shipped

- **Host:** `lfg serve` restarted 2026-08-16 16:48 (pid 6774) with the `removeMessage` change live.
- **App:** TestFlight build **202608161650** (1.2.0) — `DoD PASS: 202608161650 VALID on train 1.2.0
  (highest), internal=IN_BETA_TESTING`. Carries the 404 handling, which is the half that actually
  clears a bubble stranded across a server restart.
