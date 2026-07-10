# Feature: Live Activity Client

## User Story

The iOS app registers Live Activity tokens with configured lfg hosts and ships a WidgetKit extension that can render server-driven session Live Activities.

## User Flow

On launch, the app consumes ActivityKit push-to-start token updates and per-activity update-token updates. The widget extension renders a session title, state, and elapsed time on the lock screen and Dynamic Island.

## Success Criteria

- `LFGSessionAttributes` is shared by the app and widget targets, with content-state fields `title`, `state`, `sid`, and `since`.
- The widget extension target exists and renders lock-screen and Dynamic Island Live Activity views.
- The app registers push-to-start and per-activity update tokens against the server endpoints.
- Project changes are made through `project.yml` and regenerate cleanly with XcodeGen.
- LFGCore tests cover the new request bodies and pass.

## Test Strategy

Swift package tests verify the request shape for the two LFGClient token registration endpoints using a URLProtocol-backed URLSession.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/LFGClientLiveActivityTests.swift`
  - `testRegisterLiveActivityStartTokenPostsExpectedBody`
  - `testRegisterLiveActivityUpdateTokenPostsExpectedBody`

## Implementation Details

- Added `ios/Shared/LFGSessionAttributes.swift` to both app and widget targets. `ContentState` stays lenient with `state: String` and fields `title`, `state`, `sid`, `since`.
- Added `LFGWidgets` WidgetKit extension with lock-screen and Dynamic Island Live Activity views.
- Added `LiveActivityManager` to consume ActivityKit push-to-start tokens, current activity update tokens, and future activity updates on launch.
- Added `LFGClient` methods for the two Live Activity token endpoints.
- Raised the app and widget deployment targets to iOS 17.2 and enabled Live Activity Info.plist keys through `project.yml`.

## Verification

- `cd ios && xcodegen generate` passed.
- `cd ios/LFGCore && CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_CACHE_PATH="$PWD/.build/swiftpm-cache" swift test --disable-sandbox` passed: 108 tests, 0 failures.
- XcodeBuildMCP simulator build passed for the `LFG` scheme on iPhone 17; the generated scheme includes both `LFG.app` and `LFGWidgets.appex`.

## Residual Risks

Live Activity presentation was compile-validated but not visually exercised with a live server-started ActivityKit activity in Simulator.

## Bugs

None yet.
