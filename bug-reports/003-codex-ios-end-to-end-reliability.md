# Bug 003: Codex sessions are unreliable and incomplete on iOS

## Status: FIXED AND VERIFIED

## Description

Codex sessions in the iOS client have failures across three connected surfaces:

- follow-up messages error, disappear, or fail to enter the agent's native queue;
- session status alternates between Running and Idle while a Codex turn is open;
- Codex-visible transcript blocks such as commands, tool calls, and code edits are missing.

The expected behavior is end-to-end parity with a live Codex session: one durable
send acknowledgment, stable open-turn status, and every meaningful Codex TUI
block normalized and rendered in order on iOS.

## Steps to Reproduce

1. Start a disposable Codex session through LFG and keep its first turn running.
2. Open that session in the iOS client.
3. While it is running, submit one follow-up and then two rapid follow-ups.
4. Observe whether each message leaves the composer, appears in LFG's queue, is
   accepted by Codex's native next-turn queue, and later becomes a user turn.
5. During the same open turn, make Codex search/read files, run a command, apply
   a patch, call a generic tool, update a plan, and wait for input.
6. Observe the session list/detail status for at least 90 seconds and compare the
   iOS transcript against the normalized server API and the Codex TUI.
7. Interrupt the turn, resume it, send while idle, and repeat the transcript and
   status comparison.

## Root Causes

Four independent races/contracts produced the reported symptoms:

1. **A busy Codex send is steering, not a next-turn queue.** Codex displays a
   busy follow-up as a user event but submits it after the next tool call inside
   the current turn. LFG treated that appearance as durable next-turn delivery,
   acknowledged it, and removed it from its own queue. The requested follow-up
   was therefore visible but never executed as a separate turn.
2. **Codex create/fork was not atomic.** `/api/sessions/new` and the Codex fork
   path could return success with `sessionId: null`, leaving an unaddressable
   managed tmux pane behind.
3. **Close raced cached lease refresh.** Resumable search refreshed leases from
   a briefly cached live-session row. If close tombstoned the pid after that row
   was read, the refresh recreated the lease that close had just released and
   hid the closed transcript for the full 90-second freshness window.
4. **Id-stable Codex resume lost its host route on iOS.** A closed transcript is
   host-agnostic. Codex resumes with the same session id, but `SessionStore`
   updated the row without recording the host that accepted the resume. An
   immediate Stop/End could therefore fail locally without making an HTTP
   request.

The current server normalization and source-built iOS renderer already render
Codex plan, run, edit, explore, and tool-result blocks. The missing-block report
was not reproducible on the current build; it is consistent with a stale client
build or the older incremental reconciliation behavior.

## Success Criteria

The following operations must each work from the iOS client and agree with the
server's durable state:

1. Start a Codex session.
2. Send a follow-up while the session is running.
3. Send a follow-up while the session is idle.
4. Send a follow-up to a closed session (resume it without losing history).
5. Interrupt the current turn with a message.
6. Queue a message without interrupting the current turn.
7. Stop a running session.
8. Fork a session with the expected transcript ancestry.
9. Close a session.

Across the matrix, Running must remain stable for an open turn, every accepted
message must execute exactly once in the intended turn, and plan/run/edit/tool
blocks must render in transcript order.

## Verification Matrix

| Operation | Result | Evidence |
|---|---|---|
| Start a session | PASS | iOS created Codex session `01a000ca-e570-70e2-a9be-c23a0971a914` with a real id and opened it. A forced bind failure returned HTTP 504 and cleaned up its new pane. |
| Follow-up while running | PASS | The row stayed `pending` during the active turn, then became a distinct user turn and produced `LIFECYCLE_QUEUE_DONE`. |
| Follow-up while idle | PASS | `LIFECYCLE_IDLE` delivered once and produced `LIFECYCLE_IDLE_DONE`. |
| Follow-up to closed session | PASS | iOS found the closed fork, resumed the same Codex id, preserved history, and produced `CLOSED_RESUME_DONE` / `CLOSED_RESUME_2_DONE`. |
| Interrupt with a message | PASS | `sleep 60` ended as `aborted by user`; the interrupt message became the next turn and produced `LIFECYCLE_INTERRUPT_DONE`. |
| Queue a message | PASS | Busy Codex message stayed in LFG with attempts `0`, was visible in the iOS queued strip, and drained only after idle. |
| Stop a session | PASS | iOS Stop aborted `sleep 60` after 1.3 seconds; the forbidden completion response never appeared. |
| Fork a session | PASS | Fork `01a000ce-822a-71c3-9bf2-e21693bbe671` retained ancestry and produced `FORK_DONE`; the source transcript did not receive the branch-only turn. |
| Close a session | PASS | iOS End reached the server, killed the exact pane, released the lease immediately, and made the transcript searchable under Closed without the old 90-second delay. |

Additional checks:

