# "Queued messages are no longer sent automatically after the session goes idle"

**Reported:** 2026-08-06 ~19:10 local, from the iOS client. Symptom as clarified by Eugene:
the message **never arrives at all** — the agent goes idle and just sits there. Agent type
unknown at report time.

**Verdict:** two separate things were folded into one report.

1. **The claude path is healthy on this host.** Verified end-to-end today, twice, including
   through the real iOS client. Not the bug.
2. **Every recorded send failure on this host today was a *codex* session**, root-caused
   earlier the same day in `.claude/diagnosis-codex-send-not-sent-20260806.md` and fixed at
   ~18:36 (deployed 18:40). **The fix is still uncommitted, and the Air is still running a
   pre-fix server** — so the bug is live on the other host.

---

## Evidence

### The delivery trace nobody was reading

`CLAUDE.md` says delivery failures land in `data/sendq.log`. They don't — `PATHS.data` is
`~/.lfg`, so the file is **`~/.lfg/sendq.log`**. It has been recording since 2026-07-09 and
holds 21 failures. Every one of them is `"message never left the input box after retries"`.

Failures by session:

| sessionId | count | agent | when |
|---|---|---|---|
| `019fd561-…` | 11 | **codex** (`~/.codex/sessions/2026/08/06/019fd561-….lease.json`) | all of 2026-08-06 |
| `67598c15-…` | 4 | claude | 2026-07-10 |
| `f688108c-…` | 3 | claude | 2026-07-09 |
| `a135bff5-…` | 2 | claude | 2026-08-04 (send-path test) |
| `d77d5d6a-…` | 1 | claude | 2026-08-04 |

**Nothing on 2026-08-06 except the codex session.** Its message
`"Convert the artifact into HTML and host it in my cloudflare"` failed at 14:05, 14:09, 14:11,
14:12, 14:15, 14:27, 17:00, 17:25 local — the same `msgId` re-driven and re-retried for over
three hours. That is precisely "never arrives at all".

The `sendq` table agrees: the only non-`delivered` rows today are two `failed` rows, both
`019fd561`.

### The claude path, verified live

Scratch session `sendqrepro2` (`~/dev/personal/lfg-sendq-repro2`), server-side:

```
19:22:  POST /send  (long foreground loop, ~60s)   -> delivered
19:23:  POST /send  "QUEUEDMSG…" while busy        -> pending
        t=10s pending / t=20s pending / t=30s pending
        t=40s delivered   <- agent went idle, pump picked it up
```

Then through the **real iOS client** on the simulator (build from this working tree), which is
the seam that actually matters:

- typed while the agent was mid-turn → `pending` server-side, one-line bar in the client
  (`scratchpad/queued-bar.png`)
- agent finished → server delivered within one pump tick → the bar disappeared and the message
  became a normal blue bubble, answered `BARACK` (`scratchpad/resolved-bubble.png`)

Two hypotheses were tested and **disconfirmed**:

- *Held forever behind an open permission selector* — sent into a session sitting on a
  `Do you want to proceed?` dialog; `deliver()`'s Escape-dismiss path fired and the message
  landed in under 3s.
- *Slow `listSessions`/`resolveTranscript` stalling the queue* — measured: 533ms cold / 0ms
  warm, 1-3ms respectively.

### The codex path, verified live (scratch session `codexrepro`)

Independently re-verified rather than taken on the other session's word. Scratch codex TUI
(`codex --yolo --dangerously-bypass-hook-trust`), follow-up sent while codex showed
`Working (20s • esc to interrupt)`. Trace from `~/.lfg/sendq.log`:

```
11:59:00 enqueue             status=pending    age=0s
11:59:00 hold                status=pending    age=0s   agent busy   <- Defect B fixed: busy reads busy
11:59:05 hold                status=pending    age=5s   agent busy   <- (re-logged: server restarted, see below)
11:59:51 deliver-start       status=sending    age=50s               <- codex went idle
11:59:51 deliver-queued      status=queued     age=51s
11:59:53 reconcile-delivered status=delivered  age=53s
```

codex answered `CODEXACK`. Delivered on the **first** attempt (`attempts=1`) — the old failure
mode burned three attempts and gave up.

**Bonus finding:** the Bun server segfaulted and was respawned by `serve-forever.sh` at
19:59:04 — *mid-test*, four seconds after this message was enqueued. The message still landed:
`ensureRecovered()` rebuilt the queue from SQLite and delivery continued. That is the durable
queue doing its job, and it is why the `hold` line appears twice (the once-per-message WeakSet
guard is keyed on the object identity, which a restart replaces).

### Deploy gap on the Air

| host | serve started | has the codex fix? |
|---|---|---|
| Pro (this one) | 18:40:17 | yes (restarted 4 min after the fix) |
| Air | **10:10:12** | **no** — 8h older than the fix |

Both hosts share the working tree via Syncthing, so the Air's *files* have the fix and its
*process* does not. Its `sendq` table is empty, so nothing has been sent to an Air session
recently — but a codex send there today would still fail.

---

## What changed as a result

- **`src/sendq.ts`**: the trace log now records the whole lifecycle
  (`enqueue`, `hold`, `deliver-start`, `deliver-<status>`, `reconcile-<status>`), not only the
  final failure. `KEEP_TERMINAL = 12` prunes the queue rows, so before this a report an hour
  later had nothing left to read — which is why this took a live repro to answer. A hold is
  traced **once per message**, not once per pump tick. Suppressed under `NODE_ENV=test` so the
  unit tests don't append synthetic lines to the host's real trace.

## Still open

- The codex fix (`src/tmux.ts`) is **uncommitted**.
- The **Air's server needs a restart** to pick it up. That is a live-service restart on the
  other host (drops in-memory session tracking) — Eugene's call, not done unilaterally.
- `CLAUDE.md` points at `data/sendq.log`; the real path is `~/.lfg/sendq.log`.
