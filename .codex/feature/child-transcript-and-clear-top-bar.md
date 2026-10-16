# Child transcript parity and clear session header

## User story

Child-agent transcripts should use the main session's grouped tool summaries and nested expand/collapse controls. The main transcript should visibly scroll beneath a transparent header with a smooth fade and no full-width blur.

## Success criteria

- [x] SC1: Main and child transcripts use the same item projection, ToolStepGroupView, and ToolCallCard. Consecutive child calls form one summary; single calls retain the same direct disclosure behavior.
- [x] SC2: Child group and call disclosures expand/collapse, preserve paired results and error styling, and open the same full-output sheet. Thinking remains hidden; normal messages retain order.
- [x] SC3: Transcript rows move beneath the main session navigation bar. The full-width navigation background is hidden and the transition uses only a translucent color gradient, with no material or blur layer.
- [x] SC4: Main toolbar actions, bottom composer, and transcript scrolling still work in light/dark appearance. Verified iPhone 17 Pro light/dark and iPad adaptive navigation.
- [x] SC5: Relevant package tests, final FlowDeck build, and independent visual audit pass. Complete disclosure and scrolling interactions were recorded.

## Decisions

- Extract the existing identified transcript-item projection without changing the tested grouping algorithm. Both views consume it and the existing tool components.
- Keep child fetching/polling unchanged. Own the child full-output sheet on its stable transcript view.
- Preserve native toolbar controls. Hide the bar's full-width background and replace the opaque session scrim with a non-blurring, translucent gradient.
- Keep the existing main transcript inversion, render window, keyboard handling, bottom chrome, and shared list fade unchanged.
- No release or commit is requested. Preserve unrelated dirty files.

## Test strategy

The existing TranscriptStepGrouper suite covers consecutive calls, paired/late/legacy results, edits, errors, and hidden thinking. Run the full LFGCore package after extracting the shared projection. UIKit layout and gestures require recorded Simulator proof. The independent auditor must compare main and child tool behavior, and observe real transcript rows entering and moving through the header area.

## Residual risks

Physical devices, operating systems before version 26, and production-host actions are outside this verification. Recorded responsiveness is a functional observation, not frame-time or hitch profiling.

## Verification evidence

- Before extraction, all 17 TranscriptStepGrouper tests passed. The grouping algorithm was left unchanged.
- After implementation, the full LFGCore package passed 428 tests in 63 Swift Testing suites. Log: `.codex/evidence/20261016-child-clear-header/core-tests.log`.
- The initial FlowDeck build passed at 11:50:57 UTC. A final build also includes a stable `toolOutputDone` identifier for the new child full-output path.
- The isolated fixture presents the same multi-call and single-call sequences in main and child transcripts. It also supplies 24 marked paragraphs for actual header-underlap scrolling evidence.
- Independent audit PASS on iPhone 17 Pro / iOS 26.3 and iPad Pro 11-inch M5 / iPadOS 26.3. Report: `.codex/evidence/20261016-195256-ios-visual-audit-child-clear-header/evidence.md`.
- Real marked paragraphs moved through the main navigation title area in light, dark, and the iPad split layout, with no visible full-width blur or opaque stop. Child groups, nested calls, error output, full output, and single-call disclosures passed, including exact-ID taps on the final build. Composer typing and native Back also passed.
- The same audit closed the earlier settings/content iPad gate: App Settings close, Session title/sole glass close, Host menu opening without transfer requests, and wide-code panning all passed.

## Audit fixes

- The first visual pass confirmed crisp main-header underlap and matching child group/call expansion, paired output, full-output presentation, error styling, single-call expansion, and hidden thinking.
- The child screen's root accessibility identifier masked nested tool control identifiers. Moving it from the lazy stack to the scroll view did not fix the runtime tree. Removed the loaded screen override to preserve the same native hierarchy as main; loading/error/empty anchors remain. The final binary passed exact-ID taps for the group, individual Read call, full-output action, output dismissal, and single-call group.
- Apple documents that LazyVStack already supplies an accessibility container. The fix preserves native children instead of replacing the loaded screen's accessibility metadata. Source: [SwiftUI Accessibility: Beyond the basics](https://developer.apple.com/videos/play/wwdc2021/10119/).

The final accessibility build passed at 11:58:11 UTC. Log: `.codex/evidence/20261016-child-clear-header/child-native-accessibility-build.log`. Package code did not change after the 428-test run; subsequent fixes changed only the child view's accessibility modifiers.

## Cleanup

The auditor restored light appearance, stopped capture, and shut down the owned iPad. The parent verified the fixture PID/command, stopped only that process, and confirmed no listeners remained on ports 18891 or 18892. No real host, commit, release, or production service was changed.
