# Feature: Session Liquid Glass Chrome

## User Story

As a person reading a live session, I want the navigation bar and message composer to feel like translucent Liquid Glass so the transcript remains visually continuous behind the controls.

## User Flow

1. Open a session with enough transcript content to scroll.
2. Scroll through the transcript.
3. See transcript content pass beneath the top navigation bar and bottom composer while both surfaces preserve legibility with adaptive glass.
4. Continue to type, attach, and send normally.

## Success Criteria

- SC1: The session navigation bar uses the system Liquid Glass treatment on iOS 26 and transcript content is visible moving beneath it.
- SC1a: The entire top bar is one continuous translucent glass surface; glass is not limited to separate back/title/menu elements.
- SC1b: The top treatment has no divider or hard lower edge. It transitions from glass into the sharp transcript with a soft vertical fade, matching Noto's compact editor header.
- SC2: The session composer uses a translucent rounded Liquid Glass surface on iOS 26 and transcript content is visible moving beneath it.
- SC2a: Blur and translucency remain confined to the top bar and composer; the transcript viewport itself stays sharp and readable.
- SC2b: At the newest resting position, the final transcript content clears the composer by 16 points instead of touching or overlapping its glass edge.
- SC2c: When conditional controls appear above the composer—including the child-agent bar, queued/offline notices, and one or more waiting sign-in buttons—the final transcript content clears the top of the entire expanded bottom stack by the same 16 points.
- SC2d: Adding or removing conditional bottom controls updates transcript clearance from the live stack height; normal sessions without those controls do not receive duplicate fixed spacing.
- SC2e: Sending while already at the newest position preserves the transcript's resting bottom clearance; only sending from history performs an explicit jump to newest.
- SC3: iOS 17–25 retain the existing readable raised-surface fallback without changing composer behavior.
- SC4: Existing session title/menu, transcript scrolling, composer input, attachment, and send controls remain accessible and operational.

## Test Strategy

This is a visual layout/material change with no new business logic. Swift tests cannot prove translucency or scroll-under composition. Verification therefore uses a focused app build plus Simulator screenshots/recording on iOS 26, followed by an independent visual evidence audit. Existing accessibility identifiers are retained for the composer controls and session title.

## Tests

- Build the iOS app with the saved FlowDeck configuration — verifies the availability-gated SwiftUI composition compiles for the app target.
- Simulator visual check with a long transcript at a mid-scroll position — verifies SC1 and SC2.
- Simulator interaction check for transcript scrolling and composer focus — verifies SC4.
- Simulator checks in both the composer-only and expanded conditional-stack states — verify SC2b–SC2d from accessibility-frame geometry and screenshots.
- Unit policy checks plus a Simulator send interaction — verify SC2e without relying on an animated re-anchor at offset zero.
- Source availability review — verifies the existing iOS 17–25 raised-surface fallback remains in place for SC3.

## Implementation Details

- Keep the controls in the native navigation toolbar, as Noto does, so their layout and interaction remain system-owned.
- Expand the transcript through the top and bottom container safe areas so rows physically exist behind the navigation bar and home-indicator region.
- On iOS 26, float the session-only bottom chrome over the transcript, include the home-indicator inset in its measured height, and use that live height as scroll-content clearance at rest. The measurement wraps the outer `VStack`, so pending-send rows, the offline notice, child-agent control, every waiting sign-in request, and the composer contribute automatically when present.
- Add 16 points beyond the measured bottom chrome height so the newest content has deliberate breathing room above the composer's glass edge and shadow.
- Let the system navigation toolbar own its localized scroll-edge treatment. Do not apply a scroll-edge effect to the inverted transcript itself: iOS 26 expands that effect across the viewport and obscures the main content.
- Keep the system navigation toolbar controls and its backdrop transparent on iOS 26. Because LFG's intentionally inverted transcript cannot use SwiftUI's automatic scroll-edge effect without spreading blur across the viewport, place a non-interactive full-width regular Liquid Glass field behind the status/navigation region and mask its lower portion with a vertical alpha gradient. Expand only the glass shape beyond the visible field so its specular perimeter is clipped away without changing the original blur material.
- Measure the navigation-safe content's global top before expanding the transcript into the safe area. Use that value for the glass region, extend the fade 34 points into the transcript, and keep the glass fully opaque until 12 points before the navigation boundary.
- Explicitly disable automatic scroll-edge effects for the inverted transcript. Its transformed coordinate system causes both automatic and soft edge effects to expand across the viewport instead of remaining at the bars.
- On iOS 17–25, retain the prior `safeAreaInset` behavior as the readable compatibility path.
- Keep the composer in the existing availability-gated `GlassPanel`, with a solid raised-surface fallback on iOS 17–25.
- Use regular Liquid Glass for the iOS 26 composer so transcript movement remains perceptible without sharp underlying text competing with the input.
- Do not force toolbar background visibility, which would make the navigation material more opaque.

