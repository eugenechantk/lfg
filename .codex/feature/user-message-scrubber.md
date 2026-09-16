# Feature: User Message Scrubber

## User Story

As a transcript reader, I can long-press the trailing edge and drag vertically to jump between my messages, so I can navigate long sessions without repeatedly scrolling.

## User Flow

1. Open a session transcript; no user-message scroll indicator is visible.
2. Long-press the trailing-edge activation zone.
3. The native iOS scroll indicator appears and the nearest user-message anchor is selected.
4. Drag upward or downward; the selection moves through user turns in chronological screen order and the transcript jumps to each selected bubble.
5. Release; the native indicator fades away.
6. With VoiceOver, focus the user-message index and swipe up/down to move through the same anchors.

## Success Criteria

- [x] SC1: The native scroll indicator is hidden until a trailing-edge long press activates it and fades again after release.
- [x] SC2: Drag position maps from oldest user message at the top to newest user message at the bottom, clamped at both ends.
- [x] SC3: Only messages that render as user bubbles become anchors; tool and thinking records do not.
- [x] SC4: Selecting an older anchor expands the transcript render window as needed before scrolling to it.
- [x] SC5: Each selected anchor is centered in the transcript and selection changes provide light haptic feedback.
- [x] SC6: Normal transcript scrolling and the existing lower-band double-tap remain available.
- [x] SC7: The custom gesture has a stable accessibility identifier and an adjustable VoiceOver alternative.

## Test Strategy

Pure anchor filtering, drag-position mapping, clamping, and required-window calculation live in `LFGCore` and are covered by Swift Testing. Simulator recording proves the custom gesture, transient native indicator, window expansion, scrolling, and coexistence with ordinary transcript scrolling.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/UserMessageScrubberTests.swift`
  - `anchorsIncludeOnlyRenderedUserBubblesInChronologicalOrder` — SC2, SC3
  - `positionMapsAcrossAllAnchorsAndClampsAtEdges` — SC2
  - `positionReturnsNilWithoutUsableAnchorsOrHeight` — SC2
  - `requiredWindowExpandsOnlyForOlderTargets` — SC4

### Simulator

- Record the session transcript from hidden indicator through long-press, upward drag, anchor jump, and release — SC1, SC4, SC5, SC6.
- Inspect the accessibility tree for `userMessageScrubber` and exercise its adjustable action if supported by the automation surface — SC7.

## Implementation Details

- Product-tier iOS/iPadOS SwiftUI feature.
- A transparent 44-point trailing-edge `UIScrollView` owns a long-press recognizer and renders only its native vertical scroll indicator.
- `UserMessageScrubber` in `LFGCore` derives stable anchors and maps vertical gesture position to an anchor index.
- The view snapshots anchors only when the transcript version changes, avoiding an O(transcript) filter on every drag update.
- Older targets grow the existing inverted transcript window before `ScrollViewProxy.scrollTo` runs on the next main-actor turn.
- UIKit controls the indicator's native appearance, placement, and fade timing; there is no custom thumb, rail, or ordinal pill.

## Residual Risks

The independent simulator audit passed. FlowDeck cannot emit continuous touch-move events, so the drag-change path was verified through long presses at distinct vertical positions plus unit coverage of continuous position mapping. Haptic feedback remains API-verified because Simulator recordings cannot capture tactile output.

Audit evidence: `.codex/evidence/20260826-112655-ios-visual-audit/evidence.md`

## Bugs

None yet.
