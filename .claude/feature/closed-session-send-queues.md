# Feature: closed-session send shows as a queued message until the reopened session records it

## User Story

As someone reopening a conversation from the session list or a search result, I want a
message I send to a **closed** session to appear as a *queued* message — the same waiting-room
treatment a message held behind a running turn gets — and to become a blue (accent) bubble
**only** once the reopened session has actually recorded it, so that "blue" keeps meaning
"the agent has this" and never means "we asked a host to wake up".

## User Flow

1. Open a closed session (from the list, from search, or from a tapped push notification).
2. Type a message and hit send.
3. The message appears **immediately** as a queued row in the pending strip above the
   composer — muted capsule, clock/spinner, the word "Queued" — not as a bubble.
4. The server resumes the conversation (`claude --resume <id> "<prompt>"`, a real 1–6s
   round-trip; Claude continues into a NEW sessionId, Codex resumes in place). The row
   stays queued for the whole of that.
5. When the resumed session writes the message as a real user turn and this client's
   transcript has it, the queued row disappears in the same render pass that the real
   **blue** user bubble appears. The message visibly *moves* into the conversation.

## Current behaviour (the gap)

`SessionStore.sendWithAttachments` (ios/LFG/SessionStore.swift:2818-2842) classifies this as
a **wake-up** send and creates the `PendingSend` with `showSent: true, confirmed: false` — a
**muted gray transcript bubble** with a "Waking session…" spinner
(`OptimisticUserBubble`, ios/LFG/Components.swift:389-448).

Two problems:

1. It is rendered as a bubble, not as a queued row, which contradicts the invariant the
   codebase states explicitly at Components.swift:325-329 — *"the bar is the waiting room;
   the blue bubble means received."*
2. On the send POST returning it sets `confirmed = true` (SessionStore.swift:2909-2919), so
   it turns **blue the moment the host accepts the resume request** — before the resumed
   agent has recorded anything. The server compounds this: the resume branch calls
   `recordImmediateMessage` (src/commands/serve.ts:2194), which persists the message as
   `status: "delivered"` and journals a `delivered` ack **immediately**
   (src/sendq.ts:214-239). The client's `applyQueueAck` (SessionStore.swift:2576-2586) then
   *removes* the pending row outright on that ack, whether or not the transcript has the
   turn yet.

So today the sequence is: gray bubble → blue bubble (on POST return) → row dropped on the
premature `delivered` ack → real turn arrives later. The user's ask is: queued row → (nothing
changes) → real blue bubble the instant the reopened session's transcript has it.

## Success Criteria

- [x] **SC1:** Sending to a session whose `closed == true` (or a carried-forward
      focused/deep-linked session missing from the live list) produces a **queued row in the
      pending strip**, not a transcript bubble — i.e. the `PendingSend` has
      `showSent == false` and a new `queuedForResume == true`.
      **Verify by:** new LFGCore unit test over the extracted classifier
      (`OutgoingSendPresentation`), asserting the wake-up case maps to the strip; plus the
      simulator recording in SC5.
- [x] **SC2:** The queued row carries the "Queued" affordance — the word "Queued" plus the
      ellipsis tap hint, same as the offline-queued row. It keeps the spinner rather than the
      offline row's clock, because a resume is actively in progress where an offline row is
      dormant; a plain `queuedBehindTurn` row shows neither label nor clock, so all three
      remain distinguishable.
      **Verify by:** simulator screenshot of the strip while a closed session is resuming.
- [x] **SC3:** The row does **not** turn blue when the send POST returns. It stays queued for
      the entire resume round-trip.
      **Verify by:** unit test that applying a `resumed: true` send response to a waking
      `PendingSend` leaves it un-promoted; plus the SC5 recording (row is still "Queued"
      after the host has accepted, before the turn lands).
- [x] **SC4:** A `delivered` queue ack does **not** drop the optimistic row while the
      matching user turn is absent from this client's local transcript; it triggers a history
      fetch and the row survives until the turn is present.
      **Verify by:** new LFGCore unit test over the extracted ack policy
      (`QueueAckResolution`), asserting `.awaitTranscript` when the turn is absent and
      `.remove` when present.