## Residual Risks

The restored regular Liquid Glass header independently passed on iPhone 17 Pro / iOS 26.3: its earlier adaptive blur character is preserved while no enclosing outline, side rim, rounded rectangle, or divider remains; bidirectional scrolling preserved the progressive blur-to-sharp transition and toolbar controls remained functional. Evidence: `.codex/evidence/20260913-0245-header-glass-restore-independent-audit/`. The bottom-clearance follow-up also independently passed: the final transcript item ended at `y=709` and the composer field began at `y=730`, leaving a measured 21-point content-frame gap with no overlap, while mid-scroll evidence confirmed content can still pass behind the floating composer. Evidence: `.codex/evidence/20260912-182257-ios-bottom-clearance-audit/`. A subsequent dynamic-stack audit confirmed the composer-only state keeps that 21-point frame gap without duplicate padding and a child-agent state leaves 35 points between the last transcript control and `childSessionsComposerBar`; all conditional rows share the same outer measurement. The synthetic sign-in request did not render during this audit, so sign-in-button inclusion is source-verified through that common boundary rather than directly screenshot-tested. Evidence: `.codex/evidence/20260912-183900-ios-dynamic-bottom-stack-audit/`. The iOS 17–25 fallback remains availability-gated in source but was not rendered on an older Simulator in this pass.

## Bugs

- First pass left the transcript bounded by the top and bottom safe areas, so the toolbar had no content to refract and the home-indicator region formed a visible cutoff below the composer.
- `safeAreaBar(edge: .bottom)` was rejected after runtime testing because its automatic inset is applied to the wrong end of this intentionally inverted transcript, moving the newest page offscreen.
- Applying `.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])` to the inverted transcript caused iOS 26 to render a dark blurred mass across nearly the entire viewport. The effect belongs to the stationary system toolbar, not the scrolling content.
- The first full-width glass prototype used the content-relative safe-area inset and placed an oversized rectangle below the toolbar. The corrected implementation measures the content's global top boundary, then offsets an exactly matching glass plane upward into the status/navigation region.
- Follow-up report: the corrected rectangular plane still read as an opaque bar with a divider-like lower boundary instead of Noto's translucent scroll-edge fade.
- Follow-up report: matching the resting transcript clearance exactly to the measured composer height left the final content too close to the glass edge and visually overlapping it.
- Follow-up report: an idle send briefly lifted the transcript because send classification ran after the optimistic busy mutation, adding a false pending strip, while the view also performed a redundant animated jump from its already-pinned offset.
- Follow-up report: the custom top glass field still shows a faint perimeter highlight, making the header read as a bounded rectangle rather than an edgeless blur fade.
- Follow-up report: replacing the top glass field with `.ultraThinMaterial` removed the perimeter but visibly degraded the blur. The correction restores the original regular Liquid Glass and clips only its off-field rim.

## Deployment

- TestFlight `1.3.0 (202609130248)` contains the restored regular Liquid Glass header with rim-only clipping, plus the dynamic full-bottom-stack clearance and send-time bottom-stability fixes. App Store Connect verification passed: IPA version/build matched, processing state `VALID`, train `1.3.0` is the highest existing train, and internal state is `IN_BETA_TESTING`.
