# Bug 017: Session transcript still lags on the first scroll

## Status: INVESTIGATING

## Description

Immediately after landing on a populated session, the first transcript scroll still feels slightly laggy. Subsequent scrolling is smoother. The initial gesture should be as responsive as steady-state scrolling without changing transcript order, newest-edge behavior, or history pagination.

## Steps to Reproduce

1. Open a populated session.
2. Begin scrolling into older transcript content immediately after the view lands.
3. Observe a slight hitch during the first gesture.
4. Compare with later scrolling in the same session, which feels smoother.

## Root Cause

The Release build still used Phase-1 diagnostic offset and content-height buckets as the value emitted by `onScrollGeometryChange`. Those buckets changed roughly every 40 points of a drag, so SwiftUI repeatedly invoked the tracker action while scrolling. The action then assigned `isAtBottom` even when its boolean value had not changed, invalidating the parent session view and re-diffing the transcript during the gesture. Product behavior only needs the transition between “at newest” and “in history.”

## Success Criteria

### 1. Scrolling within transcript history emits one stable tracking value instead of diagnostic offset buckets.
- [ ] Verified in unit test
- [ ] Verified in Simulator

**Unit test:** `NEW` — `TranscriptWindowTests.swift` → `NewestEndTrackingTests.testHistoryOffsetsCollapseToOneTrackingValue`.

**Simulator verification:** Open a populated session, immediately scroll through several hundred points of history, and confirm the transcript remains populated and responsive without repeated `tracker.atNewest` transitions.

### 2. Crossing the newest-edge threshold still updates follow behavior correctly.
- [ ] Verified in unit test
- [ ] Verified in Simulator

**Unit test:** `NEW` — `TranscriptWindowTests.swift` → `NewestEndTrackingTests.testTrackingValueChangesOnlyAcrossNewestBoundary`.

**Simulator verification:** Move from newest into history and back; confirm exactly one edge transition in each direction and preserved newest-follow behavior.

### 3. Keyboard focus from history and Send-to-newest behavior remain correct.
- [ ] Verified in unit test
- [ ] Verified in Simulator

**Unit test:** `EXISTING/MODIFIED` — the keyboard reader-intent and send-follow cases in `TranscriptWindowTests`.

**Simulator verification:** From history, focus/dismiss without jumping; then send and confirm the complete new user row is brought above the composer.

## Investigation Log

### Attempt 1

**Hypothesis:** The remaining hitch is one-time work performed by lazily created transcript rows or initial session-state invalidation during the first gesture.

**Changes:** None.

**Result:** Confirmed. The tracker emitted an `AtNewest` value containing `yBucket` and `contentBucket`, so it changed throughout every scroll even while `atNewest` remained false. The callback unconditionally reassigned `isAtBottom`.

### Attempt 2

**Hypothesis:** Emitting only the boolean newest-edge state will let SwiftUI's Equatable geometry transform suppress every in-history callback, removing the repeated parent invalidation while retaining the one state transition the product needs.

**Changes:** Replaced the diagnostic tracking struct with a boolean policy value and guarded the outer state assignment against redundant writes.

**Result:** Source-level fix complete. Unit and Simulator verification are pending the Xcode license blocker.

### Verification blocker

`swift test` reports that the Xcode license agreements have not been accepted, and FlowDeck's one-off iPhone 17 build stops while resolving Apple tooling. Runtime validation cannot begin until the license is accepted on this Mac.