- [x] **SC5:** End-to-end in Simulator against a real host: send to a closed Claude session →
      row reads "Queued" throughout the resume → the row is replaced by a **blue** user bubble
      in the reopened (new-id) session, with the agent replying to it.
      **Verify by:** `ios_visual_evidence_auditor` recording of the full flow.
- [x] **SC6:** No regression to the three existing send paths — idle send (instant blue
      bubble), busy send (queued row behind the running turn), offline send (queued row,
      "Will send when reachable").
      **Verify by:** existing + new LFGCore tests, and the auditor exercising an idle send
      and a busy send on the same build.

## Platform & Stack

- **Platform:** iOS (SwiftUI, iOS 26), shipping via TestFlight
- **Language:** Swift 6, strict concurrency complete
- **Key frameworks:** SwiftUI, `@Observable`, GRDB-backed `LFGStore` outbox
- **Layers touched:** `ios/LFGCore` (new pure classifiers + tests), `ios/LFG/SessionStore.swift`,
  `ios/LFG/Components.swift`, `ios/LFG/SessionDetailView.swift`

## Test Strategy

The two decisions that matter are pure functions of already-`Sendable` inputs, so both move
into `LFGCore` behind small enums and are unit-tested there — matching the repo convention
that non-UI logic lives in `LFGCore` with a test (`ios/CLAUDE.md`, "Conventions").

1. **`OutgoingSendPresentation`** — given `(isClosedOrAbsentFromLiveList, hasPrompt, isBusy,
   isOffline)`, returns `.sentBubble | .queuedBehindTurn | .queuedForResume | .offlineQueued`.
   Today this is four booleans computed inline in `sendWithAttachments`; extracting it makes
   every combination assertable and stops the next change re-deriving it.
2. **`QueueAckResolution`** — given `(ackKind, transcriptHasMatchingUserTurn)`, returns
   `.remove | .awaitTranscript | .markFailed`. Encodes the "only remove after the turn is
   local" rule that `correlatePending` already follows and `applyQueueAck` currently doesn't.

## Steps to Verify

1. `cd ios/LFGCore && swift test`
2. `flowdeck simulator boot "iPhone 17 Pro"`, build + install the app, point it at a live host.
3. Find a **closed** Claude session, open it, send a marker message.
4. Observe: queued row throughout the resume; blue bubble only once the turn lands.
5. Regression: idle send → instant blue; busy send → queued row; offline host → "Will send
   when reachable".

## Implementation Phases

### Phase 1: LFGCore classifiers + tests

- Scope: add `OutgoingSendPresentation` and `QueueAckResolution` to `ios/LFGCore` with unit
  tests covering every case.
- Success criteria covered: SC1 (logic half), SC3 (logic half), SC4.
- Verification gate: `swift test` green in `ios/LFGCore`.

### Phase 2: Wire SessionStore + rendering

- Scope: `PendingSend.queuedForResume`; `sendWithAttachments` uses the classifier; the send
  response no longer promotes a resume row; `applyQueueAck` consults `QueueAckResolution`;
  `PendingStripView` renders the resume row with the "Queued" affordance; the queued-message
  dialog offers only Remove for a resume row (there is no server queue entry to interrupt or
  edit — the text was handed to `claude --resume` as its kickoff prompt).
- Success criteria covered: SC1, SC2, SC3, SC6 (build-level).
- Verification gate: app builds; `swift test` still green.

### Phase 3: Live verification

- Scope: no code. Simulator run on iPhone 17 Pro + `ios_visual_evidence_auditor`.
- Success criteria covered: SC2, SC5, SC6.
- Verification gate: auditor `PASS`.

## Decision Log

_Decisions made autonomously — review asynchronously._

- **Queued row, not a muted bubble.** The user asked for "a queued message". This codebase
  already has exactly one meaning for that: a capsule row in `PendingStripView`. Reusing it
  (rather than inventing a third bubble style) also restores the stated invariant that an
  accent bubble means received. The existing "Waking session…" muted-bubble treatment is
  removed for the closed-session case.
