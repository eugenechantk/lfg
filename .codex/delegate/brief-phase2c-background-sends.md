# Delegation Brief: phase2c — sends via background URLSession (SPEC; execution owner TBD)

> Status: **spec complete, do not execute yet.** This touches the optimistic-send reconcile stack
> (`ios/CLAUDE.md` flags it as high-risk) and `ios/LFG/*` is under active edit by another session.
> Whoever executes (Codex or a Claude session) must re-read the files fresh at execution time.

**Goal:** a send handed to the system survives app suspension AND app death: the user hits send,
immediately pockets/kills the app, and the message still reaches the host exactly once — with the
existing optimistic bubble resolving correctly on next launch.

## Why background URLSession

Today `SessionStore.dispatchSend` runs a standard data task under a ~30s background-task
assertion — suspension usually doesn't kill it, app death always does. A background
`URLSessionConfiguration.background` session is completed BY THE SYSTEM out-of-process: upload
tasks run to completion after suspension/kill, and the app is relaunched (in background) to
receive the results via `handleEventsForBackgroundURLSession`.

## Spec

### New: `BackgroundSender` (app target, `ios/LFG/BackgroundSender.swift`)

- Owns one `URLSession` with `URLSessionConfiguration.background(withIdentifier:
  "com.eugenechan.lfg.send")`, `isDiscretionary = false`, `sessionSendsLaunchEvents = true`,
  delegate-based (background sessions cannot use async/await task APIs).
- `enqueue(sid:hostURL:body:clientKey:) `: serialize the POST body JSON to a file under
  `Application Support/pending-sends/<clientKey>.json` (the file IS the persistence), then
  `uploadTask(with: request, fromFile:)` with `taskDescription` = compact JSON
  `{clientKey, sid, hostURL}`. File-based upload is REQUIRED for background sessions.
- Delegate:
  - `didReceive data` → accumulate per task (background upload tasks do deliver response bodies).
  - `didCompleteWithError`:
    - success + HTTP 2xx → delete the pending file, decode the server's `{msg}` response, hand
      `{clientKey, serverMsg}` to `SessionStore` (existing pending-send resolution path — the
      same data the current in-process send path gets).
    - failure/non-2xx → keep the file, hand `{clientKey, error}` to the store → existing failed
      bubble + Retry UI.
  - `urlSessionDidFinishEvents(forBackgroundURLSession:)` → call the stashed AppDelegate
    completion handler on the main queue.
- Launch reconcile: on app start, list `pending-sends/*.json` and `session.getAllTasks()`:
  - file has a live task → leave it (in flight).
  - file with NO task → the send died before/without completing. Do NOT blind-resubmit: mark the
    corresponding pending bubble failed so the EXISTING duplicate-safe retry path
    (`reconcilePendingViaQueue` → `retryPending`) decides. Exactly-once beyond that arrives with
    Track B's server-side `clientId` idempotency; do not attempt to build it here.

### Changed: `SessionStore.dispatchSend`

- Routes ALL message sends (`/api/sessions/<id>/send` POSTs) through `BackgroundSender.enqueue`
  instead of the direct client call. The optimistic bubble, pendingSends bookkeeping, and
  reconcile-by-text machinery stay EXACTLY as they are — only the transport changes; the server
  response still reaches the same resolution code, just via the delegate.
- The UIKit background-task assertion in `dispatchSend` becomes unnecessary for the transfer
  itself; KEEP it for now (it also covers the optimistic-state bookkeeping window).
- Non-message POSTs (rename, stop, model, etc.) stay on the direct path — they're user-attended.

### AppDelegate

- `application(_:handleEventsForBackgroundURLSession:completionHandler:)` → stash the handler
  (identifier must match), recreate `BackgroundSender` (recreating the session with the same
  identifier reattaches to in-flight tasks), let the delegate drain.

## Verification (behavioral gates — must be run on simulator/device, not just unit tests)

1. Unit: pending-file round-trip; launch-reconcile decision table (file+task → wait; file-only →
   failed bubble; neither → no-op). Pure logic in LFGCore where possible, with tests.
2. Build green; existing suites green.
3. **Gate C1 (suspension):** send → immediately background the app → message appears in the
   session transcript on the host (server log / transcript check), bubble resolves on return.
4. **Gate C2 (death):** send → immediately kill the app (swipe up) → message still delivered by
   the system → on next launch the optimistic bubble resolves (not duplicated, not stuck).
5. **Gate C3 (no duplicates):** run C1/C2 ten times; count user turns server-side == sends.

## Definition of done
- [ ] All sends transport via the background session; response resolution unchanged.
- [ ] Launch reconcile per decision table; no blind resubmits.
- [ ] Gates C1–C3 pass with evidence (server-side turn counts).
- [ ] No changes to reconcile-by-text logic itself.