- A 45-second tool turn remained continuously `busy=true` and changed once to
  idle at completion; no Running/Idle oscillation occurred.
- The isolated Simulator rendered `Updated Plan`, `Ran`, patch `Added`,
  `Explored`, and tool-result blocks in transcript order.
- A just-resumed session was ended again from iOS before a polling refresh; the
  close request reached the server, proving the restored host route.

## Investigation Log

### Attempt 1

**Hypothesis:** The three symptoms cross server and client boundaries and may
have separate causes: stale deployed server code for delivery, disagreement
between REST/journal turn-state derivation, and incomplete Codex rollout-event
normalization or iOS row rendering.

**Changes:** Created one end-to-end regression record and began comparing the
deployed server, current dirty worktree, real Codex rollouts, normalized API,
and Simulator UI. No production changes yet.

**Result:** The symptoms split into four independently reproducible contracts,
documented above.

### Attempt 2

**Hypothesis:** Codex's busy-composer behavior is not equivalent to Claude's
native next-turn queue even though LFG currently treats both as the same
delivery contract.

**Changes:** Started a disposable Codex session, held the turn open with a
45-second command, sent two rapid server follow-ups, then repeated an idle send
and busy follow-up from an isolated iOS Simulator. Compared the raw rollout,
normalized REST transcript, durable queue rows, and rendered accessibility
tree.

**Result:** Confirmed. LFG marks a busy Codex follow-up `delivered` as soon as it
appears as a user event, but Codex injects that event into the still-open turn.
It does not run as a distinct next turn: `IOS_QUEUE_PROBE` appeared between the
sleep result and the original turn's `IOS_STATUS_DONE`, and Codex never emitted
the requested `IOS_QUEUE_DONE`. Earlier rapid follow-ups behaved identically.
This is observable message loss despite a successful delivery acknowledgment.

The same Simulator transcript did render `Updated Plan`, `Ran`, patch `Added`,
`Explored`, and tool-result rows. Therefore the current normalization and the
current source-built iOS renderer can display these blocks; missing blocks on a
deployed client are likely a stale-build or incremental-reconciliation issue,
not an absence in the authoritative transcript. Further live-delta testing is
still required.

### Attempt 3

**Hypothesis:** Session creation can report success before Codex has produced a
bindable rollout/session identifier.

**Changes:** Started a disposable Codex session in a new temporary directory
through `POST /api/sessions/new` and inspected its tmux pane and process state.

**Result:** Confirmed. The endpoint returned HTTP success with `sessionId: null`
and left a blank managed tmux session. A successful creation must either return
a real session identifier or fail and clean up the session it just created.

### Attempt 4

**Hypothesis:** Holding busy Codex messages in LFG until the structured turn
state is idle prevents Codex steering from being misreported as next-turn
delivery.

**Changes:** Delivery now uses the same structured session `busy` verdict as
REST/SSE. Busy Codex sends remain pending in LFG; Claude retains its native
queue behavior. Codex delivery advances one row at a time so a second pending
row cannot race into a newly starting turn.

**Result:** Passed live. The queued row remained pending throughout the active
turn and executed separately immediately after idle.

### Attempt 5

**Hypothesis:** Rechecking the close tombstone at the lease side-effect boundary
will prevent a cached session enumeration from resurrecting a released lease.

**Changes:** Added `mayRefreshLiveLease` and used it immediately before each
`ensureLease`; added a regression test for a cached row whose pid has since
been tombstoned.

**Result:** Passed live and in tests. The closed session appeared immediately in
`/api/sessions/resumable` and the iOS Closed search group.

### Attempt 6

**Hypothesis:** Persisting the accepting host on every resume response will make
immediate lifecycle actions routable, including Codex's same-id resume.

**Changes:** `applyResume` / `carryForwardResume` now require the accepting host
id and assign `hostBySession` before publishing the revived session state.

**Result:** Passed live. iOS resumed the closed session and its subsequent End
request reached the correct host without waiting for refresh.

## Automated Verification

- `bun test`: 619 passed, 0 failed (1,210 expectations across 54 files).
- `bunx tsc --noEmit`: passed.
- `ios/LFGCore swift test`: 305 XCTest + 58 Swift Testing tests passed.
- `flowdeck run -S 4E15AD3B-8DA3-4C99-AFD6-3ED0BC6A2DED`: built,
  installed, and launched the source-built app successfully.
- `flowdeck test` could not run because the `LFG` app scheme has no Test action;
  the repository's Swift-package suite was used as the documented fallback.

## Evidence

- `.codex/evidence/codex-ios-live-followups.mov`
- `.codex/evidence/codex-ios-lifecycle-matrix.mov`
- `.codex/evidence/codex-ios-queue-held.png`
- `.codex/evidence/codex-ios-queue-drained.png`
- `.codex/evidence/codex-e2e-session-open.png`
- `.codex/evidence/codex-ios-closed-after-resume.png`
