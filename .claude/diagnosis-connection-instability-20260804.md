# Diagnosis — connection instability + unreliable sends (2026-08-04)

Three reported symptoms:

1. Hosts are online, iOS shows disconnected, connects after 10–20s
2. Messages not sent for **idle** sessions even when the host is connected
3. Resend / interrupt / follow-up are not reliably sent

They have **two different causes**. #1 is a fix that exists and was never
shipped. #2 and #3 are an architectural problem in `/send` — and the reason
they've resisted fixing is that failures leave no evidence.

---

## Symptom 1 — "connects after 10–20 seconds"

**Cause: the fix is written, committed, tested, and not on your phone.**

`ios/LFGCore/Sources/LFGCore/HostEvents.swift:113` documents your exact symptom,
in the code that fixes it:

> `quietRedialAfter` — How quiet an apparently-healthy stream may be before a
> foreground kick force-redials it. […] after a process suspension a link can
> *read* healthy (`.live`, no failure recorded) while its socket is long dead,
> because its watchdogs were frozen along with everything else. **Waiting for the
> 20s stale watchdog to notice is exactly the "not connected for a while" the
> user sees on reopening the app.**

The numbers line up exactly with what you observe:

| Constant | Value | Role |
|---|---|---|
| `staleTimeout` | **20s** | how long a dead socket looks alive without the kick |
| `quietRedialAfter` | 12s | the foreground kick's threshold — preempts the above |
| `keepaliveInterval` | 10s | NAT-mapping warmth + fast death detection |
| server heartbeat | 10s | — |

iOS suspends the app; its watchdogs freeze with it. On reopen the link still
reads `.live` while its socket is dead, and nothing notices until the 20s stale
timer fires. **That is your 10–20 seconds.** It is not the network and not the
host — both are fine the whole time.

`7a5b2ea ios: reconnect on launch and foreground instead of showing a stale
Offline` adds the foreground kick. `8ecdf83 fix: send the first SSE heartbeat
immediately on connect` is its server half.

**Ship state:**

| | |
|---|---|
| Last version bump | `41ac525 ios: 1.2.0` — **2026-08-01** |
| Fix commits | `7a5b2ea`, `8ecdf83` — **2026-08-04** |
| `MARKETING_VERSION` | still **1.2.0** |

The fix landed *after* the last release and no build has been cut since. This is
a TestFlight build away, not a code change away. (Confirms the standing memory
note; re-verified today.)

**One real architectural residue** (worth fixing after shipping): the banner is
`reachabilityByHost != .ok`, and there are **two writers** for it — the REST poll
(`refresh()`, now a 60s loop) and link state (`linkStateChanged`). The comment at
`SessionStore.swift:1008-1015` concedes the flip "cannot wait for the NEXT
state-change callback" because those arrive "once per watchdog cycle (~20-25s)".
So a poll-driven banner is being patched to keep up with a link-driven reality.
The durable fix is the one in the architecture analysis: **derive connection
state from the HostLink only** — it is the thing actually carrying data — and
demote the REST poll to reconciliation that can never paint the banner.

---

## Symptoms 2 & 3 — sends that report success and don't happen

### `/send` is four different mechanisms behind one endpoint

`serve.ts:2136-2220`, in order of evaluation:

| # | Condition | Mechanism | Confirms delivery? |
|---|---|---|---|
| 1 | session not in `listSessions()` | `resumeClosedSession()` — spawns a **new session, new sessionId** | **No** |
| 2 | agent is `aisdk` / `codex-aisdk` / `opencode` | `appendAisdkCmd()` — appends to a command file | **No** |
| 3 | no `tmuxTarget` | `409 "session is not in a tmux pane"` | n/a — hard fail |
| 4 | tmux session | `enqueueMessage()` → confirmed-delivery queue | **Yes** |

Only path 4 confirms anything. Paths 1 and 2 both call
`recordImmediateMessage()` (`sendq.ts:209`), which does this:

