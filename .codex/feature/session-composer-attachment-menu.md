# Feature: Session Composer Attachment Menu Regression

## User Story

As an LFG iOS user, I want the session message composer’s attachment button to
open photo/video and file choices so I can include attachments in a message.

## User Flow

1. Open an existing session.
2. Tap the attachment button beside the message input.
3. Choose either **Photos & Videos** or **Files**.
4. Select an item in the system picker.
5. See the attachment in the composer and send it with the message.

## Success Criteria

- [x] SC1: Tapping the session composer attachment button presents a responsive menu containing **Photos & Videos** and **Files**. — **Verify by:** app-target regression coverage plus FlowDeck interaction recording.
- [x] SC2: Choosing **Photos & Videos** presents the system photo picker; choosing **Files** presents the system file importer. — **Verify by:** focused presentation-state tests plus FlowDeck interaction recording.
- [x] SC3: Existing attachment selection and send behavior remains unchanged. — **Verify by:** existing attachment tests, focused build/test, and simulator smoke verification.
- [x] SC4: The session attachment control has a stable accessibility identifier for UI automation. — **Verify by:** FlowDeck accessibility-tree assertion.

## Test Strategy

Determine whether the regression is in menu hit testing, presentation state, or
composer layout. Preserve the failing interaction as focused app-target coverage
where the owning behavior can be exercised deterministically; use FlowDeck for
the runtime SwiftUI/menu/system-picker wiring that Swift Testing cannot prove.

## Tests

- Runtime accessibility assertion: `composer.attach` is enabled, visible, and at
  least 44×44pt.
- Runtime interaction: tapping the expanded target while the keyboard is visible
  opens a menu containing **Photos & Videos** and **Files**.
- Runtime picker routing: each menu item presents the corresponding system picker.
- Existing `LFGCoreTests/AttachmentsTests.swift` suite protects attachment naming,
  type, and metadata behavior.

## Implementation Details

Keep the fix local to the reusable session composer and attachment presentation
surface. Do not alter upload, outbox persistence, or host API behavior.

Root cause: the paperclip `Menu` label inherited the glyph's intrinsic 23×25pt
frame. The fix gives the label a 44×44pt content shape while preserving the
visible icon's leading alignment.

## Residual Risks

SwiftPM cannot directly prove SwiftUI hit testing because this project has no
app-target Swift test bundle. The real runtime seam is covered through the
FlowDeck accessibility frame and edge-tap interaction. No known residual risk
remains for the reported interaction.

## Verification Evidence

- `swift test --filter Attachment` — 26 attachment tests passed.
- `swift test` — 367 XCTest cases plus 100 Swift Testing cases passed (467 total).
- `flowdeck run -S 60FCA83F-230A-4D69-8835-04D99AD5911B --json` — build, install,
  and launch passed on the dedicated iPhone 17 Pro simulator.
- Runtime accessibility tree — `composer.attach` is enabled and visible with
  frame `{x: 24, y: 776, width: 44, height: 44}`.
- Edge-tap proof — tapping `(64, 798)`, outside the old 23.3pt-wide frame but
  inside the new target, opened both attachment choices.
- Picker routing — **Files** presented the Files importer and **Photos & Videos**
  presented the Photos picker.
- Recordings:
  `.codex/evidence/20260820-session-attachment-hit-target/attachment-menu-edge-tap.mov`
  and
  `.codex/evidence/20260820-session-attachment-hit-target/photo-picker-route.mov`.
- Independent iOS visual audit: **PASS**. Report and independent recording:
  `.codex/evidence/20260820-155909-ios-visual-audit/evidence.md` and
  `.codex/evidence/20260820-155909-ios-visual-audit/03-edge-tap-opens-menu.mov`.

## Bugs

- `bug-reports/008-session-composer-attachment-button.md`
