# Stop / Close don't work — diagnosis

**Date:** 2026-08-06 · **Host:** Eugenes-MacBook-Pro · **Reported session:** `cy-001114-96215`
(sessionId `dc902159-095c-4c81-85a3-a90bfb8cf9fb`)

## TL;DR

Three independent defects, all confirmed live on this host. None is "the request didn't
arrive" — the server answers `200 {"ok":true}` in every case, including when it did nothing.

| # | Defect | Affects | Evidence |
|---|---|---|---|
| 1 | `interrupt` returns `ok` from a tmux exit code, never checks the turn stopped | Stop | reproduced on `cy-001114-96215` |
| 2 | A turn that starts and never ends latches `busy: true` forever; sending into a blocked session flips it from "blocked" to "running" | Stop, state | transcript rows 314/317 |
| 3 | `close` kills only the **first** pane claiming a sessionId; duplicates survive and the row comes back | Close | 2 live sessionIds each own 2 panes right now |

Plus a client-side amplifier: `SessionDetailView.swift:144` dismisses the detail view on a
**failed** close, so a no-op looks like a success until the row reappears.

---

## Defect 1 — `interrupt` confirms nothing

`src/commands/serve.ts` interrupt handler:

```ts
if (!tmuxInterrupt(sess.tmuxTarget)) return err(502, "interrupt failed");
return json({ ok: true });
```

`src/tmux.ts:1079`:

```ts
export function tmuxInterrupt(target: string): boolean {
  return Bun.spawnSync(["tmux", "send-keys", "-t", target, "Escape"]).exitCode === 0;
}
```

`send-keys` exits 0 whenever the **pane exists**. It says nothing about whether the process
inside the pane read the key, let alone acted on it. Every Stop tap returns `{"ok":true}`.

**Reproduced.** `POST /api/sessions/dc902159-…/interrupt` → `200 {"ok":true}`. Two seconds
later the session was still `busy: true`; the pane capture was byte-identical to before.

This is the same class of bug as the send path found on 2026-08-04: an endpoint that reports
delivery from the exit code of the transport rather than from the observed effect.

## Defect 2 — why a wedged session reads "running"

**Correction to an earlier draft:** this is not the frozen pane spinner. `journal-pump.ts:209`
is `verdict != null ? verdict.state === "running" : paneBusy` — the transcript verdict wins and
`paneBusy` is never consulted. The operative signal is the **transcript**, not the pane.

The last four rows of `dc902159-…jsonl`:

| # | type | role | timestamp | notes |
|---|---|---|---|---|
| 314 | assistant | assistant | **2026-08-04T16:13:34** | `isApiErrorMessage`, `apiErrorStatus: 403`, `error: authentication_failed` |
| 315 | system | — | 2026-08-04T16:13:34 | |
| 317 | **user** | user | **2026-08-06T01:33:23** | "Can we take a look at the launchd scripts…" |
| 318–321 | attachment | — | | |
| 322 | last-prompt | — | | |

Row 314 is exactly the row `computeStatus` is built to catch — it has an explicit
`code === "authentication_failed" || httpStatus === 403 → blocked / auth_required` branch. On
Aug 4 this session correctly read **blocked**.

Then, ~33 hours later, a message was sent into it. That single user row did two things:

1. **It displaced the 403 as `last`.** `computeStatus`'s first line is
   `const text = last.role === "assistant" ? last.text : ""`, then `if (!text) return ok`. A
   user turn short-circuits before any error branch is reached. **blocked → ok.**
2. **It became the newest decisive row for `transcriptTurnState`.** Scanning back:
   `last-prompt` → null, `attachment` ×4 → null, `user` with content, not an interrupt, not
   meta → **`"running"`**.

The host is logged out, so no assistant row and no `turn_duration` ever follow. Both signals
latch permanently. The transcript has not grown since 01:33:23 — 8 hours at the time of the
report — and nothing notices, because `transcriptTurnState` is deliberately clock-free:

> ORDERING DECIDES, NOT TIMESTAMPS … Scanning back and taking the first decisive record needs
> no clock at all. — `src/turn-state.ts:19`

That is the right call for two synced hosts with skewed clocks, and it is exactly what makes an
abandoned turn immortal. A turn that started and never ended is indistinguishable from a turn
still in progress. (`transcriptRecent`, the freshness heuristic that *would* catch this, exists
at `sessions.ts:1246` but only as the `??` fallback when there is no verdict and no pane.) The
size-keyed memo at `turn-state.ts:113` seals it: unchanged file size → cached verdict, never
rescanned.

**So: "running" is not an assertion that anything is happening.** It is the bottom of the
client ladder — `closed → prompt → isBlocked → busy` — the state left over when nothing else
claims the session. There is no "stalled" state to fall into.

