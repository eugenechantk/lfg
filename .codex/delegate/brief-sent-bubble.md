# Delegation Brief: sent message bubble vanishes in live view until reopen

**Goal:** After sending a message in the iOS session detail view, the user's own
bubble must stay visible continuously — optimistic placeholder until the real
transcript turn is locally present, then the real bubble, never a gap.

**Working directory:** `/Users/eugenechan/dev/personal/lfg/.worktrees/sent-bubble`
(git worktree, branch `sent-bubble-fix`). Work ONLY here.

## Diagnosed root cause (verified by supervisor — trust this, but re-read the code)

The optimistic bubble (`OptimisticUserBubble`, driven by `pendingSends`) is dropped
by `correlatePending` (`ios/LFG/SessionStore.swift` ~line 1261) as soon as the
server outbound queue marks the item `delivered` — or when a previously-linked
queue item vanishes. "Delivered" means the turn surfaced in the *server-side*
transcript, NOT that the client has fetched it. Two call paths:

- Live path: `.queue` SSE event (~line 1104) → `correlatePending` → bubble dropped,
  **no history reload**. If the real user turn is behind the live stream's attach
  offset (e.g. right after a fork's `reset` re-attach, or any stream reconnect that
  seeds offsets at end-of-file), the turn never arrives as a stream delta → the
  message is invisible until the next full history load (view reopen).
- Poll path: `reconcilePendingViaQueue` (~line 1288) DOES call `loadHistory` when a
  pending clears — but drops the bubble first, so there is still a visible gap
  until the fetch lands.

Reproduced twice on the simulator in the fork flow (bubble absent after send, reply
visible, reopen shows everything); the transcript on the server was correct the
whole time — this is purely client rendering state.

## Fix (behavioral spec)

Change the drop condition: a pending bubble may only be REMOVED when its matching
real user turn is present in the client's local transcript (`transcripts[sid]`,
same matching as `reconcilePending` / the view's `unmatchedSentBubbles`). Queue
status `delivered` (or a linked item vanishing) becomes a *trigger to fetch*, not a
license to drop:

- In `correlatePending`, on `delivered`/vanished: if the local transcript already
  contains the matching user turn → drop (unchanged). If not → KEEP the bubble
  (mark it delivered-but-unfetched if useful) and trigger `loadHistory(sid)`.
- The existing transcript-based reconciles (`reconcilePending` on incoming user
  `msg` events, and after `ensureHistory` merges) then remove the placeholder in
  the same render pass the real bubble appears — the view's documented intent.
- The 3 s poll safety net already re-runs while any pending remains, so a
  `loadHistory` that raced (e.g. fetched before the turn was flushed server-side)
  self-heals on the next tick. Verify this convergence holds; don't add a new
  timer.
- Watch `loadHistory`'s single-flight guard (`historyTasks[id]`): a reload
  requested while an older fetch is in flight must not be silently lost — the
  poll net may cover this; prove it or queue a follow-up reload.

Failed sends must behave exactly as today (Retry bar untouched).

## Constraints

- Swift/iOS only; expected surface is `ios/LFG/SessionStore.swift` (small,
  targeted edits). No new dependencies, no new timers, match existing style.
- If (and only if) it is a clean lift, the "may I drop this bubble?" decision can
  be extracted as a pure testable helper into LFGCore with a unit test; do not
  restructure the store for testability beyond that.

## Verification (run yourself)

- `cd ios/LFGCore && swift test` — green (plus your new test if you extracted the
  helper).
- iOS app compiles: XcodeBuildMCP `build_sim` (or equivalent compile-only build)
  for scheme LFG — SUCCEEDED. Do not run simulators/UI; the supervisor does live
  verification afterward.
- `bun test` at repo root still green (should be untouched).

## Definition of done

- [ ] Bubble is never dropped while its user turn is absent from the local transcript
- [ ] `delivered`/vanished queue status triggers a history fetch instead of a drop
- [ ] Failed-send Retry path unchanged
- [ ] Builds + tests green; committed on `sent-bubble-fix` with a clear message

## Report back

Files changed, the exact drop-condition logic you ended with, test output, any
deviation from this spec and why.
