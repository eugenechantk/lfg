# Mobile session floating pills

## User story

Keep the transcript visible while session controls float above it.

## User flow

1. Open a mobile session.
2. Show the Subagents pill only while at least one subagent runs.
3. Scroll history behind the Subagents pill and queued messages.
4. Tap each control to open its existing actions.

## Success criteria

- [x] SC1: Files and Terminal never appear in the composer pill row. Completed-only subagents do not create a row. Verify with Swift visibility tests and Simulator states.
- [x] SC2: Running subagents show one working pill that opens the subagents sheet. Verify with Simulator and a visibility test.
- [x] SC3: The bottom stack has no full-width opaque backdrop. Transcript content moves behind the individual glass pills and queued message. Verify with a Simulator recording.
- [x] SC4: Queued message actions remain anchored and usable. Verify by opening and dismissing the menu in Simulator.
- [x] SC5: The app builds and relevant package tests pass. Verify with FlowDeck and Swift Testing.

## Platform and scope

iOS SwiftUI app and the existing LFGCore presentation model. Retain transcript clearance, keyboard handling, composer controls, and Session sheet access to Files and Terminal.

## Decision log

- Use the existing GlassPanel material on each capsule. Clear the shared bottom fade so transcript remains visible between the controls.
- Use a network-free DEBUG fixture for repeatable scroll and subagent lifecycle evidence.
- Unit tests cover visibility. Rendering and action placement require Simulator evidence.

## Verification evidence

- SC1 / SC2: `swift test --package-path ios/LFGCore --filter 'SubagentPillTests|QueuedStripRowTests'` passed 13 tests. Visibility covers all five statuses, no agents, and the last running agent finishing. The regression tests failed before `isVisible` existed. Logs: `.codex/evidence/20261016-mobile-session-pills/{focused-tests,visibility-before}.log`.
- SC1: Finished-only Simulator state has no composer pill or leftover row spacing: `finished-no-pill.jpg` and `finished-tree.json` in the evidence directory.
- SC2: Tapping `composerPill.subagents` opened the sheet listing one running, one completed, and one failed agent: `subagents-sheet.jpg`.
- SC3: On the iPhone 17 Pro Simulator, scrolling down moved blue transcript bubbles behind both floating capsules. Screenshot: `running-scrolled.jpg`. Recording: `scroll-and-actions.mov` (25 seconds).
- SC4: Tapping `pendingStripRow` opened the actions 8 points above the source row; tapping the row again dismissed them. Screenshot: `queued-menu.jpg`.
- SC5: `swift test --package-path ios/LFGCore` passed 423 tests in 63 suites. `flowdeck run -S 1E27DFC3-E7FF-4D9A-81CC-21F8A1734240 --launch-env='LFG_SEND_FOLLOW_FIXTURE=1 LFG_SESSION_OVERLAY_FIXTURE=running' --json` built and launched successfully. Logs: `core-tests.log` and `build.log`.
- `git diff --check` passed.
- Independent visual audit: PASS. Report: `.codex/evidence/20261016-185228-ios-visual-audit/evidence.md`. The auditor independently confirmed active, completed-only, and empty subagent states, light/dark scroll-under rendering, subagent sheet navigation, and anchored queue-menu dismissal. It rebuilt with FlowDeck and ran the LFGCoreTests Simulator scheme: 1,059 passed and 1 skipped.

## Residual risks

Self-verification and independent auditing used the network-free DEBUG fixture on iOS 26.3. Physical-device and older-iOS behavior have not been exercised. No release, commit, push, or host restart occurred.

## Bugs

None yet.