### The staleness fallback exists — twice — and neither copy can fire here

There are exactly two "no activity for a while → idle" rules in the server, and both are wired
as a fallback for the **absence** of a verdict, never as a **check on** one:

| rule | where | guard that excludes us |
|---|---|---|
| `REST_BUSY_WINDOW_MS = 12_000` → `transcriptRecent` | `sessions.ts:1223`, used at `:1246` | `turn != null ? turn === "running" : (paneBusy ?? transcriptRecent)` — `turn` had an opinion, so `transcriptRecent` is never evaluated |
| `BARE_BUSY_WINDOW_MS = 4_000` | `journal-pump.ts:34`, used at `:188` | sits inside `if (!w.target)` — the pane-less branch. We had a pane. |

(`PANE_BUSY_TTL_MS` in `activity.ts` is a cache TTL on the pane note, not a staleness rule.)

A normal pane-backed session with a readable transcript — the overwhelmingly common case —
takes **neither** branch. Both timeouts are dead code on the main path.

### The lease doesn't catch it either — and that is the general shape of the bug

The lease is the obvious candidate: it is the one record with a heartbeat and an expiry
(`LEASE_FRESH_MS = 90_000`). It carries turn state too — `state` / `stateAt` / `stateEvent`,
written by `scripts/lfg-agent-hook.py`, read by `hook-state.ts`, and arbitrated against the
transcript by recency in `sessionTurnState`. The hook **is** registered and **does** work;
a healthy session's lease looks like:

```json
{ "hostId": "2b178534-…", "pid": 85375, "acquiredAt": …, "heartbeatAt": …,
  "state": "idle", "stateAt": 1785982308455, "stateEvent": "Stop" }
```

It didn't help here for two separate reasons.

**1. The hook layer latched "running" too, from the same event.** The hook's event map is:

```python
"UserPromptSubmit": "running",
"Stop":             "idle",
"StopFailure":      "idle",
"SessionEnd":       "ended",
```

The message sent at 01:33:23 fired `UserPromptSubmit` → `state: "running"`. Then the turn died
on the 403, and `Stop` never fired. The script's own comment says exactly this:

> Claude Code fires Stop only on a clean turn end — an ESC interrupt fires nothing at all,
> leaving "running" behind. That stale value is expected…

So `sessionTurnState` was arbitrating **two "running"s** by recency. `session-state.ts` argues
that a stale hook value "cannot mislead… an outdated one simply loses" — which holds only while
*something* eventually says idle. Here nothing ever does.

**2. `heartbeatAt` measures the wrong thing.** It is not written by the agent. `startLeaseHeartbeat`
(`serve.ts:829`) walks `listSessions()` every 30s and `ensureLease`s each one — so the lease stays
fresh for exactly as long as **lfg can see the pane**. That is the right signal for `closed`
("nothing holds a fresh lease", `sessions.ts:1703`) and says nothing at all about whether the
agent is making progress.

**The general shape:** three layers claim to know turn state — hook, transcript, pane — and all
three are **edge-triggered on turn boundaries**. A turn that dies mid-flight emits no edge in any
of them:

| layer | opening edge | closing edge | fired here? |
|---|---|---|---|
| hook | `UserPromptSubmit` → running | `Stop` (clean end only) | open yes, close **never** |
| transcript | user row → running | `turn_duration` | open yes, close **never** |
| pane | spinner painted | spinner repainted away | open yes, close **never** |

The single level-triggered, clock-based signal in the system is the lease heartbeat — and it is
sourced from the *server observing a pane*, not from the agent doing work. So nothing anywhere in
the stack is both time-based **and** sourced from actual agent progress. The one piece of evidence
that qualifies is transcript mtime, which is computed as `transcriptRecent` and then discarded on
the main path.

The reasoning that put the staleness rules where they are is at `sessions.ts:1229`:

> Pane-backed sessions ONLY: a live pane is the proof the process still exists. Without it, a
> transcript that simply ends mid-turn — crashed, or a stale row sitting on a recycled pid —
> would read "running" forever, which is the exact latch this change exists to remove.

That is sound as far as it goes, and it hides the hole: **"the process exists" is not "the turn
is in flight."** The pane guard defends against a *dead process*. Nothing defends against a
*live process with a dead turn* — which is exactly this case. pid 76911 was alive and healthy
the whole time; only its turn was dead, for 8 hours.

Two consequences:

1. **Sending a message to a blocked session converts it to "running."** The act of asking a
   wedged session to do something erases the evidence that it can't. This is a plain ordering
   bug in `computeStatus`: it should scan back for the last *assistant* turn, not give up when
   the last row happens to be a user turn.
