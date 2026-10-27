# Feature: Direct Space input

## User story and flow
Watch Live Space, take control after the agent pauses, then use the guest pointer and keyboard inside LFG. Done or disconnect ends input.

## Success criteria
- macOS captures pointer movement, click, right click, drag, wheel, text and keyboard shortcuts on the video surface.
- iOS supports tap, drag, external keyboard, and a Keyboard button for the software keyboard.
- Input preserves whitespace and order. Pending pointer moves coalesce. Disconnect cancels queued input.
- The host checks agent idle state before every mutation. Streaming remains view only.

## Tests
Backend route tests cover normalized pointer coordinates, drag, key validation, whitespace and running-agent refusal. Native builds and independent simulator recording prove focus and keyboard delivery.

## Residual risks
Input uses guarded request/response driver calls. Latency depends on driver round trips; this is not a gaming remote desktop.

## Verification so far
- Backend: 19 tests pass with 123 assertions. Covers coordinate boundaries, desktop move scope, drag mapping, right button, shortcut allowlist, whitespace and busy-agent rejection.
- Real Cua container: move, drag, right-click and Escape each confirmed by driver through HTTP. Text and Ctrl+A also succeeded.
- Native macOS capture probe: plain key events route to text; Command maps to Ctrl; Shift+Tab, Enter and Backspace route as keys. Unicode and whitespace survive. Inactive input emits no events.
- Final iOS build passed at 17:11:05 UTC. Mac desktop build passed.
- Independent recorded simulator audit pending.

## Audit iteration 1
The simulator audit found that the custom UIKeyInput surface did not show the keyboard or deliver typed text. Replaced it with a real UIKit UITextView responder. Its delegate forwards text, Enter and Backspace without storing guest text. Focus runs after attachment to the window. Hardware shortcuts remain intercepted. Awaiting repeat audit.

## Audit iteration 2
The UIKit text editor delivers exact `A  B` to the real guest. Slider drag moves the thumb from its midpoint to about 90 percent. The simulator does not display the software keyboard for either the Space responder or a standard SwiftUI URL field. This is an environment-wide presentation limitation; a physical iPhone keyboard appearance has not been recorded. Native typing delivery is verified.

## Remaining verification limits
The Mac event capture probe runs without physical cursor takeover. A complete physical Mac hover/drag flow was not recorded. Linux driver movement and drag succeeded live. Complex input methods and physical external keyboards were not tested.

## Final independent verdict
PASS. See `.codex/evidence/20261021-010825-ios-visual-audit/evidence.md` and `direct-space-input-final.mov`. Tap, exact whitespace, Backspace, Enter/newline and slider drag reached the real guest. Done returned to view only. A post-Done tap, Z and Enter left the screenshot byte-identical. Software keyboard presentation remains an explicit simulator-wide visual limitation. The test Space was paused after verification.

## Follow-up: full-screen control
The later full-screen audit displays the native keyboard in landscape and verifies text delivery. The prior simulator-wide visual keyboard limitation no longer applies to the new full-screen flow. See `cua-space-fullscreen.md` and `.codex/evidence/20261021-091707-ios-visual-audit/evidence.md`.
