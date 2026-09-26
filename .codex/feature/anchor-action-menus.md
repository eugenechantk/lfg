# Feature: Anchor Action Menus

## User Story

As an LFG user, I want transient action menus to open beside the control or row I invoked so the actions remain visually tied to their context.

## User Flow

1. Open a session with a queued message.
2. Tap the queued message row's More affordance.
3. See the queued-message actions adjacent to that row.
4. Dismiss or choose an action without changing existing queue behavior.

## Success Criteria

- SC1: The queued-message action menu is presented from the tapped queued-message row, not from the session root or top of the screen.
- SC2: Each queued row owns its own presentation anchor, including when multiple queued rows are visible.
- SC3: Send now, edit, remove, cancel, and the reduced resume-only action set retain their current behavior.
- SC4: Existing toolbar, composer, and other native `Menu` controls keep their native trigger-relative positioning.
- SC5: The queued-message trigger remains accessible and automation-addressable.

## Test Strategy

- Characterize presentation ownership with a focused source contract test: the queued action dialog must be attached inside the queued row, and the session root must not own it.
- Run the relevant iOS test target and build through FlowDeck.
- Validate the interaction in Simulator and capture independent visual evidence showing the trigger and opened menu in the same frame.

## Tests

- `src/ios-queued-message-menu-anchor.test.ts`
  - verifies SC1 and SC2 by enforcing row-local presentation ownership.
  - verifies SC5 by retaining the queued-row accessibility contract.
- Existing LFGCore queued-message tests cover the action-state semantics behind SC3.

## Implementation Details

- Replaced the screen-level queued-message `confirmationDialog` with a native `Menu` inside each pending row.
- Kept queue operations in `PendingStripView`; edit returns the recovered draft to `SessionDetailView`.
- Added the DEBUG-only `LFG_SEND_FOLLOW_FIXTURE_HOLD_QUEUED=1` flag to keep the queued state stable during visual evidence capture.

## Residual Risks

- The focused visual path is iPhone portrait. Native `Menu` placement adapts on iPad and landscape, but those size classes are not separately captured in this change.

## Verification Results

- `bun test src/ios-queued-message-menu-anchor.test.ts src/ios-session-menu-threading.test.ts` — 4 passed.
- `flowdeck test -s LFGCoreTests -S C77504FA-02C1-4C28-B9FE-6BE16982F4A8 --only LFGCoreTests/QueueAckResolutionTests --progress` — 9 passed.
- `flowdeck build -S C77504FA-02C1-4C28-B9FE-6BE16982F4A8` — passed.
- Manual Simulator validation — queued action menu rendered directly above the queued row; Edit dismissed it and restored the message to the composer.
- Independent visual evidence audit — PASS; report and recording in `.codex/evidence/20260926-154956-ios-visual-audit/`.

## Bugs

- Current queued-message actions are attached to `SessionDetailView`, so SwiftUI resolves the presentation source from the screen-level view instead of the tapped row.
