# More Actions opens on the first tap

Product tier. iPhone session toolbar.

## User story and flow

Open a session, tap More Actions once, and see its sheet. Close it and repeat. The same behavior should hold after opening another session or focusing the composer.

## Success criteria

- [x] SC1: The first tap opens More Actions after a fresh session navigation. Verify with a simulator recording and repeated independent cold opens.
- [x] SC2: Closing and reopening the sheet takes one tap, including after keyboard focus and transcript updates. Verify with recorded simulator interactions.
- [x] SC3: Sheet dismissal and subsequent actions still work. Verify close, title edit, and a secondary sheet in the simulator.
- [x] SC4: The toolbar keeps its existing icon, native appearance, and usable hit area. Verify screenshots and interaction checks.

## Test strategy

Reproduce the real toolbar interaction before editing. This is a UIKit/SwiftUI presentation and hit-testing bug; simulator evidence is the primary regression proof. Add a deterministic test only if the fix introduces independently meaningful state logic. Build with FlowDeck and run the relevant existing tests. An independent visual auditor will exercise the final app.

## Decision log

Committed the three completed features separately before this fix:

- `7b98abc` — Keep desktop session status synchronized.
- `8c17beb` — Match session fades to the lists.
- `83d2e02` — Render file handoffs only as cards.

The new toolbar fix is included in this commit. Preserve concurrent work from other sessions. No push or TestFlight release was requested.

Replace the wrapped UIButton and its weak coordinator/asynchronous action forwarding with a native SwiftUI Button. Keep the custom icon and set a 44-point label with an explicit rectangular content shape. The native control owns both hit testing and the direct sheet-state mutation. Do not add retries or presentation delays.

## Verification evidence

Baseline: the original toolbar opens on a center tap, but a tap 16 points left of the center, visibly inside its glass circle, does not open the sheet. The same miss occurs after opening and closing once. The capture uses the real RootView session-list navigation and a disposable two-session host fixture. Results: `.codex/evidence/session-more-first-tap/baseline-hit-area.json`; recording: `baseline-hit-area.mov` in the same folder. This reproduces a touch-area defect; the reported intermittent center-tap timing failure has not been independently reproduced.

Six existing SessionSheet model tests passed before and after the fix (`sheet-tests.log`, `sheet-tests-final.log`).

The final FlowDeck build passed. Parent regression passed 10 single-tap sheet openings across five fresh navigations, covering leading, trailing, upper, lower, and center points, both before and after sheet dismissal. No retry taps. Results: `final-hit-area.json` and `final-hit-area.log`; recording: `final-hit-area.mov` (106 seconds; all 60 actions/assertions completed in 73 seconds). The previously failing leading-edge tap now opens on the first tap.

## Residual risks

Physical-device behavior remains unverified. Baseline center taps succeeded; the reproduced defect was the visible glass button having a smaller interactive area. The final simulator audit passed cold launch, fresh session navigation, all five tap points, repeated opens, keyboard focus, and secondary-sheet actions. A real transcript reload was exercised; a simultaneous incoming-message animation was not tested.

Parent keyboard/action checks: an edge tap opened More Actions with the keyboard visible. Tapping the title dismissed the sheet and opened Rename; Cancel returned safely. A further single edge tap opened More Actions and Files & links opened its secondary sheet. Recording: `keyboard-actions.mov`. The rename alert uses native field accessibility that does not expose the assigned SwiftUI identifier; the alert title and Cancel were observed directly. No rename, host switch, or production write occurred.

## Final independent audit and cleanup

PASS: `.codex/evidence/20261017-002800-ios-visual-audit/evidence.md`. The frozen bundle manifest matches. All five button points opened with one tap; cold launch, fresh navigation/transcript reload, keyboard focus, Rename/Cancel, and Files & links passed. A transient stale screen read briefly suggested a failed lower-edge tap, but the saved screenshot/tree showed the original tap had opened the sheet; no second tap occurred. A fresh capture confirmed the same lower-edge tap opened successfully.

The independent capture stopped and appearance returned to light. The root simulator returned to its original shutdown state. The disposable 19041/19042 fixture stopped. Production hosts and other sessions were untouched. The three earlier features are committed; the new toolbar fix is included in this commit.
