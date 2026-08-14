# Bug 001: More options menu resets while scrolling

## Status: FIXED — verified 2026-08-14

## Description

The session detail screen's More Options menu flashes and jumps back to its first item when the user tries to scroll. It should remain stable and preserve the user's scroll position for the lifetime of the presentation.

## Steps to Reproduce

1. Launch LFG and open a session detail screen.
2. Tap the ellipsis button in the navigation bar to open More Options.
3. Swipe upward inside the menu to reveal lower actions.
4. **Observed:** the menu flashes and returns to the top instead of remaining at the scrolled position.

## Root Cause

`SessionDetailView` observes the live transcript. While a session is running, transcript deltas invalidate the view several times per turn. The ellipsis actions were implemented as a native SwiftUI `Menu` inside that same toolbar, and each invalidation rebuilt the presented `UIMenu`. UIKit recreated the menu at offset zero, producing the flash and jump to the first row.

Extracting an equatable child was insufficient because SwiftUI reconstructs toolbar menu presentations above the child view boundary. The fix replaces only the root `Menu` with a toolbar-anchored popover containing a plain `ScrollView`. The scroll view owns persistent scroll state and updates its rows in place; the short model, owner, and host choices remain native submenus.

## Success Criteria

### 1. A tall More Options surface preserves its scroll position across live transcript updates
- [x] Verified in simulator

**Unit test:** `N/A` — the regression is the runtime interaction between SwiftUI toolbar invalidation and UIKit's presented menu scroll state; the project has no UI-test target that can own this system presentation. Compilation is covered by the app build, and the behavior is exercised end-to-end in Simulator.

**Simulator verification:**
1. Launch the app with a live session and two configured hosts so "Move to host" makes the options surface overflow.
2. Open More Options and swipe upward until the debug IDs and "End session" are visible.
3. Deliver a new assistant transcript message while the options surface remains open.
4. **Expected:** the same bottom rows remain visible, with no flash or jump to "Stop".

### 2. Existing primary and nested actions remain reachable
- [x] Verified in simulator

**Unit test:** `N/A` — presentation routing is exercised through the real SwiftUI/UIKit hierarchy in Simulator.

**Simulator verification:**
1. Open More Options.
2. Tap "Switch model" and confirm its model submenu appears.
3. Reopen More Options and tap "Files & Links".
4. **Expected:** the native model submenu appears, and Files & Links dismisses the popover before presenting its sheet.

## Investigation Log

### Attempt 1

**Hypothesis:** Live session updates are invalidating and rebuilding a native SwiftUI `Menu` while it is presented, causing UIKit to recreate the menu and reset its scroll position.

**Changes:** Extracted the native menu into an equatable child so transcript-only changes would not alter its inputs.

**Result:** Failed. The menu scrolled to "End session," but the next live transcript update still rebuilt the toolbar presentation and reset it to "Stop."

### Attempt 2

**Hypothesis:** A toolbar-anchored popover with a native `List` can retain its own scroll state while SwiftUI updates live option rows in place.

**Changes:** Replaced the root native `Menu` with a popover-backed list. Kept bounded model, owner, and transfer choices as native submenus. Added deferred handoff for actions that present another sheet or dialog.

**Result:** Passed. After scrolling to "End session," a new live transcript message arrived and the bottom offset remained unchanged. The model submenu and Files & Links sheet also presented successfully.

### Follow-up: plain popover chrome

Removed the navigation title and "Done" button after review. More Options now reads as a plain anchored popover and dismisses by tapping outside. Simulator verification confirmed the popover still scrolls to "End session" and dismisses through the outside region.

### Follow-up: flat button styling

Replaced the grouped `List` presentation with a plain `ScrollView` and flat button rows separated by hairlines. This restores the previous menu-style visual language without giving up stable scrolling. Simulator verification confirmed that the flat surface remained scrolled to "End session" after a live transcript update.

## Final Summary

The native root `Menu` was recreated on every transcript-driven toolbar invalidation, discarding its scroll offset. More Options now uses a plain toolbar-anchored popover backed by a flat `ScrollView` of buttons and separators, while bounded choices remain submenus. The scroll view stayed at the bottom across a live transcript update, the nested model menu and Files & Links handoff passed, the app built successfully, and all 360 LFGCore tests passed.
