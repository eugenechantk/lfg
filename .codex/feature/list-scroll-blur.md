# Restore translucent list bars

This is product work for the iPhone and iPad Sessions and Tasks lists. Their content should scroll beneath the top controls and bottom dock with a smooth blur transition, like the session view.

## Success criteria

- [x] Both lists show soft blur at the top and bottom while scrolling.
- [x] The dock keeps Sessions and Tasks on the left and Create on the right, near the home indicator.
- [x] On iPad, the dock stays inside the sidebar.
- [x] Search, tab switching, and task navigation still work. The dock stays out of phone detail views.
- [x] No hard opaque strip or abrupt clipping separates the list from its controls.

## Approach

Use native soft scroll edges and attach the dock to each scroll surface with `safeAreaBar` on iOS 26. Remove outer layout padding that prevents rows from reaching the controls. Keep the earlier-OS inset fallback. Keep task guidance in the scrolling content so it does not block the bottom edge.

## Verification

This change has no new business logic. Verify it through a simulator build, scrolling recordings, screenshots, and an independent visual audit. Use a read-only local fixture with enough rows to reach both edges. Cover phone and tablet, light and dark appearance, and navigation/search regressions.

## Status

Implementation complete. The iOS simulator and standalone desktop builds passed. All 181 desktop checks passed after the shared task-view change. Before/after screenshots show rows reaching behind the dock, with soft transitions on both lists. The dock keeps its original phone position. The task host requirement now scrolls with task rows instead of creating a fixed strip above the dock.

The independent review passed on iPhone 17 Pro and iPad Pro 11-inch running iOS 26.3. Five recordings cover scrolling, including light and dark phone appearances. Seventeen screenshots cover bar transitions, final-row clearance, sidebar placement, short search results, and detail navigation. No opaque strip, abrupt clipping, or dock spill appeared.

Independent report: `.codex/evidence/20261010-214556-ios-visual-audit/evidence.md`. Build evidence and the scoped source diff are under `.codex/evidence/list-scroll-blur/`. No release, device installation, commit, or push was performed.

## Residual scope

The result is verified in simulators. It is not yet in a TestFlight build or installed on a physical phone. Earlier iOS versions retain the existing safe-area inset fallback; the new soft-edge effect requires iOS 26.

## API references

- [Apple: safeAreaBar](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) extends the affected scroll views' edge effects.
- [Apple: soft scroll edges](https://developer.apple.com/documentation/swiftui/scrolledgeeffectstyle/soft) provides a soft transition between scrolling content and controls.
