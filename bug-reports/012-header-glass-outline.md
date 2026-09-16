# Bug 012: Subtle outline wraps the translucent session header

## Status: FIXED — verified 2026-09-13

## Description

The session header now blurs and fades correctly, but a faint border-like outline remains around the header region. The glass should transition into the transcript without a visible enclosing shape, divider, or perimeter highlight.

## Steps to Reproduce

1. Launch LFG on iOS 26 and open a session with a scrollable transcript.
2. Scroll until transcript content is visibly behind the navigation header.
3. Inspect the header perimeter and the fade into the sharp transcript.
4. Observe a subtle line that makes the header read as a bounded glass rectangle instead of an edgeless blur field.

## Root Cause

`topChromeFade` applied `.glassEffect(.regular, in: Rectangle())` to a view whose bounds matched the visible header field. Liquid Glass adds a subtle specular rim at the effect shape's perimeter. The vertical alpha mask hid the lowest edge progressively, but the surface's inset top and side highlights remained visible as a rounded enclosing outline.

## Success Criteria

### 1. The session header has no visible enclosing outline
- [x] Verified in Simulator

**Unit test:** Not applicable — the outline is emitted by the iOS Liquid Glass compositor and is not represented in view-model or layout state.

**Simulator verification:**
1. Build and launch on iPhone 17 Pro / iOS 26.3.
2. Open a long transcript and place text behind the navigation region.
3. Capture the header at full-screen scale and inspect its top, side, and lower perimeter.
4. **Expected:** Glass blur remains visible but no rounded rectangle, side rim, or divider encloses the header.

### 2. The original regular Liquid Glass blur and soft fade are preserved
- [x] Verified in Simulator

**Unit test:** Not applicable — material blur and mask compositing require rendered-image verification.

**Simulator verification:**
1. Record scrolling a long transcript in both directions beneath the header.
2. Inspect the transition below the title and toolbar buttons.
3. **Expected:** Content uses the original regular Liquid Glass character, blurs under the header, and becomes progressively sharp without a hard cutoff.

### 3. Header controls remain usable
- [x] Verified in Simulator

**Unit test:** `EXISTING` — the custom glass remains non-interactive and accessibility-hidden; no control hierarchy changes.

**Simulator verification:**
1. Tap the options menu, dismiss it, then navigate back.
2. **Expected:** Both controls respond normally and the glass field does not intercept input.

## Investigation Log

### Attempt 1

**Hypothesis:** The custom full-width `glassEffect` rectangle still renders Liquid Glass's own perimeter highlight, so masking only the lower alpha transition cannot fully hide the enclosing shape.

**Changes:** None yet.

**Result:** Confirmed on iPhone 17 Pro / iOS 26.3. Evidence: `.codex/evidence/20260912-1956-header-border-before/header-border-before.jpg`. The rounded perimeter matches the bounds of the custom glass field.

### Attempt 2

**Hypothesis:** Overscanning the actual glass surface past every visible edge, then clipping and applying the existing vertical fade to only its interior, will preserve blur while moving Liquid Glass's specular rim off-screen.

**Changes:** Render the glass rectangle 32 points beyond the header on all sides before clipping it to the visible fade field.

**Result:** Failed. The project built, but the enclosing rim remained in the Simulator. Moving the nominal bounds did not suppress the shaped glass object's own optical perimeter.

### Attempt 3

**Research:** Noto's editor keeps navigation controls system-owned and extends content beneath a transparent navigation bar; it does not apply a full-width custom `glassEffect` shape behind the header. The Liquid Glass guidance likewise reserves shaped glass for controls and recommends system/material-backed bar treatment rather than layering another glass object over a toolbar.

**Hypothesis:** Keep the back and menu controls as native Liquid Glass, but render the borderless header field with a masked translucent material. Material blur has no specular shape perimeter, so it can fade into the transcript without an enclosing outline.

**Changes:** Replace the full-field custom `glassEffect` rectangle with `.ultraThinMaterial`, preserving the same height, vertical mask, transparent navigation backdrop, and non-interactive behavior.

**Result:** Local verification passed on iPhone 17 Pro / iOS 26.3. The app built and launched, the enclosing rim disappeared, transcript text remained visibly blurred beneath the header during bidirectional scrolling, and the menu/back controls responded normally. Full LFGCore suite: 144 tests passed. Motion evidence: `.codex/evidence/20260912-1959-header-border-after/header-scroll-after.mov`. The independent visual audit also passed.

### Attempt 4

**User feedback:** Replacing Liquid Glass with `.ultraThinMaterial` removed the outline but degraded the blur. The requested change is border removal only; the original blur must remain unchanged.

**Hypothesis:** Restore `.glassEffect(.regular)` exactly and expand only its shape boundary outside the visible header field. The existing fade mask can then clip the off-field specular perimeter while preserving the original glass compositor and all layout values.

**Changes:** Restored regular Liquid Glass and passed a negatively inset rectangle to the effect. Fade height, solid stop, frame, mask, toolbar configuration, and hit-testing behavior are unchanged.

**Result:** PASS. Build and local Simulator verification passed. The independent audit confirmed that the original regular Liquid Glass character is restored, the full-header rim is absent, bidirectional scrolling retains the soft blur-to-sharp fade, and menu/back interactions work. Evidence: `.codex/evidence/20260913-0245-header-glass-restore-independent-audit/`.

## Final Verification

Independent audit: **PASS**. The header again uses regular Liquid Glass with its earlier adaptive blur character. No enclosing outline, side rim, rounded rectangle, or divider remained; only the expected native circular glass around the back and menu controls was visible. Bidirectional scrolling preserved the progressive blur-to-sharp transition, and menu/back interactions passed. Evidence: `.codex/evidence/20260913-0245-header-glass-restore-independent-audit/`.
