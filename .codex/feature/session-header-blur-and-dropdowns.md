# Session header blur and trailing dropdowns

Product tier. iPhone and iPad session view.

## User story

The session header stays readable while transcript text moves underneath. More settings uses right-anchored dropdown menus for Model, Effort, and Host.

## Success criteria

- [x] Transcript text scrolls beneath a blurred header. Blur fades into clear content without a hard boundary. Header title and controls remain readable in light and dark appearance. Verify a recorded marker transcript.
- [x] Effort opens a menu with supported levels and the current choice checked. Choosing a level updates the session. Verify a synthetic host request and changed value.
- [x] Model, Effort, and Host values align with the trailing field edge. Their native menus anchor to the trailing control. Verify menu screenshots and geometry on iPhone and iPad.
- [x] Opening a menu changes no session setting. Existing host transfer and model-switch actions retain their current behavior. Verify fixture request logs and existing tests.
- [x] Relevant tests, simulator builds, and independent visual audit pass.

## Decisions

The earlier no-blur header requirement is superseded by this request. Keep transcript underlap and the hidden native navigation background. The inverted transcript cannot use the native automatic edge effect reliably, so confine a gradient-masked system material to the header. Reduce Transparency uses a matching opaque-color ramp.

Anchor each Menu to its trailing value, with a minimum 44-point touch target, instead of wrapping the whole settings row. Effort uses the existing SessionStore action and supported-level catalog.

## Evidence

- Existing SessionEffort, SessionSheetModel, and SessionListRow suites: 30 tests passed in six suites. Log: `.codex/evidence/20261016-session-header-dropdowns/tests.log`.
- Final functional build and launch passed via FlowDeck on iPhone 17 Pro / iOS 26.3. Log: `build-run-final.log`. A later edit only updates an obsolete comment.
- iPhone self-check: Model, Effort, and Host control right edges match at 363.27 points. Their popup item right edges match at 363.33 points. Evidence: settings-control-geometry.json and menu-trailing-geometry.json.
- Effort initially showed High checked. Selecting Low generated exactly one POST with effort=low, and the sheet/composer updated to Low. Fixture state and requests confirm this. Opening Model and Host generated no mutation.
- Actual transcript scrolling changed the header marker from 22 to 18 while the title and controls remained crisp. Light screenshots and a recording are in the evidence directory.
- Independent visual audit: PASS on iPhone 17 Pro and iPad Pro 11-inch, iOS/iPadOS 26.3. Report: `.codex/evidence/20261016-212907-ios-visual-audit/evidence.md`.
- Independent light and dark recordings show real transcript movement under the gradual header blur. Header controls remain readable. Menu trailing-edge differences measure 0.060 points on iPhone and zero on iPad.
- Independent fixture checks confirm exactly one request when changing Effort, the guarded host-transfer sequence, and one model-selection request. Opening menus alone produces no mutation. Selected values remain unclipped.

## Residual risks

Physical devices, older OS versions, and the Reduce Transparency setting were not exercised. No frame-time or performance claim is made. Release status is tracked separately from this feature audit.
