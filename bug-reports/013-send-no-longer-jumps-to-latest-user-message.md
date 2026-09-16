# Bug 013: Sending no longer jumps to the latest user message

## Status: FIXED — verified 2026-09-13

## Description

When the user sends a new message, the session should immediately follow the new outgoing user turn and keep it visible above the composer or software keyboard. It remained at the previous scroll position or left the newest row obscured behind the keyboard.

## Steps to Reproduce

1. Open a populated live session.
2. Scroll away from the latest transcript edge into older history.
3. Enter a new message in the composer and send it.
4. Observe that the transcript does not jump to the latest outgoing user message.

## Root Cause

The iOS 26 performance rewrite intentionally keeps the inverted transcript at a stable, full-screen height while the composer alone follows the keyboard. That removed keyboard-driven lazy-stack layout work, but it also changed the meaning of `isAtBottom`: offset zero could be correct while the newest outgoing row was physically behind the focused composer and keyboard.

The send policy only jumped when `isAtBottom == false`, and its target was the absolute `NEWEST` sentinel. A send at offset zero therefore did nothing, while the sentinel itself could not guarantee that the outgoing row was visible. The correct target is the outgoing user row: first its optimistic pending ID, then the real transcript ID after reconciliation.

## Success Criteria

- Sending while reading history returns to the newest edge and reveals the optimistic user row.
- Sending while the composer is focused follows the optimistic row even when the transcript reports offset zero.
- The real user turn remains followed when it replaces the optimistic row.
- With the software keyboard visible, the outgoing user row has enough scroll clearance to remain above the composer and keyboard.
- An unfocused reader already at the newest edge does not receive a redundant programmatic jump.
- The keyboard-performance design remains intact: keyboard animation does not resize the transcript or rewrite its lazy-stack padding on every animation frame.

## Investigation Log

### Attempt 1

**Hypothesis:** The recent inverted-list/performance rewrite leaves the explicit send-follow intent dependent on stale `isAtBottom` state or a removed scroll anchor.

**Changes:** Added a focused-composer input to the send-follow policy and regression tests for newest, history, and focused-composer cases.

**Result:** Confirmed the policy regression: `isAtBottom == true` suppressed the jump even though the full-height transcript could leave the new row behind the keyboard.

### Attempt 2

**Hypothesis:** Following the actual pending row and then the reconciled real turn will restore the expected behavior without reintroducing the old redundant bottom jump.

**Changes:** Added stable IDs to optimistic bubbles, armed follow state before dispatch, deferred the scroll until SwiftUI inserts the target, and followed the real user turn after reconciliation.

**Result:** Passed. In the network-free Simulator fixture, a send from history logged `jumpToNewest`, then `jumpToSentMessage` for the pending row, followed by `sendLanded.jump` and a second `jumpToSentMessage` for the real turn. The outgoing row was visible immediately above the composer.

### Attempt 3

**Hypothesis:** A row-targeted scroll still needs scrollable clearance equal to the software keyboard because the transcript deliberately ignores the keyboard safe area.

**Changes:** Capture the keyboard's final occlusion from UIKit, snapshot it only when Send is tapped, add that stable value to visual-bottom transcript clearance, and clear it when composer focus leaves. The clearance is not applied during keyboard presentation, preserving the stable transcript viewport.

**Result:** Partial. On iPhone 17 Pro / iOS 26.5, the software keyboard occupied 291 points and moved the composer from y=741 to y=440. Send targeted the pending row immediately and the reconciled row about 700 ms later, but a one-line bubble could still land partly beneath the floating composer because centering the row ignored that overlay.

### Attempt 4

**Hypothesis:** The keyboard clearance provides scroll range, but the send-follow target itself must be placed above center to clear the composer. Because the transcript is inverted, increasing the structural Y anchor moves the visually restored row upward.

**Changes:** Added a 56-point reveal gap to the send-only clearance and offset focused send-follow targets upward by the same screen-relative amount. Unfocused navigation remains centered.

**Result:** Passed. The final FlowDeck recording kept the 291-point software keyboard visible, cleared the draft, and followed both the optimistic and reconciled `Proof` row. The landed text frame was y=359–378 while the composer text field began at y=429, leaving the complete bubble visibly clear of the floating panel. The independent evidence audit returned PASS with no hang, blank viewport, or rendering disruption. Full LFGCore suite: 486 XCTest tests and 144 Swift Testing tests, all passing. FlowDeck app build passed.
