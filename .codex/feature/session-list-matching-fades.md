# Session fades match the lists

Product tier. iPhone and iPad session view.

## User story

Use the same dark edge fading as the Sessions and Tasks lists at both edges of the transcript. Transcript content continues behind the header and floating composer.

## Success criteria

- [x] The session header uses the lists' shared ChromeFade, replacing its separate material fade. Dark appearance matches the lists' black fade; light appearance uses the same adaptive treatment.
- [x] The bottom uses the same shared fade behind the composer and floating controls. Both edges transition smoothly during recorded transcript scrolling without a hard cutoff or blur across the viewport.
- [x] Header and composer controls stay readable and usable. Keyboard presentation moves the bottom fade with the composer without covering history or leaving a detached band.
- [x] Scrolling, newest-message clearance, and floating pill/queued-message layout stay intact on iPhone and iPad.
- [x] Existing transcript geometry tests, simulator build, and independent visual audit pass.

## Implementation and verification

Reuse ChromeFade's existing gradients, scrim, and dark glass tint. Keep the flipped transcript's native edge effects disabled. Anchor the bottom fade behind the existing measured composer, so it follows the keyboard without changing transcript layout or chrome measurement. Older OS versions use the shared color ramp without Liquid Glass.

This is a visual reuse change. Existing TranscriptWindow tests cover clearance and history behavior; screenshots and scroll/keyboard recordings prove rendering. Compare the unchanged Sessions and Tasks list fades with the session on iPhone and iPad, including dark and light appearance.

## Evidence

- Existing TranscriptWindow tests: 41 passed with no failures. Log: `.codex/evidence/20261016-session-list-fades/tests.log`.
- Final FlowDeck build and launch passed on iPhone 17 Pro / iOS 26.3. Log: `.codex/evidence/20261016-session-list-fades/build-run-final.log`.
- Network-free send-follow fixture displays running-subagent and queued-message pills above the composer. Parent light/dark inspection shows adaptive fades with no opaque band across the transcript. Dark screenshot: `self-dark.jpg` in the evidence directory.
- Independent visual audit: PASS on iPhone 17 Pro and iPad Pro 11-inch, iOS/iPadOS 26.3, in light and dark appearance. Report: `.codex/evidence/20261016-230749-ios-visual-audit/evidence.md`.
- Four recorded scroll flows show real numbered transcript movement under both fades. Fresh Sessions and Tasks list references match the session's black treatment. Header and composer remain readable with no hard cutoff or blur across the viewport.
- Keyboard recordings show the pill, queued row, and composer moving together: 331 points on iPhone from history and 350 points on iPad at newest. The bottom fade stays attached, and newest-message clearance remains intact.
- Both simulators were restored to light appearance; captures stopped and the audit iPad shut down. The read-only local reference fixture was stopped after verification.

## Residual risks

Physical devices, older OS versions, and accessibility appearance overrides were not exercised. No frame-time or performance claim is made. These changes remain local; no commit or new TestFlight release is part of this request.
