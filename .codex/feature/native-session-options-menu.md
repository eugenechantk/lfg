# Feature: Native Session Options Menu

## Status: Current — native menu with independent glyph

The action surface remains a native `UIButton` + `UIMenu`. On iOS 26.3 UIKit can hide the toolbar menu-source subtree for up to 1.186 seconds during dismissal, so the visible ellipsis is now an independent, noninteractive `UINavigationBar` sibling while the transparent toolbar button remains the real native-menu source.

Dismissal stability requirements and the failure history are tracked in `.codex/feature/session-more-button-stability.md`.

## User Story

As an LFG iOS user, I want the session toolbar's More button to present Apple's native action menu so it looks and behaves like the rest of iOS, including when the action list is taller than the available screen.

## User Flow

1. Open a session detail view.
2. Tap the ellipsis button in the navigation bar.
3. Scroll the native menu to reach every action.
4. Continue scrolling without the menu jumping to the top while transcript messages stream.
5. Select primary, submenu, debug-copy, and destructive actions normally.

## Success Criteria

- [x] SC1: The ellipsis presents a native Apple `UIMenu`, not a custom popover.
- [x] SC2: A tall action menu scrolls whenever its contents overflow the available height.
- [x] SC3: Transcript updates do not recreate an already-presented menu or reset its scroll position.
- [x] SC4: Existing actions, submenus, disabled states, icons, section grouping, and destructive roles remain available.
- [x] SC5: The More button stays a fixed circular toolbar control when the title is short or long.
- [x] SC6: The More icon uses the dynamic label color, matching the back chevron instead of the blue accent color.
- [x] SC7: Selecting a native-menu action leaves no post-menu frame without a recognizable ellipsis.
- [x] SC8: The closed runtime accessibility tree exposes the enabled `sessionOptionsMenu` Button before and after action dismissal.

## Test Strategy

This regression is owned by UIKit's live menu presentation and cannot be proven by a Swift unit test. Build the app, then exercise the real menu in Simulator. Use a long menu, scroll to its bottom, and keep it open across live transcript updates. Reopen it after state changes to confirm deferred menu generation reflects current actions.

## Tests

### Simulator interaction

- Open the menu in an idle session and scroll from the first to the final action — verifies SC1, SC2, SC4.
- Open the menu in a streaming session, scroll down, wait for transcript deltas, then continue scrolling without a jump — verifies SC2, SC3.
- Open the model/assignment submenu and verify the destructive End Session action — verifies SC4.
- Compare short- and long-title session headers and confirm the More control remains the same width — verifies SC5.
- Compare the More icon with the back chevron in light appearance — verifies SC6.

## Implementation Details

Use a stable `UIButton` with `showsMenuAsPrimaryAction` and a `UIDeferredMenuElement`. SwiftUI may update the representable as messages stream, but it only replaces the coordinator's menu builder; it never reassigns the button's root `UIMenu`. UIKit asks for the latest action tree when the user opens the menu, then owns the presented menu and its native scroll state for that presentation.

Constrain the representable to a 44×44pt toolbar footprint and give its UIKit button required content-hugging priorities. Keep the source button's symbol transparent. Install a label-colored `ellipsis.circle` directly on the live `UINavigationBar` at the same 44×44pt trailing frame, with interaction and accessibility disabled on the glyph itself. The separate proxy advertises `sessionOptionsMenu` and forwards accessibility activation to the native source.

## Residual Risks

The earlier independent menu audit passed SC1–SC4. Disabled styling was not separately exercised because no disabled row existed in the audited running-session state; destructive styling, submenu reachability, sheet handoff, overflow scrolling, and streaming stability were exercised directly.

A follow-up independent visual audit passed SC5–SC6 for both short and long titles and confirmed the menu still opens from the fixed-size control.

Evidence: `.codex/evidence/20260818-174539-ios-visual-audit/evidence.md`

Follow-up evidence: `.codex/evidence/20260818-184314-ios-visual-audit/evidence.md`

Current local native-menu, 60 Hz dismissal, Rename, and accessibility evidence: `.codex/evidence/20260926-095829-native-session-more/evidence.md`

Current independent evidence: `.codex/evidence/20260926-100348-ios-visual-audit/evidence.md`. PASS: native menu/submenus/overflow/destructive role confirmed; first menu-clear frame at PTS 4.900 contains the ellipsis; Rename begins at PTS 5.067; blank post-clear frames: 0 (0.000 seconds); closed AX state exposes the enabled visible 44×44 `sessionOptionsMenu` Button.

## Bugs

- iOS 26.3 hides the native context-menu source subtree during dismissal. Keeping the visible glyph inside the toolbar representable failed independent audits with blank intervals up to approximately 1.186 seconds.
- An app-owned popover removed the blank interval but was rejected because it was not the native Apple menu.
