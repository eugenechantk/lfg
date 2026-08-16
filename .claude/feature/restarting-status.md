# Feature — "Restarting" session status

**Tier:** product (shipping iOS client)
**Status:** implemented, pending live simulator verification

## Problem

Waking a closed session has a 2–15s window where the list lies about what is
happening:

| Phase | Duration | What the card says today |
| --- | --- | --- |
| Resume POST in flight (`/api/sessions/resume` or a send that auto-resumes) | up to ~6s — the server polls the pidfile for 12×500ms before answering | **Closed** |
| Response returned, revived pane not yet in `/api/sessions` | 1–6s (comment at `SessionStore.carryForwardResume`) | **Idle** (or Working, if a send optimistically set `busy`) |
| Pane live, first journal beat | ~1s | Working |

`group(for:)` checks `s.closed` first, so even the optimistic `busy[id] = true`
that `dispatchSend` sets can't move the row — a session you just told to wake up
sits in the **Closed** section, looking like the tap did nothing. The detail view
already handles this (`OutgoingSendPresentation.queuedForResume` → a "Queued" row
in the pending strip); the *list* does not, and an explicit Resume from the list
menu (no message) has no feedback anywhere.

## Design

A new group, **Restarting**, checked ahead of `closed` — the same reason `closed`
sits outside the shared `SessionDisplayState` ladder applies here: only the client
knows a revival is in flight. The server can't report it, because the window it
would report during is *inside* its own blocking resume request.

Definition, deliberately narrow:

> **Restarting** = this client asked a host to revive this session, and no host
> has yet returned a live row for it.

- **Marked** at three sites: `resume(_:on:)` (before the POST),
  `sendWithAttachments` when the send classifies as `.queuedForResume`, and
  `transfer(_:to:)` (a close + resume elsewhere).
- **Follows the id** through `remap(from:to:)` — Claude resumes into a *new*
  sessionId, so the mark has to move with the row.
- **Cleared** the moment the id appears in `liveIds` during `rebuildSessions`,
  on an explicit resume failure, and by a 45s timeout so a resume that never
  lands falls back to the truth (Closed) instead of spinning forever.

Section order: `needsInput, blocked, restarting, working, unread, idle, closed`.
Adjacent to Working on purpose — that's where the row lands seconds later, so the
transition is one short hop, not a jump across the list. Colour: teal
(#64D2FF/#5AC8FA), distinct from Working green and Idle blue.

The decision logic is `RestartTracking` in `LFGCore` (pure, injected clock, unit
tested); `SessionStore` owns only the marking/clearing call sites.

## Success criteria

1. Sending to a closed session moves its card to a **Restarting** section before
   the HTTP response returns — not on it.
2. Explicit Resume (no message) shows the same, with no message in the strip.
3. The card leaves Restarting as soon as the revived pane is in `/api/sessions`,
   under its NEW id for Claude (id-changing resume) and its same id for Codex.
4. A resume that never produces a live row falls back to Closed within 45s.
5. `runningCount` ("N running") does not count restarting sessions.
6. `swift test` green, including new `RestartTrackingTests`.

## Verification — 2026-08-16

Unit: `cd ios/LFGCore && swift test` — 58 Swift Testing + all XCTest cases pass,
including 9 new `RestartTrackingTests`.

Live: iPhone 17 Pro sim (`5361ED19-…`, FlowDeck session sim) against the Pro's
real host at `http://127.0.0.1:8766`. Created a scratch claude session, closed
it, found it in search under **Closed 24**, opened it and sent "Hi".

| Criterion | Result | Evidence |
| --- | --- | --- |
| 1. Restarting appears before the response | **PASS** — 2s after the send tap the card is under a **Restarting** section with the teal dot; Closed dropped 24 → 23 | `evidence/20260816-restarting-status/list-restarting.png` |
| 3. Leaves Restarting once the pane is live | **PASS** — back on the list ~40s later the same row is under **Idle** (`scratch · sonnet · 2m`), no duplicate Closed card | `…/list-landed-idle.png` |
| 5. Restarting isn't counted as running | **PASS** — header stayed at the host's own busy count (3), which four independent busy sessions on the host account for | same shots |
| 6. Tests green | **PASS** | `swift test` |
| 4. 45s fallback to Closed | **Unit only** — not exercised live | `RestartTrackingTests.testMarkExpiresAfterTheTimeout` |
| 2. Explicit Resume (no message) | **N/A today** — see below | — |

**Finding: `SessionStore.resume(_:on:)` has no UI caller.** Nothing in the app
invokes it; the only user-facing way to wake a closed session is to send it a
message (`transfer` calls the client directly). The mark/clear wiring is in place
for whenever a Resume affordance lands, but criterion 2 can't be exercised until
one exists. Worth deciding separately whether the Closed section should carry a
swipe/menu "Resume" — it's a one-liner now that the status exists.

Incidental observation: on the iPhone layout the resume response calls
`requestSelection(new)`, which pulls navigation back into the detail — so backing
out to the list mid-resume doesn't stick. Correct as designed, just surprising.