- **Client-side fix, not server-side.** The premature `delivered` comes from
  `recordImmediateMessage` on the server's resume branch. Changing the server's status would
  ripple through the outbox state machine, the desktop app, and the web UI, none of which
  asked for this. The client already has a documented policy — *only remove a bubble after
  the matching user turn is present locally* (`correlatePending`, SessionStore.swift:2533-2538)
  — and `applyQueueAck` is simply inconsistent with it. Making the ack path obey the same rule
  is the smaller, more principled change.
- **No promotion timeout.** A waking row could in principle sit "Queued" forever if the resume
  succeeds but no user turn ever appears. `correlatePending` already accepts that same risk
  today for delivered-but-unmatched rows, and adding a timer that flips the row to blue
  without the turn would reintroduce exactly the lie this feature removes. The escape hatch
  is the row's Remove action instead.
- **Remove-only dialog for a waking row.** "Send now (interrupt)" and "Edit" both assume a
  server queue entry that can be pulled back. The resume path has none — the text is the
  process's kickoff argument. Offering them would be a no-op dressed as an action.

## Verification Evidence

Environment: iPhone 17 Pro simulator `FEB585EE-283E-4D0D-B578-5A77CA57D384`, app built
from this working tree, pointed at the live host `http://127.0.0.1:8766` (Eugenes-MacBook-Pro).
Throwaway Claude sessions created in `~/lfg-verify-0899b223` and closed via
`POST /api/sessions/:id/close`, so no real conversation was resumed.

Evidence directory: `.claude/evidence/20260812-closed-session-queued/`

| SC | Method run | Observed | Artifact |
|---|---|---|---|
| SC1 | Send to a closed session found via search (`CHARLIE`), captured the frame right after the send tap | Message appears as a **strip row**, not a bubble: spinner + text + "Queued" + ellipsis | `01-queued-immediately-on-send.png` |
| SC1 | `swift test` — `OutgoingSendPresentationTests` (9 cases) | All pass; `sessionNeedsResume` → `.queuedForResume`, never a bubble, never confirmed | see `swift test` output below |
| SC2 | Same run, frame at t=6s of the recording | "Queued" label + ellipsis affordance, identical chrome to the offline-queued row | `02-queued-row-while-resuming.png` |
| SC3 | Same frame — the nav header already reads **"Running"**, i.e. the host had accepted the resume and the pane was live, while the row was still "Queued" | The send response does **not** promote the row | `02-queued-row-while-resuming.png` |
| SC4 | `swift test` — `QueueAckResolutionTests` (4 cases) | `delivered` + turn absent → `.awaitTranscript`; `delivered` + turn present → `.remove` | see `swift test` output below |
| SC5 | Full flow recorded end to end (`DELTA5520`) | t≈6s queued → t≈9s **blue user bubble**; agent replies `DELTA5520` | `queued-to-blue.mov`, `03-blue-when-transcript-lands.png`, `04-agent-reply.png` |
| SC6 | Busy send (`ECHO88`) and follow-up send (`FOXTROT9`) on the now-live session | Both take the plain `queuedBehindTurn` strip row (spinner + ellipsis, **no** "Queued" label — visually distinct from a resume row) and both resolve to blue bubbles with replies | `20-idle-send.png`, `21-idle-send.png`, `22-foxtrot.png` (scratchpad) |
| SC6 | Offline send against a stub host on `:8767` (30-line Bun stub serving one fake live session, per memory `lfg-stub-host-offline-repro`), killed after opening its session | Composer notice "Stub is unreachable — messages will send when it's back"; the send produced a **clock icon + "Queued" + ellipsis** row, and its tap dialog still offered Try sending now / Edit / Remove | `12-regression-offline-queued.png` |

### Independent audit — PASS

`ios_visual_evidence_auditor`, its own simulator (`6A6ADA9C-CB83-45D5-874B-A3953C55A063`,
iPhone 17 Pro / iOS 26.3), three independent closed-session runs, judged blind against the
criteria. Report and artifacts: `.claude/evidence/20260812-closed-session-queued-audit/evidence.md`.

All five criteria it was given returned PASS, including an accessibility-tree capture proving
the row sits above the composer rather than in the transcript, and frames showing the row still
reading "Queued" while the nav subtitle already reads "Running". No frame at its 0.8s sampling
cadence ever showed the queued row and the blue bubble simultaneously.

Findings it raised, both outside this change:

