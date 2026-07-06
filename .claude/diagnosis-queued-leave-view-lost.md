# Diagnosis — "queued message lost after leaving the session view"

## Symptom (user)
On the iOS client: send a message while the session is running (busy) → it shows
as queued. Then leave the session detail view → the message is lost (never
delivered to the agent).

## Static analysis of CURRENT source (both halves are durable)

### Client (`SessionStore.swift`, `SessionDetailView.swift`)
- Composer's `onSend` calls `store.dispatchSend(sid, …)` (SessionDetailView.swift:69).
- `dispatchSend` (SessionStore.swift:557) retains the send `Task` in
  `inflightSends` on the **store** (app-lifetime, `@MainActor @Observable`
  injected at app root) and takes a `beginBackgroundTask` assertion
  **synchronously**. Leaving the view / popping nav / backgrounding cannot cancel
  the send.
- The optimistic `PendingSend` is added to `store.pendingSends` (store-owned), not
  view state — it survives leaving too.

### Server (`sendq.ts`, `serve.ts`)
- `POST /api/sessions/:id/send` → `enqueueMessage` → returns immediately
  (serve.ts:1510). Queue is an in-memory `Map` per session.
- While the agent is busy, `kick()` breaks (hold-in-lfg: message stays `pending`).
- `startQueuePump()` (serve.ts:2128) runs a **client-independent** 1s ticker that
  re-`kick`s every session with `pending` work when it goes idle. Delivery does
  NOT depend on any client being connected or on the detail view being open.

### Deploy-gap check (per repo hazard)
- Running `serve` process: started Jul 1 18:04. `sendq.ts` mtime: Jul 1 02:13.
  Process is NEWER than the pump code, and `startQueuePump()` is wired at
  serve.ts:2128 → **pump is live in the running process.** No server deploy gap.

## Conclusion from static analysis
On the current code, a queued message CANNOT be lost by leaving the view. The
report most likely reflects a **stale device build** (predating `dispatchSend`
d54a720 / the pump 2852acc) — the documented "device didn't get the latest build"
hazard. Verifying on the current build to confirm (real-seam test, not a static
read).

## Live reproduction (current build, simulator) — DONE, COULD NOT REPRODUCE LOSS
Built the latest app onto a fresh sim (`9D7C189B`, iPhone 16 Pro / iOS 26.3),
pointed at `localhost:8766`, created a throwaway Claude session in `inbox`, kept
it busy (long `for … sleep` loop → header "Running"), then:

1. **Sent a marker message while busy:** `QUEUEDMARK please reply with token
   BRAVO9915`. It showed as a muted **pending bar** in the composer area, and the
   server queue confirmed it landed as `status: "pending"` (item `131ba6355c…`)
   — i.e. genuinely held-in-lfg behind the running turn, not delivered yet.
2. **Left the session view** (tapped back → session list).
3. **Polled the server queue from the list view.** At the FIRST poll (~10s after
   leaving) the marker was already `status: "delivered"`, and on re-entering the
   session the agent had replied **`BRAVO9915`** as a real user turn + reply.

→ The queued message was delivered by the **client-independent pump** while the
user was NOT in the detail view. **Not lost.** This matches the static analysis:
on current code the message can't be lost by leaving the view.

Evidence: transcript screenshot shows `QUEUEDMARK…BRAVO9915` as a delivered user
bubble with the agent's `BRAVO9915` reply; queue poll log `t=10s marker=delivered`.

## Verdict
On the CURRENT build, "queued → leave view → lost" does **not** reproduce.
Most likely cause of the user's report: a **stale device build** predating the
durable-send (`dispatchSend`, d54a720) + client-independent pump (2852acc) fixes.
Next step: confirm the build installed on the user's device, or have the user
reproduce so the exact failing state can be captured.

### Not covered by this repro (only genuine remaining gap on current code)
Force-quitting the app in the ~sub-second window between tapping send and the POST
landing (over a slow link) could drop the in-flight POST before it reaches the
server — `dispatchSend`'s background-task assertion covers *backgrounding*, not a
hard force-quit. But "leave the session view" (nav back) keeps the app + store +
send Task alive, so that path is safe (verified above).
