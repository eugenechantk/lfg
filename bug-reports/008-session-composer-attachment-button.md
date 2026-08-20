# Bug 008: Session composer attachment button does not respond

## Status: FIXED — verified 2026-08-20

## Description

In an existing session’s message composer, tapping the attachment button no
longer opens the menu for adding photos/videos or files. The same control should
offer both attachment sources and route the selected source to its system picker.

## Steps to Reproduce

1. Launch the LFG iOS app and connect to a host with an existing session.
2. Open the session detail view.
3. Locate the attachment button beside the message input.
4. Tap the attachment button.
5. Observe that no **Photos & Videos** / **Files** menu appears.

## Root Cause

The `Menu` label used only the paperclip glyph's intrinsic frame. FlowDeck's
accessibility tree measured the enabled attachment control at **23.3×25pt**, far
below the 44×44pt minimum interactive target. An exact-center automation tap
opened the menu, but normal finger taps near the small glyph were outside the
control and were swallowed, making the button appear non-responsive.

The fix keeps the visible glyph in the same leading position while expanding the
label and content shape to 44×44pt. Attachment source state, picker presentation,
loading, and sending are unchanged.

## Success Criteria

### 1. The session attachment control exposes a 44×44pt interactive frame
- [x] Verified in regression coverage
- [x] Verified in simulator

**Regression coverage:** `EXISTING` — runtime accessibility-frame assertion is
the direct test; the app currently has no app-target Swift test bundle, and the
LFGCore package does not own SwiftUI layout.

**Simulator verification:**
1. Build and launch on the dedicated iPhone 17 Pro simulator.
2. Open an existing session.
3. Inspect `composer.attach` in the FlowDeck accessibility tree.
4. **Expected:** enabled and visible with a frame at least 44×44pt.

### 2. Tapping the attachment control shows both source choices
- [x] Verified in regression coverage
- [x] Verified in simulator

**Regression coverage:** `EXISTING` — `AttachmentTray.choose` remains unchanged;
the SwiftUI `Menu` wiring is verified through the real runtime seam.

**Simulator verification:**
1. Focus the message field so the software keyboard is visible.
2. Tap `composer.attach` near the expanded target's trailing edge.
3. **Expected:** **Photos & Videos** and **Files** are both visible.

### 3. Both source choices still present their system pickers
- [x] Verified in unit test
- [x] Verified in simulator

**Unit test:** `EXISTING` — `LFGCoreTests/AttachmentsTests.swift` covers attachment
metadata/type behavior; no attachment data or picker routing changed.

**Simulator verification:**
1. Choose **Photos & Videos** and verify the Photos picker appears.
2. Dismiss it, reopen the menu, then choose **Files**.
3. **Expected:** the Files importer appears.

## Investigation Log

### Attempt 1

**Hypothesis:** The reusable session composer’s menu or hit-testing wiring was
broken while the attachment picker implementation itself remained intact.

**Changes:** Reproduced the current build through the real session composer with
the keyboard both hidden and visible. Inspected the attachment control's runtime
accessibility frame.

**Result:** The menu and both pickers present when tapping the exact 23×25pt
glyph. The undersized hit target explains the intermittent/non-responsive real
finger interaction.

### Attempt 2

**Hypothesis:** Expanding the menu label to 44×44pt will restore reliable taps
without changing picker or send behavior.

**Changes:** Expanded only the paperclip label/content shape to 44×44pt, keeping
the icon aligned to its existing leading edge.

**Result:** Focused attachment tests passed (26), the full LFGCore suite passed
(467), and the app built/launched successfully. The runtime accessibility frame
is now 44×44pt. A tap at `(64, 798)`—outside the old control but inside the new
trailing edge—opened both source choices. Both system picker routes presented.
Independent visual audit passed on a separate iPhone 17 Pro simulator. Evidence:
`.codex/evidence/20260820-155909-ios-visual-audit/evidence.md`.

## Final Summary

The attachment feature was present, but its session-composer paperclip inherited
an undersized 23×25pt interactive frame. Expanding that label/content shape to
44×44pt restored reliable finger taps without changing the visible icon, menu,
picker, loading, upload, or send behavior. Focused and full tests passed, and an
independent simulator audit verified the enlarged edge tap and both picker routes.
