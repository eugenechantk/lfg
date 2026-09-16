# Bug 015: Idle transcript exposes a scrollable bottom void

## Status: FIXED — verified 2026-09-15

## Description

When a session is idle and the software keyboard is hidden, the transcript has too much empty space after its newest message. The reader can drag into that empty region. The newest transcript row should instead rest slightly above the floating composer, with no additional end padding that can be revealed by scrolling.

## Steps to Reproduce

1. Open a populated idle session at its newest transcript edge.
2. Confirm the software keyboard is hidden.
3. Drag the transcript toward its newest/bottom edge.
4. Observe that a large blank region after the newest row can be exposed above the composer.

## Root Cause

The iOS 26 transcript reserves composer and keyboard clearance with structural `.padding(.top)` on the inverted `LazyVStack`. Structural top is the visual bottom after inversion, so the newest row initially appears in the right place. But that padding is also part of the scrollable transcript content. The composer-sized spacer can therefore be exposed during edge interaction or retained when a programmatic scroll stops away from the actual newest edge.

The boundary belongs in the scroll view's content margin instead: it should inset the resting edge without adding a fake transcript region after the newest row.

## Success Criteria

### 1. The idle newest row rests slightly above the composer without a scrollable spacer after it.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `NEW` — `ios/LFGCore/Tests/LFGCoreTests/TranscriptWindowTests.swift` → idle bottom content-margin policy.

**Simulator verification:** Launch the populated fixture with the keyboard hidden, record a drag toward and away from the newest edge, and confirm no composer-sized blank region can settle above the input panel.

### 2. Keyboard focus and wrapped Send still keep the complete newest row above the raised composer.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `EXISTING` — focused keyboard margin and focused-send follow policy tests in `TranscriptWindowTests`.

**Simulator verification:** Focus the composer and send the wrapped fixture draft; confirm the latest assistant/user content remains fully above the composer with the software keyboard present.

### 3. Moving the boundary does not reintroduce transcript re-layout churn or scrolling stalls.
- [x] Verified in unit test
- [x] Verified in Simulator

**Unit test:** `NEW` — the boundary policy produces one clamped margin from stable keyboard/chrome inputs.

**Simulator verification:** Review the idle-edge, focus, and send recordings for populated frames, continuous motion, and no repeated corrective jump.

## Investigation Log

### Attempt 1

**Hypothesis:** The inverted lazy stack's structural bottom padding is doing two jobs—composer occlusion and scrollable content extent—so the clearance needed behind the floating composer is exposed as transcript content when the reader drags to the newest boundary.

**Changes:** None.

**Result:** Confirmed structurally and in the populated fixture. A fresh idle edge had the desired ~28 pt visual gap, but inspection showed the full composer/keyboard clearance is `LazyVStack` content padding. Edge gestures and programmatic anchors can therefore expose or retain that fake tail region. Evidence: `.codex/evidence/20260915-idle-bottom-void/`.

### Attempt 2

**Hypothesis:** Moving the floating-chrome reserve to `ScrollView.contentMargins` and targeting the real newest sentinel would preserve the occlusion boundary without adding transcript rows. The inverted stack's generic structural-top padding also had to be removed because it became a second, drag-reachable visual-bottom spacer.

**Changes:** Replaced the inverted `LazyVStack`'s dynamic top padding with a clamped scroll-content margin; made explicit newest/send/keyboard transitions target the actual newest edge; followed discrete composer-height changes only while already at the newest edge; removed the redundant inverted bottom padding. When the keyboard is visible, the margin subtracts the home-indicator inset already owned by the keyboard.

**Result:** Fixed. In the standard idle fixture, the latest row stayed at `y=641`, height `65.281`, before and after a newest-edge drag. The wrapped sent row likewise stayed at `y=623`, height `65.281`, before and after the drag, ending about 42 pt above the input field. With the software keyboard visible, the standard latest row ended at about `y=387` above the field at `y=429`; the wrapped sent bubble ended at about `y=369` above the same field. Independent visual review passed all states. Independent motion review found no blank viewport or repeated corrective jump; the send window's largest frame gap was 46.667 ms, with zero gaps above 50 ms. Evidence: `ios/.codex/evidence/20260915-idle-bottom-void/` and `ios/.codex/evidence/20260915-final-transition-independent-review/evidence.md`.
