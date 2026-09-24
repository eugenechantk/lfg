# Feature: Session Message Auto-Scroll

## User Story

As an LFG iOS user, I want new messages to follow the transcript only when I am already at its newest edge, so reading older messages is not interrupted.

## User Flow

1. Open a populated session.
2. Either remain at the newest edge or scroll upward into transcript history.
3. Send a message and allow its optimistic and reconciled rows to appear.
4. Observe that the transcript follows the sent message only from the newest edge and otherwise preserves the history position.

## Success Criteria

- [x] SC1: Sending while at the newest edge keeps the outgoing message visible.
- [x] SC2: Sending while positioned above the newest edge does not jump to the outgoing message or newest edge.
- [x] SC3: Optimistic-row insertion and real-row reconciliation preserve the same follow decision made at send time.
- [x] SC4: Incoming transcript mutations preserve a reader's history position while continuing to appear naturally for a reader already at the newest edge.
- [x] SC5: Focusing or dismissing the keyboard while reading history does not change the transcript position before Send.
- [ ] SC6: The complete flow passes independent Simulator verification. The required auditor could not start because its fixed model is unavailable on this account.

## Test Strategy

- Unit-test the send-follow policy at both newest-edge and history positions, including focused-composer behavior.
- Unit-test keyboard-margin transitions so geometry changes are frozen while reading history and synchronized upon returning to newest.
- Retain the existing transcript-window reconciliation tests that protect the oldest rendered row while live messages arrive during history reading.
- Exercise the shipping session view in Simulator: send once from the newest edge and once after scrolling into history, recording both outcomes.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift`
  - sending at newest without keyboard uses the natural newest offset (SC1)
  - sending at newest with a focused composer explicitly follows above keyboard (SC1, SC3)
  - sending from history never follows, including with a focused composer (SC2, SC3)
  - existing reconciled-window coverage protects live arrival while reading history (SC4)
  - keyboard focus/dismissal preserves the existing margin while reading history (SC5)
- Independent Simulator recording of newest-edge and history-position sends (SC1-SC6).

## Implementation Details

- Send captures the existing newest-edge state before dispatch. A send from history no longer sets `isAtBottom`, schedules a newest-edge jump, or arms optimistic/reconciled-row following.
- A focused send follows explicitly only when the reader was already at newest; an unfocused newest-edge send continues to use the inverted list's natural offset.
- Keyboard clearance and the effective bottom content margin freeze while reading history so focus, reconciliation, and multiline-composer shrink do not rewrite the reader's scroll coordinate space.
- The iOS 26 inverted transcript applies a history-only home-indicator counter-offset while the software keyboard owns that safe-area region. This preserves the same visible row coordinates without changing the underlying scroll offset.
- Returning deliberately to newest clears the frozen margin, synchronizes keyboard clearance, and restores ordinary newest-edge following.

## Verification

- Focused `TranscriptWindowTests`: 39 tests passed with zero failures.
- Full LFGCore suite: 593 XCTest tests passed (1 skipped) plus 179 Swift Testing tests passed.
- FlowDeck Debug build and launch passed on the isolated iPhone 17 Pro / iOS 26.3 Simulator.
- Runtime fixture, newest edge: focused wrapped send stayed visible above the keyboard through reconciliation.
- Runtime fixture, history: messages 25 and 26 retained the same screen coordinates through keyboard focus, optimistic send, composer shrink, and real-row reconciliation; the view did not jump to the outgoing message.

## Residual Risks

- Independent Simulator evidence review could not run because the required auditor's fixed model is unavailable on this account. Manual FlowDeck verification covered both paths, including optimistic insertion and delayed reconciliation.

## Bugs

- Existing send behavior overwrites reader intent by setting `isAtBottom = true` and scheduling a newest-edge jump after a send from history.
