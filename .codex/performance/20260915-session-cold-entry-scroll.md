# iOS Performance Investigation: Session cold-entry scrolling

## Symptom

The first transcript scroll shortly after landing on a populated session still feels slightly laggy, even though sustained scrolling is smoother.

## Classification

- Category: hitch / SwiftUI
- Device scope: reported on the user's iPhone; Simulator comparison pending
- Build scope: latest TestFlight plus current local changes

## Baseline

- Metric: first-gesture frame continuity and main-thread work during initial transcript row reveal
- Current value: perceptible first-scroll hitch; numeric baseline pending runtime tooling
- Target value: no visible first-gesture stall; continuous populated frames during the complete first scroll
- Measurement surface: code-first SwiftUI audit, then FlowDeck recording/logs and independent performance verification

## Reproduction

1. Open a populated session.
2. As soon as the session view lands, drag into older transcript content.
3. Observe a slight lag during the first scroll that is reduced or absent on later scrolling.

## Hypotheses

- [ ] Lazy transcript rows perform expensive one-time prose parsing/render setup on the first gesture.
- [ ] Initial history/store mutations broadly invalidate the session view while the first gesture is active.
- [x] Geometry callbacks trigger redundant state updates during the first scroll: diagnostic offset/content buckets survived into Release and published throughout each drag.

## Before / After

- Before: perceptible first-scroll hitch; numeric baseline pending.
- After: the scroll tracker now emits only the boolean newest-edge state and cannot publish again while remaining in history; runtime metric pending.

## Code-First Evidence

- Before, `NewestEndTracker` projected scroll geometry into an `AtNewest` value containing 40-point offset and 100-point content-height buckets. That value changed continuously during a drag even when its product boolean stayed `false`.
- The action unconditionally reassigned `SessionDetailView.isAtBottom`, putting parent-view invalidation back on the transcript's scrolling path.
- After, the projection is a single `Bool`; SwiftUI compares that transformed value and invokes the action only when it changes. The parent callback also guards against redundant state writes.
- Apple documents this boolean projection pattern specifically to avoid updating large parts of an app for frequent scroll-geometry changes.

## Verification Blocker

Both `swift test` and the one-off FlowDeck iPhone 17 build stop before compilation because the Mac's Xcode license has not been accepted. Before/after recordings, numeric motion evidence, and independent audit remain pending until that system prerequisite is resolved.

## Regression Protection

- [x] Focused tracking-policy tests added
- [ ] First-scroll runtime recording reviewed
- [ ] Field hitch metrics recommended after TestFlight rollout
