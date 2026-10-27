# Feature: Full-screen Space control

## User story
Taking control opens the guest desktop across the phone screen. Rotate to landscape, zoom into details, click and drag, right-click with two fingers, and use the native keyboard.

## User flow
Live Space → Take control → wait for agent pause → full-screen desktop. Pinch to zoom, two-finger pan to inspect, one-finger tap or drag sends guest input, two-finger tap right-clicks. Keyboard toggles native input. Fit resets zoom. Done ends control and returns to watching.

## Success criteria
1. Taking control presents full screen after the agent pauses. Done returns to watching and clears queued input.
2. Portrait and both landscape directions work inside control. iPhone returns to portrait afterward.
3. Pinch zoom and two-finger pan work without guest clicks. Fit resets the viewport.
4. Taps and one-finger drags use guest coordinates after zoom and pan. Two-finger tap sends exactly one right-click.
5. Keyboard text, whitespace, Backspace and Enter reach the guest. Native keyboard remains accessible in landscape.
6. Disconnect/background stops sending input. No cursor or keyboard takeover on the Pro.

## Test strategy
Swift Testing covers viewport fit and normalized-point conversion across portrait, landscape and zoom. Existing backend tests cover the guest protocol and idle-agent boundary. Native builds plus an independent recorded simulator audit exercise all UI criteria against a real Linux guest.

## Residual risks
The recorded simulator flow displays the native keyboard in landscape. Physical-phone behavior and complex input methods were not separately tested. Request/response guest input has network latency.

## Verification progress
- All 501 core tests pass, including 3 viewport tests. Backend: 19 tests, 123 assertions. Mac build passes.
- Independent iOS build and full-screen transition pass. Portrait and both landscape directions are captured.
- Recorded native UI tests verified pinch zoom, true two-contact pan and Fit. Guest counters stayed at zero during zoom and pan.
- Zoomed guest drag, text, Backspace and Enter pass. Final snapshots show one right-click, a guest drag after manual pan and zoom, visible landscape keyboard input, and return to portrait after Done.
- UI test target is opt-in. Generic test runs skip the isolated Cua fixture unless explicitly enabled with its host URL.

## Implementation
UIKit owns zoom and touch conversion. One-finger guest input and two-finger viewport input have separate recognizers. Each control session owns a video connection. Closing control clears pending input and reconnects the inline viewer. Orientation permission is limited to the control session.

## Tests
- `ios/LFGCore/Tests/LFGCoreTests/SpaceViewportTests.swift`: aspect fit, normalized coordinates and bounds.
- `ios/LFGUITests/SpaceControlFullScreenUITests.swift`: opt-in recorded native gesture flow against the real guest.
- The two-contact gesture helper lives only in the UI-test target; the app has no private XCTest dependencies.

## Final independent verdict
PASS on the final app binary. The audit proved portrait and both landscape directions, 2x pinch, two-contact local pan with zero guest events, guest drag after manual pan and zoom, Fit, exactly one right-click, visible landscape keyboard with whitespace/Backspace/Enter, and Done from landscape restoring portrait viewing.

Report: `.codex/evidence/20261021-091707-ios-visual-audit/evidence.md`.
Recording: `.codex/evidence/20261021-091707-ios-visual-audit/fullscreen-control-flow-final.mov` (ffprobe-valid, 159.775 seconds).

The test Space is paused. The app remains in the isolated worktree; no production installation, release, commit or push occurred.
