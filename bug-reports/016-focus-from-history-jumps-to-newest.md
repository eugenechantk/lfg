# Bug 016: Focusing the composer jumps a history reader to newest

## Status: IN PROGRESS

## Description

When a reader is in the middle of a session transcript, tapping the message input jumps the transcript to its newest edge as the software keyboard appears. Focusing or dismissing the composer must preserve a reader's history position. Keyboard transitions should follow the newest edge only when the reader was already there; sending remains an explicit request to return to newest.

## Steps to Reproduce

1. Open a populated session.
2. Scroll away from the newest edge into the middle of the transcript.
3. Tap the message input.
4. Observe that the transcript jumps to the newest messages while the keyboard appears.

## Root Cause

`applyKeyboardTransition` derives `shouldFollowNewest` only from keyboard clearance, so every focused keyboard presentation sets `isAtBottom = true` and scrolls to the newest sentinel. The bottom-chrome measurement path also treats any nonzero keyboard clearance as permission to schedule the same jump. Neither path preserves the reader's pre-transition position intent.

## Success Criteria

### 1. Focusing or dismissing the composer while reading history preserves the transcript position.
- [ ] Verified in unit test
- [ ] Verified in Simulator

### 2. Focusing at the newest edge still keeps the complete newest row above the raised composer.
- [ ] Verified in unit test
- [ ] Verified in Simulator

### 3. Sending from history still jumps to the sent message at the newest edge.
- [ ] Verified in unit test
- [ ] Verified in Simulator

## Investigation Log

### Attempt 1

**Hypothesis:** Keyboard layout changes are correct, but keyboard visibility is incorrectly being used as a proxy for reader intent.

**Changes:** None.

**Result:** Confirmed in code. `keyboardTransition` follows whenever clearance appears or disappears, regardless of `isAtBottom`, and the bottom-chrome observer separately follows whenever keyboard clearance is nonzero.
