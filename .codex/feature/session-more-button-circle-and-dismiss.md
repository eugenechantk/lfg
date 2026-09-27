# Feature: Session More Button Circle and Dismissal Stability

## User Story

As a user in a session, I can recognize the More control as a circular three-dot button, and opening then dismissing its native menu never blanks the icon.

## User Flow

1. Open a session.
2. Observe the More control in the navigation bar.
3. Tap More to open the native menu.
4. Dismiss the menu without selecting an action.
5. The circular button and three-dot icon remain visible and tappable.

## Success Criteria

- [x] The resting More control has a circular visible shape, not a capsule or unbounded glyph.
- [x] The three-dot icon is optically centered within the circle.
- [x] The native menu opens from the More control.
- [x] Dismissing the menu without choosing an action leaves the circle and three-dot icon visible.
- [x] The control can immediately open the menu again after dismissal.
- [x] Existing menu actions and confirmation flows remain unchanged.

## Test Strategy

- Preserve existing pure menu-action coverage; this bug is UIKit/SwiftUI navigation-bar presentation behavior and cannot be proven by a package unit test.
- Use a deterministic session fixture and FlowDeck recording to prove the resting shape, open/dismiss transition, retained icon, and immediate second open.
- Run the complete LFGCore suite to guard unrelated session behavior.

## Tests

### Runtime

- Launch a deterministic session fixture.
- Record the More button before interaction.
- Open and dismiss the native menu without selecting an action.
- Verify the circle and ellipsis remain visible.
- Open the menu a second time.

## Implementation Details

- The native `UIButton` remains the stable `UIMenu` source, so UIKit still owns menu anchoring, scrolling, submenus, and actions.
- iOS 26's toolbar-generated shared background is hidden for this one item because it adds horizontal chrome and turns the intended circle into a 52×44 capsule.
- A strongly owned 44×44 navigation-bar proxy renders the visible ellipsis inside `UIGlassEffect` with a 22-point continuous corner radius.
- `StableSessionOptionsButton` reports the native menu animator's completion. The proxy then reattaches itself, restores visibility and alpha, and returns to the front of the navigation bar after cancellation or action selection.
- The accessibility element remains a 44×44 button labelled “More” with identifier `sessionOptionsMenu`.

## Verification

- `bun test`: 1,028 passed, 0 failed.
- `swift test` in `ios/LFGCore`: 205 passed, 0 failed.
- FlowDeck build and launch: passed on isolated iPhone 17 Pro simulator `83C762D7-E34F-407E-AA5C-C6113228399C` (iOS 26.3).
- Runtime fixture: opened and dismissed the menu twice, then selected the debug copy action; the circular control and ellipsis remained visible and tappable after every transition.
- Evidence: `.codex/evidence/session-more-button/verified-open-dismiss-reopen.mov`, `verified-after-first-dismiss.png`, `verified-after-second-dismiss.png`, and `verified-after-action.png`.
- Independent iOS visual audit: **PASS**. Report and additional transition evidence: `.codex/evidence/20260927-170720-ios-visual-audit/evidence.md`.

## Residual Risks

- The iOS 18–25 blur fallback is compile-covered but was not visually exercised; the reported regression and requested circular Liquid Glass treatment were verified on iOS 26.3.

## Bugs

_None yet._
