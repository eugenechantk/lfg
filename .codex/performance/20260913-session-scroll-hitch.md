# iOS Performance Investigation: Session Scroll Hitch

## Symptom

The populated session transcript feels sluggish during the first scroll immediately after entering the session view. Focusing the composer also lags while the software keyboard appears.

## Classification

- Category: hitch / SwiftUI / keyboard layout
- Device scope: reported device unknown; reproduced and verified on iPhone 17 Pro Simulator, iOS 26.5
- Build scope: local Debug

## Baseline

- Metric: scroll hitch rate and time to visible movement after the first injected swipe
- Current value before change: unknown; no pre-fix trace was captured
- Target: Organizer hitch rate below 5 ms/s on a physical device, with immediate gesture response
- Measurement surface: FlowDeck retained Simulator frames and process samples; Organizer or Animation Hitches remains required for a trustworthy frame-time metric

## Reproduction

1. Open a session with a long, mixed-content transcript.
2. Swipe immediately after the session appears.
3. Continue scrolling forward and backward through prose and tool rows.
4. Tap the message field and observe keyboard presentation, composer motion, and transcript position.

## Bottleneck

Each MarkdownUI-backed `SelectableProseView` could build its attributed string at a synthetic 10,000-point width during `updateUIView`, then immediately rebuild it at the real width during `sizeThatFits`. Lazy transcript layout also caused ordinary prose views to invalidate display and enumerate TextKit fragments repeatedly, although the shipping per-block MarkdownUI path does not use those custom decorations.

The keyboard follow-up confirmed a second invalidation path: on iOS 26 the floating composer was measured after `.safeAreaPadding(.bottom)`, and that measured height was fed back into the inverted transcript's content padding. The keyboard safe area could therefore participate in the measurement, letting animation steps change transcript content geometry while the keyboard moved.

## Change

- Deferred the first attributed-string render until SwiftUI supplies a concrete width.
- Reused attributed strings across width-only layout passes except for the retained legacy whole-message table renderer.
- Reused parsed Markdown blocks when a genuine width-dependent render is required.
- Removed unconditional `layoutSubviews` display invalidation.
- Gated TextKit decoration layout/enumeration off the shipping per-block path.
- Split the iOS 26 transcript and composer into sibling layers. The transcript ignores the keyboard safe area and retains its viewport; only the composer follows keyboard avoidance.
- Moved the chrome-size probe inside `.safeAreaPadding(.bottom)`, added the stable `UIWindow` bottom inset separately, and ignored sub-point measurement noise. Keyboard movement no longer rewrites transcript padding.

## Before / After

- Before: user-reported sluggishness on the first scroll; no numeric trace available.
- After: first retained frame 295 ms after swipe injection already showed transcript motion. A 12-gesture forward/reverse batch completed 12/12 gestures in 9.464 seconds with coherent movement and no blank viewport, layout jump, crash, or displaced chrome.
- Keyboard after: the software keyboard presented successfully in Simulator; the composer moved from y=730 to y=429, remained above the keyboard, accepted and cleared a draft, and the transcript/navigation layers remained populated throughout. Retained transition frames and an 11.2-second interaction recording are under `.codex/evidence/20260913-session-keyboard-performance/`.
- Limitation: retained-frame cadence cannot establish display-refresh pacing or calculate hitch rate.

## Regression Protection

- Existing transcript-window tests continue to protect the 200-row bound, ordering, and pagination behavior.
- All 15 selectable-text tests and the full LFGCore suite pass.
- Independent rich-content Simulator verification passed table/code scrolling, styling, vertical scrolling, and per-block selection.
- The post-keyboard change Debug build passed on iPhone 17 Pro Simulator (iOS 26.5); the full LFGCore suite again passed 485 XCTest and 144 Swift Testing tests.
- Watch Xcode Organizer scrolling responsiveness after release; run Animation Hitches on a representative physical device if the field metric or user feedback remains elevated.
