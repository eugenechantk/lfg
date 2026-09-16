# Bug 014: Transcript bottom does not follow the keyboard composer

## Status: FIXED — verified 2026-09-15

## Description

When the message composer moves upward with the software keyboard, the session transcript stays at its previous full-screen position. Its newest content therefore remains behind the composer instead of sliding up so the transcript's visual bottom sits immediately above the input panel. The same geometry error can hide the bottom half of a newly sent user bubble.

## Steps to Reproduce

1. Open a populated session at the newest transcript edge.
2. Tap the message input.
3. Observe the software keyboard and floating composer slide upward.
4. Observe that the transcript bottom does not follow the composer and its newest content can remain behind the input panel.
5. Enter and send a message while the keyboard remains visible.
6. Observe that the bottom of the outgoing user bubble can be hidden by the input panel.

## Root Cause

The iOS 26 performance change deliberately made the transcript ignore the keyboard safe area so the software-keyboard animation would not repeatedly resize and re-layout the lazy transcript. That isolation was correct for performance, but no replacement viewport adjustment was added for focus: `keyboardOcclusionHeight` was recorded but applied only after Send.

The Send path then centered the outgoing row. Centering can expose a short bubble, but it does not establish the actual invariant and fails for taller rows: the transcript's visual bottom still remains behind the floating composer, so the lower part of a multi-line user bubble can be covered.

## Success Criteria

### 1. Focusing the composer at the newest edge moves the transcript's visual bottom above the raised composer.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `NEW` — `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift` → focused keyboard clearance/follow policy.

**Simulator verification:** Record the populated fixture before tapping `composer.message`, tap it, wait for the keyboard to settle, and confirm the latest assistant row remains completely above the composer.

### 2. Sending with the software keyboard visible keeps the complete outgoing user bubble above the composer, including a multi-line bubble.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `MODIFIED` — `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift` → focused sends follow the newest transcript edge rather than relying on row centering.

**Simulator verification:** With the software keyboard visible, send the fixture message, capture the optimistic and reconciled states, and confirm the entire user bubble remains above the composer.

### 3. Keyboard presentation remains smooth and does not resize the full transcript viewport.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `NEW` — keyboard clearance changes only for a focused composer with positive keyboard occlusion and resets to zero when hidden or unfocused.

**Simulator verification:** Inspect the complete focus recording for continuous transcript motion, intact chrome, and no hang or blank viewport.

## Investigation Log

### Attempt 1

**Hypothesis:** The iOS 26 performance change correctly isolated keyboard safe-area animation from transcript layout, but removed the one explicit viewport adjustment needed to keep the transcript's visual bottom attached to the moving composer.

**Changes:** None yet.

**Result:** Reproduced on iPhone 17 Pro / iOS 26.5. Before focus, the newest assistant row ended around y=689 above the composer. After focus, the composer moved to y=429 while the newest user and assistant rows remained at y=543 and y=591–656 behind it. Recording: `.codex/evidence/20260914-transcript-keyboard-follow/before-fix-focus/`.

### Attempt 2

**Hypothesis:** Animating keyboard-height content clearance and scrolling the existing newest sentinel to its ordinary `.top` anchor will move the transcript bottom with the composer.

**Changes:** Added a tested keyboard transition policy, applied its clearance during the keyboard animation, and followed the newest sentinel for focus and keyboard-visible sends.

**Result:** Failed. The clearance created the required scroll range, but `.top` still means the ordinary visual-bottom resting position in the inverted list. After focus the latest assistant row moved farther down to y=763–828 while the composer began at y=429. The target needs a keyboard/composer-aware anchor, not the ordinary newest anchor position. Recording: `.codex/evidence/20260914-transcript-keyboard-follow/attempt-1-focus/`.

### Attempt 3

**Hypothesis:** The newest sentinel must use a screen-relative anchor derived from the keyboard occlusion and the measured floating composer height. Send-follow must target that same transcript boundary instead of centering one row.

**Changes:** Added one focused-keyboard content clearance, computed an inversion-aware newest anchor from keyboard/composer geometry, and routed focus, optimistic send, and reconciled-send follow through that anchor. The full transcript viewport remains stable behind the keyboard.

**Result:** Focus and wrapped Send passed, but an inverse-transition check found that hiding the software keyboard while an expanded draft retained focus could return to an anchor that left the newest row under the composer.

### Attempt 4

**Hypothesis:** The inverse transition needs the same boundary rule, using the full bottom-chrome height and ordinary transcript gap once the keyboard no longer owns the home-indicator region.

**Changes:** Generalized the newest-boundary anchor for both keyboard-visible and keyboard-hidden geometry, added the inverse-transition unit case, and added a Debug-only wrapped-draft fixture input for deterministic Send verification.

**Result:** Passed. In the settled focus state, the latest assistant row ended at y≈405 and the composer panel began at y≈417. After sending an 84-character, three-line message, the complete user bubble occupied y≈322–387 and the composer still began at y≈417. The independent frame-by-frame audit found no overlap, abrupt corrective jump, hang, or blank viewport. Evidence: `.codex/evidence/20260914-transcript-keyboard-follow/final-focus-v3/` and `.codex/evidence/20260914-transcript-keyboard-follow/final-long-send/`.

## Verification

- Focused `TranscriptWindowTests`: 31/31 passed.
- Full LFGCore suite: 494 XCTest tests plus 144 Swift Testing tests passed with zero failures.
- FlowDeck Debug build for iPhone 17 Pro / iOS 26.5 passed.
- Independent visual audit: PASS for focus and wrapped Send; keyboard remained visible, the transcript boundary cleared the composer, and neither transition showed clipping or discontinuity.
- Independent scroll performance audit: six sustained Simulator swipes kept the viewport populated; its recorder proxy measured zero frame gaps above 50 ms. A device-level hitch trace was unavailable, so main-thread attribution remains formally partial.
- TestFlight version 1.3.0 build 202609150034: `VALID`, current train, and `IN_BETA_TESTING`.
