# Feature: idle-session-moves-without-source

Diagnosis: `.claude/diagnosis-transfer-off-offline-host-530-20260920.md`. Tier: product.

## User Story

As the phone's user, I want to move an idle session to another host without the
original host having to answer, so that a host that is down (or about to be marked
down) never blocks the move; the original copy is closed whenever that host is
reachable again.

Eugene, 2026-09-20: "The fix should be that the move should be client side instead
if the session is idle anyways. And let the client just switch the host in the
session view. And clean up the original session and close it after the host is back
online."

## User Flow

1. User picks "move to Air" on a session whose host is the Pro.
2. The target pre-flight runs as before (transcript present, cwd present, not stale).
3. **Idle session** (not busy, no pending prompt) or source known down: the client
   resumes on the Air, forced past the Pro's lease, and re-points the session view
   to the Air. No request is sent to the Pro first.
4. The Pro's copy is queued in `DeferredSourceCloses`. If the Pro is live it is
   closed straight after the move; otherwise on the Pro's next recovery.
5. **Busy session or pending prompt on a reachable source:** unchanged — close on
   the source first. If that close is answered by the Cloudflare edge (530/502/52x
   HTML) rather than by lfg, it now counts as "host went away" and the move
   proceeds as in step 3 instead of aborting.

## Success Criteria

- [x] SC1: idle + source not known down → plan skips the source close, forces the
  resume, defers cleanup — **Verify by:** `SessionTransferIdleMoveTests`.
- [x] SC2: busy, or prompt pending, on a reachable source → closes first as before —
  **Verify by:** `SessionTransferIdleMoveTests` + existing
  `testReachableSourceClosesFirstAndDoesNotForce`.
- [x] SC3: an edge 530/502/504 HTML answer on close is "unreachable"; lfg's own JSON
  502, and 404/409/500, are not — **Verify by:** `SessionTransferIdleMoveTests`.
- [x] SC4: LFGCore suite green — **Verify by:** full XCTest bundle run.
- [ ] SC5: the app target builds with the call-site change — **Verify by:**
  `flowdeck build`. BLOCKED on this machine (see Evidence).
- [ ] SC6: live: move an idle session off a Pro that is down but not yet marked
  offline → lands on the Air, no toast; when the Pro returns, its copy is closed —
  **Verify by:** on device with a TestFlight build, plus the Pro's session list.

## Platform & Stack

iOS (Swift 6, LFGCore + app target).

## Implementation

- `ios/LFGCore/Sources/LFGCore/SessionTransferIdleMove.swift` (new):
  `SessionTransfer.movesWithoutSource(sourceKnownDown:busy:promptPending:)` and
  `SessionTransfer.isEdgeOriginDown(status:body:)`.
- `SessionTransfer.closeFailureIsUnreachable`: `.http` → `isEdgeOriginDown`.
- `SessionStore.transfer`: passes `movesWithoutSource(...)` as `sourceKnownDown`.
- Everything else — forced resume, view re-pointing, `DeferredSourceCloses`, replay on
  recovery and right after the move — already existed for the known-down case.

## Decision Log

- **Reused the `.sourceUnreachable` plan rather than adding a third plan.** Idle-move
  and known-down need exactly the same three things (no close first, force, defer).
- **A pending prompt is not idle.** The asking turn exists only on the source's pane;
  moving would drop the question.
- **Body sniffing for the edge, not status alone.** lfg deliberately returns a JSON 502
  for codex resume failures; that must stay a refusal.
- **Narrow scope.** The same misclassification affects sends
  (`SendTerminality`: 530 → "server answered"). Not changed here; noted in the
  diagnosis as a follow-up.
- **Minimal footprint in dirty files.** Another session has uncommitted work in
  `SessionTransfer.swift` and `SessionStore.swift`; this change is one `case` and one
  call-site argument there, with the logic in a new file.

## Verification Evidence

| SC | Command | Observed |
|---|---|---|
| SC1–SC3 | `xctest -XCTest LFGCoreTests.SessionTransferIdleMoveTests,LFGCoreTests.SessionTransferTests` (Air, 2026-09-20) | 25 tests, 0 failures (11 new, 14 existing) |
| SC4 | full `LFGCoreTests.xctest` bundle | 560 tests, 0 failures, 1 skipped |
| SC5 | `flowdeck build` on the Air (2026-09-20 09:50, after Eugene accepted the Xcode licence) | FAILED for an environment reason, not a compile error: "CoreSimulator is out of date … Unable to find a device matching the provided destination specifier". The Air's Xcode never ran first-launch setup (`sudo xcodebuild -runFirstLaunch`). The Pro is still unreachable. App-target compile therefore UNVERIFIED; the change there is one call-site argument using `busy[id]`, `prompts[id]` and a public LFGCore function that did compile. |
| SC6 | not run | needs SC5 + a TestFlight build |

Not committed: both hooks sit inside another session's uncommitted transfer rework
(`SessionTransfer.perform`, the `SessionStore.transfer` call site), so they cannot be
staged without committing that work too, and the new test for the close escalation
would fail on a clean checkout without the hook. Commit together with that rework.

## Bugs

_None yet._