1. **A client can read "Connected" with a dead event stream.** In its first app instance the
   agent's reply sat on the host for 3.5 minutes while the transcript stayed stale; it
   reproduced on a **freshly created, never-closed** session, `GET /api/events` showed the
   server had journalled both deltas, and relaunching fixed it outright. Not caused by this
   diff — but worth its own investigation, since "Connected + dead stream" is
   indistinguishable from a quiet host. (It is also plausibly the same underlying gap that
   `watchForResumeLanding` works around.)
2. **The resume row and the offline row differ only by their leading glyph** (spinner vs
   clock); label and affordance are identical. That is the recorded design decision above, but
   it is a thin distinction.

```
$ cd ios/LFGCore && swift test
Test Suite 'OutgoingSendPresentationTests' passed
Test Suite 'QueueAckResolutionTests' passed
Test Suite 'All tests' passed
Test run with 43 tests in 6 suites passed
```

### Bug found and fixed during verification

The first live run **failed SC5**: the row stayed "Queued" indefinitely even though the
server transcript already held both the user turn and the agent's `BRAVO7731` reply. Leaving
and re-entering the detail view (which forces `loadHistory`) cleared the row and produced the
blue bubble immediately — disconfirming "the reconcile rule is wrong" and confirming "nothing
re-read history while the row waited".

Two gaps meet at the resume path:

- The journal doesn't announce the revived agent's turns. The pane the pump was watching was
  reaped, and this resume was **id-stable** (observed twice: the session kept
  `20fd1857-…`/`b940f026-…` and got a new tmux pane), so the pump's message baseline for that
  sessionId can already sit past the bytes the new pane writes.
- `reconcilePendingViaQueue`, the client's own safety net, only fetches history for a row that
  carries a `serverQueueID`. A resume send has none — its text was the process's kickoff
  argument, never a queue entry (`recordImmediateMessage` persists the row but never pushes it
  into the in-memory queue, so `GET /queue` returns `[]`).

Fixed with `SessionStore.watchForResumeLanding(clientId:)` — a bounded, self-cancelling
2s history poll started only when a send comes back `resumed: true`, stopping the moment the
row is retired and giving up after ~60s (leaving the row visibly queued rather than
pretending). Re-verified on a rebuilt app: queued at t≈6s, blue at t≈9s.

## Residual Risks

- **Relaunch mid-resume.** The durable outbox has no column for "this was a resume", so a row
  restored by `appendPendingFromOutbox` after a cold launch inside the resume window comes back
  with `showSent = (state == "sent")` — i.e. as a bubble, not a queued row. The window is the
  few seconds between the POST returning and the `delivered` ack deleting the outbox row, and
  the message itself is never lost. Not fixed here; it would need an outbox schema change.
- **`OptimisticUserBubble`'s unconfirmed branch is now unreachable.** Kept as defence in depth
  (muted colour + "Sending…") so the invariant holds if a future path routes an unconfirmed
  send to the bubble surface.
- **Not exercised:** Codex sessions (id-stable resume by a different route), a resume that
  fails with 409 "live on another host", multi-line/attachment sends down the resume path, and
  cold-launch-mid-resume.
- **Found while verifying, NOT fixed (pre-existing, out of scope):** removing a host in
  Settings crashes the app. `HeaderStatusLine` (ios/LFG/SessionListView.swift:859) iterates
  `ForEach(settings.hosts.indices, id: \.self)`, so when the collection shrinks 2 → 1 the body
  still subscripts index 1 — `Array._checkSubscript` trap, crash report
  `~/Library/Logs/DiagnosticReports/LFG-2026-08-12-184930.ips`. One-line fix (iterate the
  elements, keyed by `host.id`), deliberately left out of this diff.

## Shipped

TestFlight build **202608121934** (train `1.2.0`), uploaded 2026-08-12 19:36 from
`Eugenes-MacBook-Pro` via `bundle exec fastlane ios deploy_testflight`.
Log: `ios/fastlane/deploy-20260812-193500.log`.

Carries this change plus the directory-filter active-state fix. **Built from a dirty
working tree** — the binary does not correspond to any commit.

## Bugs

- ~~Resume send's row never cleared because nothing re-read history~~ — fixed above, re-verified.
