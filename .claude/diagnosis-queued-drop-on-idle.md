# Diagnosis — "queued messages keep dropping after the session finishes / goes idle"

## Symptom (user)
Message queued while the session is busy; when the session finishes its turn and
moves back to idle, the queued message drops (not delivered to the agent).
Recurring.

## What I verified (live, on the running server + a throwaway busy session)

### Happy path is robust — 5/5 delivered, no drops
Reproduced via API on a throwaway Claude session: enqueue a busy-inducer
(for-loop w/ sleeps → agent busy), enqueue a unique marker WHILE busy, then
poll the queue + **the tmux pane's `isBusy`** through the busy→idle transition.
- Every run: marker held `pending` while the pane was busy, then delivered
  (`pending→sending→delivered`) ~1s after the pane went truly idle. The agent
  received it every time.

### Important gotcha found: two different "busy" signals
- `/api/sessions` REST `busy` = **transcript-activity window**
  (`Date.now() - lastActivityAt < REST_BUSY_WINDOW_MS`, `sessions.ts:1076`).
- The pump's `agentBusy()` = **pane scrape** `isBusy()` (`tmux.ts:736`, matches the
  live spinner meter `(4m 37s · …)` or `esc to interrupt`).
- These disagree during a turn's tail: REST can read idle while the pane still
  shows the spinner. My first repro polled REST and saw a bogus "19s idle gap";
  re-measuring against the pane showed the pump actually kicks ~1s after **true**
  idle. So the pump latency is fine — but any client/tooling that trusts REST
  busy will show a session as "idle" while a message is legitimately still held.

### Client does NOT drop on idle
`SessionStore.apply(.busy)` just sets `busy[sid]`; nothing clears `pendingSends`
on a busy→idle transition. Pending bubbles drop only when the real user turn
surfaces (`reconcilePending`) or the server marks the item `delivered`/it vanishes
(`correlatePending`). So no client-side silent drop on idle.

### No stuck messages anywhere right now
Scanned all 19 live sessions' queues: zero messages stuck in `queued`/`failed`/
stale-`pending`. No live instance to autopsy.

## Could NOT reproduce the drop synthetically
The clean "queue while busy → idle → deliver" path always delivered. The drop
needs a condition the synthetic test doesn't hit. Leading suspects (all involve
the message entering Claude's NATIVE queue — status `queued` — rather than staying
held-in-lfg `pending`):
1. **Turn ends with a selector open** (permission / AskUserQuestion). `deliver()`
   Escapes the selector up to 2× to reach the composer; if it won't dismiss →
   `failed` ("answer it first"). Real sessions that aren't in bypass-permissions
   mode hit prompts constantly; the throwaway was bypass-mode so I couldn't.
2. **Native-queue drop + re-drive gap:** message goes `queued`, Claude drops it
   (Escape/interrupt/supersede) without running; `reconcileQueued` should re-drive
   on confirmed idle, but if the pane never reads cleanly idle (flip-flop) it can
   stay `queued` and never re-drive.
3. **Duplicate-text false-promote:** `reconcileQueuedCore` promotes on a 48-char
   substring `.some()` match, so a queued message can be marked `delivered` by an
   *earlier identical* user turn (noted latent in `diagnosis-queued-never-pickup`).

## Instrumentation left running (zero server-restart risk)
`.claude/queue-drop-watcher.mjs` → `.claude/queue-drop-watch.log`. Standalone
poller (1.2s) that logs every per-message status transition across all sessions
and prints `*** DROP ***` + a pane snapshot when a message leaves a live state
(pending/sending/queued) and vanishes without ever hitting `delivered`.
Self-tested: captured `pending→sending`. When the drop recurs, the log has the
exact transition sequence + what the TUI was showing.

## Next step
Catch one real instance: note the session id + rough time when it drops, then
cross-reference `queue-drop-watch.log` (transition + pane) and the session
transcript (did the queued text ever appear as a user turn?). That pins whether
it's suspect #1/#2/#3. A deterministic fix should follow from the captured pane.
