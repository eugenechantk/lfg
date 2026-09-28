# Feature: Media Viewer Toolbar Separation

## User Story

As a user viewing media, I see Share and Done as two independent native toolbar controls instead of one combined control wrapper.

## User Flow

1. Open an image, video, or file in the media viewer.
2. See Share and Done as separate trailing toolbar controls.
3. Tap Share to open the existing native activity sheet, or tap Done to close the viewer.

## Success Criteria

- SC1: Share and Done render in separate native toolbar materials on iOS 26, with visible space between their control boundaries.
- SC2: Share keeps its existing loading state, accessibility label, identifier, and activity-sheet behavior.
- SC3: Done remains independently tappable and dismisses the media viewer.
- SC4: Supported pre-iOS-26 systems keep two distinct toolbar items without requiring unavailable APIs.

## Test Strategy

- A focused source regression test requires separate `ToolbarItem` declarations, forbids a shared trailing `ToolbarItemGroup`, and requires an iOS 26 fixed `ToolbarSpacer` between the controls.
- A Release simulator recording opens the viewer, visually proves the separated controls, opens Share, dismisses it, and closes the viewer with Done.

## Tests

- `src/ios-file-preview-toolbar.test.ts`
  - verifies SC1 and SC4 structurally.
- Release simulator visual evidence
  - verifies SC1-SC3 at runtime.

## Implementation Details

- Keep the system `.toolbar` surface and native button styles.
- On iOS 26, use `ToolbarSpacer(.fixed, placement: .topBarTrailing)` between Share and Done so Liquid Glass treats them as separate control groups.
- On earlier systems, emit two independent trailing `ToolbarItem` values without `ToolbarSpacer`.
- Implemented Share and Done as separate `ToolbarItem` values while retaining the existing share preparation and dismissal actions unchanged.

## Residual Risks

- Local and independent Release verification pass on iPhone 17 Pro, iOS 26.3.
- This is visual toolbar composition, so the runtime screenshot and recording are the primary proof; the source regression test protects the required toolbar structure.
- The independent audit measured a 20-point gap between the separate Share and Done accessibility frames and verified both controls remain enabled after activity-sheet dismissal. Evidence: `.codex/evidence/20260928-000850-ios-visual-audit/evidence.md`.

## Bugs

- Reported: Share and Done currently appear inside one shared wrapper in the media viewer.
- Fixed locally by replacing the trailing `ToolbarItemGroup` with two native toolbar items separated by an iOS 26 fixed toolbar spacer.
- Independent Release audit passed all five criteria with no visual or interaction deltas.
