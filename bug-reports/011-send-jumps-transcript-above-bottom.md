# Bug 011: Sending a message lifts the transcript above its resting bottom position

## Status: FIXED

## Description

Sending from the session composer causes the transcript to jump slightly higher than its normal newest-message resting position. The send should reveal the optimistic message while preserving the same measured bottom-stack clearance and without adding a second animated offset.

## Steps to Reproduce

1. Open a session at the newest transcript position.
2. Focus the composer and enter a message.
3. Tap Send.
4. Observe the final transcript content move higher than its pre-send resting baseline instead of remaining aligned to the same bottom-stack clearance.

## Root Cause

Two send-time transitions combined to move the transcript unnecessarily:

1. `dispatchSend` optimistically set `busy[id] = true` before the asynchronous send classified its presentation. An idle live send therefore observed the store's own optimistic flag as pre-existing agent work, rendered a false queued row in `PendingStripView`, and increased the measured bottom-chrome height.
2. The composer unconditionally scheduled an animated scroll-to-newest even when the inverted transcript was already resting at offset zero, where a newly inserted optimistic row follows naturally.

## Success Criteria

- SC1: An idle live send is classified from the state at the tap and appears as an optimistic transcript bubble, without a false pending-strip row.
- SC2: Sending at the newest position does not schedule a programmatic scroll and preserves the same bottom clearance as the transcript updates.
- SC3: Sending while reading history still jumps to newest and follows the eventual real user turn.
- SC4: Busy, prompting, closed, and offline sessions retain their existing pending-strip presentations.

## Investigation Log

### Attempt 1

**Hypothesis:** The send handler inserts an optimistic row and also schedules an animated `scrollTo` using an anchor whose geometry includes the newly added bottom-stack padding, so the inverted list applies a redundant movement beyond its natural offset-zero resting position.

**Changes:** None yet.

**Result:** Confirmed as one half of the defect. The unconditional jump is redundant at the inverted list's natural offset-zero resting position.

### Attempt 2

**Hypothesis:** The send classification reads the optimistic busy state written synchronously by `dispatchSend`, so the measured bottom stack grows even for an idle send.

**Changes:** Snapshot `OutgoingSendPresentation` before the optimistic busy write and pass it into the retained send task. Gate the explicit scroll-to-newest behind a tested `shouldJumpAfterSend` policy.

**Result:** Fixed. The focused 29-test policy suite and full 144-test LFGCore suite pass. The app builds and launches on iPhone 17 Pro / iOS 26.3. Independent runtime evidence recorded an identical newest-message baseline before and after send (`y=670.6667`), an unchanged composer field at `y=730`, no pending-strip element, and a usable composer after send. Evidence: `.codex/evidence/20260912-191540-send-bottom-stability-audit/`.

## Deployment

TestFlight `1.3.0 (202609121919)` contains the fix. App Store Connect verification passed: the IPA carries the intended version/build, processing state is `VALID`, train `1.3.0` is the highest existing train, and internal state is `IN_BETA_TESTING`.