```ts
status: "delivered",      // ← set unconditionally, before anything happens
attempts: 0,
…
journalDelivered(sessionId, msg, null);   // ← and acks the client
```

**The message is marked delivered and the client is told so, before any
verification exists.** If the harness never reads the command file, or the
resume never picks up the prompt, the text is gone and the UI shows it sent.
That is precisely "messages are not sent even when hosts are connected."

Path 1 has a second hazard: it returns a **different `sessionId`** than the one
you sent to. The conversation continues elsewhere; the session you were looking
at stays silent.

### Why "idle" sessions specifically

An idle session is the one most likely to have lost its pane (reaped on host
restart, closed, or — as found earlier today — its `tmuxTarget` nulled by pane
attribution). Losing the pane is exactly what routes a send out of the confirmed
path (4) into the unconfirmed ones (1) or the hard 409 (3). **Idle is a proxy for
"no longer has a live pane."**

I have *not* root-caused a specific idle-send failure, because — see below —
there is no record of one to root-cause.

### Interrupt has no delivery guarantee at all

`serve.ts:2414` — interrupt is `appendAisdkCmd(key, {type:"interrupt"})` for the
aisdk family and a raw `tmuxInterrupt` (single Escape) otherwise. Neither
confirms. A busy TUI drops keys; `deliver()` learned that lesson for messages
(`sendq.ts` retries + confirms) but interrupt/close never got the same treatment.
That is symptom 3.

### The reason none of this has been fixable: failures are erased

- `KEEP_TERMINAL = 12` (`sendq.ts:78`). `pruneTerminal` runs after **every**
  terminal transition, keeping only the newest 12 rows per session. Failures are
  pruned exactly like successes.
- `data/sendq.log`, which project CLAUDE.md says failures log to, **does not
  exist** and nothing writes it.
- Net effect: the persisted `sendq` table today reads *97 sends, 100% delivered,
  all on attempt 1* — which is not evidence of health, it is evidence of
  pruning. Two failed sends from earlier today are already gone.

There is no way to answer "how often does a send fail, and on which path" from
this system. That is the actual blocker.

### Secondary: the pump violates a documented house rule

`startQueuePump` (`sendq.ts:366`) is a bare `setInterval(1000)` that fans out
over every queue each tick, and each `kick` can spawn `tmux capture-pane`
synchronously. Project CLAUDE.md explicitly warns: *"No bare `setInterval`
fan-out over a collection on the single Bun event loop — a growing collection
turns the tick into a spawn storm."* With many sessions this competes with the
same event loop serving `/api/events`, which degrades symptom 1.

---

## Plan, in order

**1. Cut a TestFlight build.** Nothing else touches symptom 1, and symptom 1 is
the one you feel most. Zero code risk — the code is already written, reviewed and
tested (`swift test` 165 / `bun test` 169 pass).

**2. Make send failures durable and visible** — before changing any send logic.
Stop pruning non-delivered rows (`pruneTerminal` should keep terminal *successes*
bounded but retain failures), and write `data/sendq.log` on every terminal
transition with the pane capture at failure. Without this, every subsequent fix
is unverifiable — including today's.

**3. Give paths 1 and 2 the same delivery contract as path 4.** Nothing may write
`status: "delivered"` that has not been confirmed. Introduce `status: "sent"`
(handed off, unconfirmed) so the client can render honestly, and confirm aisdk
sends by watching the transcript for the new user turn exactly as the tmux path
does. Resume-path sends should report the new `sessionId` as a first-class
remap event, not an optimistic ack.

**4. Route interrupt/close through the confirmed queue** rather than a bare
keystroke or a file append.

**5. Then the architectural items** from
`.claude/architecture-analysis-messages-and-connection.md`: one host health
state machine (kills the two-writer banner), retire `/api/live/stream`, and
replace the pump's bare `setInterval` fan-out.

**Sequencing note:** steps 1 and 2 are independent and both low-risk. Step 3 is
the real fix for symptoms 2 and 3, and it should not be attempted before step 2,
because there is currently no way to tell whether it worked.
