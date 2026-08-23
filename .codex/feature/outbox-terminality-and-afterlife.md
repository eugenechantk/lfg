# Feature: honest "Not sent" — outbox terminality, confirmation, and afterlife

Four parts, all attacking one symptom: **the red "Not sent" warning appearing for
messages that were delivered.** Owner: session `ff4c4e3c`. Not committed, no
TestFlight.

## The four mechanisms, in the order they were found

| # | mechanism | fix |
|---|---|---|
| 1 | Acceptance only set `confirmed`, never cleared `failed`/`queuedOffline`, so a first attempt that failed and a retry that succeeded left the failure chrome on | `applyAcceptance` clears every failure marker, once, for all callers |
| 2 | The resurrection path re-materialised every never-`delivered` row on every launch, never matched against the transcript, never pruned | `OutboxResurrectionPolicy` — retire when the transcript proves delivery, retry inside 24h, surface up to 7d, prune after |
| 3 | The reachable-host drain kept its own cap, measured from `updatedAt` — which `markOutbox` rewrites — so recording a failure reset the row's age and re-armed the send | both consumers call one `outboxDecision(for:store:)`; age comes from `createdAt`, and `.surface` writes nothing |
| 4 | **Terminality was declared on ambiguous evidence** (this document's main subject) | only a server-answered failure is immediately terminal; transport-ambiguous failures enter a bounded confirming state |

## Part 4 — the problem

On a cold tunnel `BackgroundSender.post` throws **after the request bytes went
out**. The server processes the send normally. `settleSendFailure` saw a
reachable host, called it terminal, and fired the banner. Seconds later the turn
arrived over SSE and `reconcilePending` silently cleared the bubble.

The bubble self-healed. The banner the user had already read did not. That is the
one Eugene hits daily.

### Why it couldn't be fixed at the decision site

`settleSendFailure` took no error at all, and `BackgroundSender` flattened every
`URLError` into `LFGError.notReachable(underlying: String)`. The `URLError.code`
that separates "the request never went out" from "the request went out and we
stopped listening" had been destroyed one layer down. Fixing that wrapping is
what made the policy expressible.

## Part 4 — the design

`LFGCore/SendTerminality.swift`, pure and tested:

- `SendFailureEvidence` — `.serverAnswered(status:)`, `.transportFailed(urlErrorCode:)`,
  `.unsendable`. `.from(_ error:)` reads it off whatever was thrown.
- `SendTerminalityPolicy.classify(evidence:hostStillDown:hasAttachments:)` →
  `.terminal` / `.confirming` / `.requeue`.

  **Only the server may declare a message dead.** Host-down and attachments
  requeue as before and outrank everything. A server status is terminal. An
  ambiguous transport code (`timedOut −1001`, `networkConnectionLost −1005`,
  `cancelled −999`) is `.confirming`. An *unknown* code is also `.confirming` —
  "we could not tell why" is not evidence of failure, and defaulting it to
  terminal is precisely the reported bug.
- `DeliveryConfirmationPolicy.next(probesCompleted:foundDelivered:)` →
  `.resolveDelivered` / `.probeAgain(afterMs:)` / `.declareTerminal`.
  3 probes, 5s apart, 15s total. Bounded on purpose: an unbounded confirm strands
  the message with no Retry, which is the same bug pointed the other way.

App side (`SessionStore`):

- `confirmAmbiguousSend` holds the bubble in its in-flight presentation (no red,
  no Retry, **no banner**) and probes.
- `ambiguousSendLanded` accepts two independent proofs: a matching entry in the
  session's **queue** (the host has custody even before the agent runs the turn)
  or a matching user turn in the **transcript**.
- The clientId is held in `replayingOutbox` for the window, so a host link coming
  up mid-confirm cannot re-POST a message that may already have landed.
- If SSE resolves the row first (the common path), the probe finds no pending row
  and exits silently.
- Window closes with nothing found → `markPendingFailed` → exactly one banner.

## Tests

`LFGCore/Tests/LFGCoreTests/SendTerminalityTests.swift` — 13 cases covering the
four scenarios Eugene named plus boundaries:

- server-error (7 statuses) → terminal
- timeout-then-delivered → confirming, resolves at any probe, no banner
- timeout-then-truly-lost → exactly `maxProbes` probes then one terminal
- host-down → requeue regardless of evidence
- unambiguous transport codes (`cannotFindHost` etc.) stay terminal
- unknown code → confirming
- evidence extraction from `LFGError.http` / `.transport` / `.badURL` / raw `URLError`

Full suite: **458 tests, 0 failures** (was 445).

## Live verification

Rig: a TCP proxy in front of the real host that forwards a send in full — the
server really receives and processes it — then swallows the response and closes
the client socket. Exact shape of the bug. Scans every request on a connection,
because URLSession reuses them (a first-request-only version silently passed the
send through and proved nothing).

Target: a throwaway session spawned via `POST /api/sessions/new`, closed after.

### Part 4 — timeout-then-delivered — **PASS**

| observation | result |
|---|---|
| proxy | `matched a send … forwarded upstream` → `upstream answered HTTP/1.1 200 OK` → `swallowed` → `closing client socket with no response` |
| app at t+3s | pending strip, spinner, **no banner, no red** |
| app at t+27s | real accent bubble + agent reply |
| server transcript | **one** user turn (6 URLSession background retries collapsed by the server's `getMessageByClientId` dedupe) |

Evidence: `timeout-then-delivered.mov`, `c_t3.png`, `c_t27.png`.

### Part 3 — reachable-host drain — **PASS** (discriminating)

Two rows seeded into the app's sqlite against the **reachable** host, targeting
the throwaway session; host taken down 90s and brought back to fire the real
drain (`OFFLINE -> live` confirmed in the app's Connection Log).

| row | age | expected | result |
|---|---|---|---|
| `FRESH-DRAIN-CONTROL-2` | 0h | sends | **delivered**, row retired |
| `STALE-DRAIN-PROBE-2` | 72h | never sends | **not delivered**, still `failed`, `updatedAt` still **72h** |

Exactly **one** `POST …/send` reached the host. The stale row keeping its 72h
`updatedAt` is the specific proof for part 3: the drain no longer rewrites the
age that the cap reads.

## Part 5 — the POST boundary (after the second field failure)

Parts 2 and 3 were both correct policy applied at every call site *we had
enumerated*, and both times the enumeration was wrong.

### The culprit, named

**`performRefresh` → `recoveredHosts` → `scheduleResendAfterRecovery` →
`resendFailedSends` → `retryPending`.**

It never touched `retryOutboxRow`, `retryableOutbox`, or any outbox gate, because
it resends through **`retryPending`** — the manual Retry button's function. Three
things make it fire on exactly Eugene's shape and not on my stub test:

1. At cold launch `healthBefore` is empty, so the first refresh's unknown→live
   transition counts as a **recovery**. A host that was reachable from t0 is
   therefore "recovered", and the sweep runs.
2. The sweep selects `pendingSends` entries with `failed == true` — which is
   precisely the bubble `replayPendingOutboxOnStart`'s `.surface` branch had just
   created. **The surfacing branch was feeding its own bypass.**
3. My down→up stub test had the host already known-live before the row existed,
   so `recoveredHosts` was empty and this path never ran. That is why it passed
   while the field failed.

### The fix

`OutboxSendGate.permits(_:trigger:)` in LFGCore, enforced at **both** POST
boundaries — `retryOutboxRow` and `retryPending` — via
`SessionStore.outboxSendPermitted(clientId:trigger:)`, which loads the row,
re-runs `OutboxResurrectionPolicy.decide`, and refuses.

- `.automatic` permits **only** `.retry`. `.surface`/`.retire`/`.prune` never POST.
- `.userInitiated` permits everything except `.retire` (already in the transcript
  — sending it would duplicate a message demonstrably delivered; the Retry button
  had no such guard before).
- `retryPending` defaults to `.userInitiated`; `resendFailedSends` is the one
  caller that must pass `.automatic`.
- A send with no outbox row (fresh compose, placeholder create) passes through.

A new caller is now safe by default: the worst it can do is be refused.

### Verification — Eugene's exact field shape

Build → install → configure host `http://127.0.0.1:8766` → terminate → seed
`zzv2-B`, 3d-old, `state=failed`, targeting throwaway session `2081f0fa` →
**cold launch from the home-screen icon** → wait 60s (ran 80s).

| criterion | result |
|---|---|
| row stays `state=failed` | **yes** — and `updatedAt` still 72h, age never reset |
| zero new sendq events for its text | **0** (0 new sendq lines at all) |
| not delivered into the session | **0 occurrences** in the transcript |
| "Not sent" + Retry bubble **observed rendering** | **yes** — red icon, text, Retry button (`notsent-retry-bubble.png`) — the gap open for two rounds |

**Discriminating control** (a boundary that refused *everything* would also pass
all four): tapping **Retry** on that same row immediately produced **4 sendq
events** and resolved into a real bubble with the agent's reply. Automatic
refused, human permitted.

## Residual risks

- The confirming probe resolves against the **same** sessionId. A send that
  auto-resumed into a *new* sessionId lands in a different transcript, so its
  window could close and declare terminal wrongly. `watchForTurnLanding` covers
  that path separately, and the previous behaviour was an *immediate* false
  banner, so this is strictly better — but it is not proven.
- `run("Retry", …)` sets `lastError` itself before `settleSendFailure` decides,
  so the queued-message retry path can still raise a banner outside the terminal
  rule. Pre-existing, untouched here, and worth a follow-up.
- Live verification used a local proxy standing in for the Cloudflare path. The
  transport failure it induces is `networkConnectionLost`; the daily field case
  is usually `timedOut`. Both are in the ambiguous set and take the same branch.
