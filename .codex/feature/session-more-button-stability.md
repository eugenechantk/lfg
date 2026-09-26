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
- SC4: The action surface remains Apple's native `UIMenu`, including native scrolling, submenus, roles, and dismissal behavior.
- SC5: The closed-state More control uses a bare system ellipsis whose optical size matches the system back chevron and whose center matches the native 44-point toolbar source control.

## Test Strategy

- Treat this as a UIKit presentation-lifecycle regression: only a real native-menu recording can prove the disappearance no longer occurs.
- Build and launch with FlowDeck, record the complete tap-menu-select-dismiss/present flow, normalize the dismissal boundary to 60 Hz, and inspect every boundary sample.
- Inspect the closed-state runtime accessibility tree before opening and after dismissing the selected action.

## Tests

- Focused existing app tests covering session-detail behavior, if discoverable.
- Simulator closed-state screenshot: compare the More glyph's optical size and center against the system back chevron and its own glass control (SC5).
- Simulator interaction recording: open More, select an action, and observe the button through dismissal and resulting presentation (SC1-SC4).

## Implementation Details

- Reproduced on iOS 26.3: UIKit temporarily removes the `UIButton` image while dismissing its primary-action `UIMenu`.
- Attempt 1 rendered the ellipsis as a SwiftUI overlay, but the independent 60-fps audit showed that the toolbar hides the entire representable subtree for 70–100 ms.
- Attempt 2 returned a stable UIKit host view containing sibling glyph and menu-interaction views. Independent audits still found blank intervals of roughly 0.44 seconds and 1.186 seconds because the toolbar participates in UIKit's context-menu source-preview lifecycle as a unit.
- Attempt 3 removed the `UIContextMenuInteraction` architecture and used an app-owned popover. It fixed the blank interval, but was rejected because the action surface was no longer Apple's native menu.
- The final architecture restores a real `UIButton.showsMenuAsPrimaryAction` + stable root `UIMenu`. A `UIDeferredMenuElement` reads current actions only when a presentation begins, preserving native scrolling and submenu behavior without resetting an open menu during transcript updates.
- The UIKit source button remains in the system toolbar and retains native anchoring and Liquid Glass, but its own glyph is transparent. A separate, noninteractive bare `ellipsis` is installed directly on the live `UINavigationBar`, outside UIKit's context-menu source subtree, so source-preview cleanup cannot blank the visible glyph.
- The proxy follows the native source button's resolved center instead of centering against the full navigation bar, then applies the full 44-point control footprint around that center. This keeps the visible glyph and its accessibility frame aligned with the actual Liquid Glass control while preserving the native-menu architecture.
- The independent navigation-bar proxy owns the stable `sessionOptionsMenu` accessibility element and forwards its activation to the underlying native menu source.
- The transcript scrubber now uses a dedicated adjustable accessibility proxy whose AX frame begins below the navigation bar. Its former full-height trailing AX frame overlapped and suppressed the More control from the closed-state tree.

## Residual Risks

- Local and fresh independent iPhone runtime evidence pass the icon alignment, native-menu, action, exact 60 Hz continuity, and accessibility criteria.
- The visible glyph is intentionally a navigation-bar sibling of the native menu source. Future navigation-bar work must preserve that separation and remove the installed glyph when the session view dismantles.

## Bugs

- Reported: selecting an action makes the More button disappear briefly before it reappears.
- Attempt 1 failed independent visual audit: the ellipsis was still absent for 70–100 ms during dismissal.
- Attempt 2 failed two independent visual audits. The decisive report at `.codex/evidence/20260925-235713-ios-visual-audit/evidence.md` measured no recognizable ellipsis from PTS 3.632 through 4.818, approximately 1.186 seconds.
- Attempt 2 also left `sessionOptionsMenu` absent from the closed-state accessibility tree because the full-height trailing transcript scrubber overlapped that toolbar position.
- Attempt 3 local runtime evidence passes all criteria at `.codex/evidence/20260926-0013-session-more-popover/evidence.md`: no post-clear blank frame in the 60 Hz boundary sheet, Rename presents, and the closed-state tree exposes `sessionOptionsMenu` as an enabled Button.
- Attempt 3 passed a fresh independent audit at `.codex/evidence/20260926-005111-ios-visual-audit/evidence.md`. The first fully clear 60 Hz sample already contains the ellipsis; Rename presents; and the exact enabled `sessionOptionsMenu` identifier works before and after Cancel.
- Attempt 3 was subsequently rejected by product review because it replaced the native menu with a custom popover.
- The final native-menu architecture passes local runtime verification at `.codex/evidence/20260926-095829-native-session-more/evidence.md`: the system context menu is visible, Rename presents, the normalized 60 Hz boundary has zero post-menu blank samples, and the final closed AX tree exposes an enabled `sessionOptionsMenu` Button.
- The final architecture passed the required independent audit at `.codex/evidence/20260926-100348-ios-visual-audit/evidence.md`. The first menu-clear frame at PTS 4.900 already contains the ellipsis; all ten pre-alert samples through PTS 5.050 retain it; Rename begins at PTS 5.067; blank post-clear frames: 0 (0.000 seconds). The audit also confirmed native submenu navigation, overflow scrolling and scrollbar, destructive styling, and the enabled visible 44×44 `sessionOptionsMenu` Button before opening and after Cancel.
- Product review then found the visible `ellipsis.circle` optically undersized inside the already-circular glass control and vertically offset from the system back chevron.
- The alignment revision replaces it with a 17-point semibold bare `ellipsis`, follows the native menu source's resolved center, and applies a 44×44 visual/accessibility frame around that center. Local evidence at `.codex/evidence/20260926-session-more-icon-alignment/evidence.md` passes the closed-state appearance, exact visible/enabled 44×44 AX target, native Rename action, and normalized 60 fps dismissal checks with 0 blank post-menu samples.
- The alignment revision passed the fresh independent audit at `.codex/evidence/20260926-112043-ios-visual-audit/evidence.md`. Its same-screen compact capture places the system Back and More controls in equal 44-point circles centered at `y = 84`, with comparable optical symbol weight. The exact normalized 60 fps boundary shows the ellipsis in the first fully menu-clear sample and every sample through Rename onset; blank post-clear frames: 0 (0.000 seconds). The audit also confirmed native `UIMenu`, Rename presentation, and exactly one visible/enabled 44×44 `sessionOptionsMenu` before opening and after Cancel.