2. `SessionDetailView.swift:311` only shows **Stop** `if isBusy` — so Stop is offered precisely
   on the sessions where there is no turn to stop, and Escape into a logged-out process changes
   nothing. Defects 1 and 2 compound into "Stop does nothing, forever."

## Defect 3 — `close` kills one pane out of N

`src/commands/serve.ts:2325`:

```ts
const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
```

`.find` — first match only. `resolvePaneOwners` (`src/sessions.ts:1495`) dedupes the
**one pane → many pids** direction (a TUI's daemon/worker children). It does not handle the
inverse, **one sessionId → many panes**, which happens when a transcript gets resumed into a
second pane while the first is still running.

Live on this host right now:

```
c7d0c9e8-1b86-46b3-b641-28bf50067b9c   lfg-b7fee2        pid 65399  managed=true
c7d0c9e8-1b86-46b3-b641-28bf50067b9c   cy-000647-68658   pid 68901  managed=false

9cb230b0-54bd-4c74-b0be-705504df4530   cy-234305-31300   pid 31636
9cb230b0-54bd-4c74-b0be-705504df4530   cy-221537-92607   pid 92862
```

Both panes are alive with distinct pids and distinct `tmuxTarget`s. `MultiHost.mergeSessions`
dedupes to one row client-side (first-wins), so the user sees a single session. Close it and
the server kills `lfg-b7fee2`, tombstones pid 65399 — and `cy-000647-68658` keeps returning
the same sessionId on the next poll. **The row comes back and the agent is still running.**

Note this is not what happened to `cy-001114-96215` specifically: that one had a unique pane,
and `POST /close` against it worked (tmux session gone, pid gone, row gone). Defect 3 is the
mechanism behind close failing on *other* sessions.

## Amplifier — a failed close still dismisses the view

`ios/LFG/SessionDetailView.swift:144`:

```swift
Button("End session", role: .destructive) { Task { await store.close(sid); onEnded() } }
```

`store.close` returns `Bool` (`run()` returns false and sets `lastError` on failure). The
result is discarded and `onEnded()` runs unconditionally. A close that 404s or 502s looks
identical to one that worked.

## The reason this wasn't diagnosable

`serve.ts` logs **nothing** for close or interrupt — no request line, no outcome, no target.
There is no `data/ops.log`. Exactly the gap that made the send failures unfixable: the
failures leave no trace, so each report starts from zero.

---

## Fix plan

1. **`close` kills every pane for the sessionId.** `.find` → `.filter`; kill each target,
   `markClosed` each pid, then verify the pids are actually gone and escalate to `SIGKILL`
   if not. Return what was killed.
2. **`interrupt` confirms the effect.** After Escape, re-scrape the pane for up to ~1.5s and
   report `stopped: bool`. Client surfaces "Couldn't stop the turn" instead of silence.
3. **`computeStatus` must scan back for the last ASSISTANT turn**, not read `last` and give up
   when it's a user row. A 403 two rows up is still a 403. This alone restores "blocked" on
   every session someone has messaged since it wedged.
4. **Add the one signal that doesn't exist: level-triggered, sourced from agent progress.**
   Every existing layer is edge-triggered on a boundary the dead turn never reached, so no
   amount of re-ordering them helps. The only available evidence of real progress is transcript
   mtime — already computed as `transcriptRecent` and then discarded on the main path.

   **Put it in `sessionTurnState` (`session-state.ts`), not in the callers.** That file is
   already the single definition both `sessions.ts:1246` and `journal-pump.ts:209` consume, and
   it must cover the hook layer too — the hook latched `"running"` here just as hard as the
   transcript did, so guarding only `sessions.ts` would leave the journal path broken.

   ```ts
   // a "running" verdict whose transcript stopped growing is a stall, whichever
   // layer produced it — the hook's UserPromptSubmit latches exactly like the user row
   if (verdict.state === "running" && now - transcriptMtime > STALL_MS)
     return { state: "stalled", source: verdict.source };
   ```

   `transcriptTurnState` itself should stay clock-free — its reasoning about synced-host skew is
   correct, and `session-state.ts` already compares local mtimes for hook-vs-transcript recency,
   so the clock belongs there.

   Window: not 12s. A genuine turn goes silent for the length of one tool call, and Bash alone
   allows a 10-minute timeout, so ~15 min is the first safely-quiet threshold. That is coarse
   enough that it should surface as its own state — **"Stalled"** — rather than silently reading
   idle, so a wedged session stays distinguishable from a finished one. Adding it to
   `sessionDisplayState` means updating `SessionState.swift` and `session-state-parity.test.ts`
   in the same change.
5. **Log close/interrupt to `data/ops.log`** — target, pids, outcome, duration.
6. **iOS: `if await store.close(sid) { onEnded() }`**, and surface `lastError`.
