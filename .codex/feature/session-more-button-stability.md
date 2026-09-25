# Feature: Session More Button Stability

## User Story

As a user viewing a session, I can choose an action from the More menu without the More button temporarily disappearing after the menu closes.

## User Flow

1. Open a session.
2. Tap the More button in the navigation bar.
3. Choose any available action.
4. The menu closes, the action proceeds, and the More button remains continuously visible.

## Success Criteria

- SC1: Choosing a More-menu action does not remove or hide the More button during menu dismissal.
- SC2: The selected action still executes and presents its expected destination or confirmation UI.
- SC3: The More button remains accessible by the existing stable `sessionOptionsMenu` identifier.

## Test Strategy

- Treat this as a SwiftUI/UIKit lifecycle regression: source-level tests can cover any extracted presentation state, but only a Simulator recording can prove the disappearance no longer occurs.
- Build the app with FlowDeck, then record the complete tap-menu-select-dismiss/present flow in Simulator.

## Tests

- Focused existing app tests covering session-detail behavior, if discoverable.
- Simulator interaction recording: open More, select an action, and observe the button through dismissal and resulting presentation (SC1-SC3).

## Implementation Details

- Reproduced on iOS 26.3: UIKit temporarily removes the `UIButton` image while dismissing its primary-action `UIMenu`.
- Attempt 1 rendered the ellipsis as a SwiftUI overlay, but the independent 60-fps audit showed that the toolbar hides the entire representable subtree for 70–100 ms.
- Attempt 2 returned a stable UIKit host view containing sibling glyph and menu-interaction views. Independent audits still found blank intervals of roughly 0.44 seconds and 1.186 seconds because the toolbar participates in UIKit's context-menu source-preview lifecycle as a unit.
- Attempt 3 removes the `UIContextMenuInteraction` architecture. The toolbar owns a plain SwiftUI button and presents an app-owned, scrollable popover with internal pages for child sessions, model selection, assignment, and host transfer.
- Actions that present another surface dismiss the popover first, then run after the dismissal animation. The trigger remains mounted throughout.
- The transcript scrubber now uses a dedicated adjustable accessibility proxy whose AX frame begins below the navigation bar. Its former full-height trailing AX frame overlapped and suppressed the More control from the closed-state tree.

## Residual Risks

- No known regression remains on the audited iPhone path. The app-owned popover intentionally differs from a native `UIMenu`; future action additions must preserve the internal-page and deferred-presentation behavior.

## Bugs

- Reported: selecting an action makes the More button disappear briefly before it reappears.
- Attempt 1 failed independent visual audit: the ellipsis was still absent for 70–100 ms during dismissal.
- Attempt 2 failed two independent visual audits. The decisive report at `.codex/evidence/20260925-235713-ios-visual-audit/evidence.md` measured no recognizable ellipsis from PTS 3.632 through 4.818, approximately 1.186 seconds.
- Attempt 2 also left `sessionOptionsMenu` absent from the closed-state accessibility tree because the full-height trailing transcript scrubber overlapped that toolbar position.
- Attempt 3 local runtime evidence passes all criteria at `.codex/evidence/20260926-0013-session-more-popover/evidence.md`: no post-clear blank frame in the 60 Hz boundary sheet, Rename presents, and the closed-state tree exposes `sessionOptionsMenu` as an enabled Button.
- Attempt 3 passed a fresh independent audit at `.codex/evidence/20260926-005111-ios-visual-audit/evidence.md`. The first fully clear 60 Hz sample already contains the ellipsis; Rename presents; and the exact enabled `sessionOptionsMenu` identifier works before and after Cancel.
