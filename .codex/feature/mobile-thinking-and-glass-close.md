# Mobile thinking rows and glass close buttons

## User story

Remove thinking blocks from mobile transcripts. Use native Liquid Glass close buttons in the More Actions sheet and its Files and Subagents sheets.

## Success criteria

- [x] SC1: Main and child transcripts omit every thinking row, including empty and populated rows, without leaving blank row gaps.
- [x] SC2: Normal messages, tool calls, and tool results still render and pair correctly around hidden thinking rows.
- [x] SC3: Session options, Files, and Subagents use a single upper-right, circular system glass close button on iOS 26. Each button dismisses its sheet and has a Close accessibility label.
- [x] SC4: Relevant package tests, FlowDeck build, and independent iPhone visual audit pass. Light/dark rendering and minimum 44-point close targets passed. These buttons remain in custom headers; no adaptive toolbar placement changed.

## Decisions

- Hide all messages whose kind is `thinking`, including task notifications or compaction rows mapped to that kind. Preserve transcript data and provider running state.
- Filter main transcript projection and child rows. Keep a defensive empty render branch for direct message renderers.
- Use SwiftUI's native glass button style with an SF Symbol cross. Keep the existing availability fallback on earlier OS versions.
- Preserve earlier mobile changes and unrelated dirty files. No commit or release is requested.
- Apple HIG Buttons was checked from its current structured source. It recommends system button styles, familiar symbols, press feedback, and a minimum 44-by-44-point hit region.

## Tests and evidence

- Regression tests failed before implementation for hidden thinking rows and for a legacy tool call whose result arrives after a thinking row.
- `TranscriptStepGrouperTests.swift` covers omitted empty/populated thinking rows, stable message indices, and pairing with and without provider call IDs.
- The full LFGCore package passed 428 tests in 63 Swift Testing suites. Log: `.codex/evidence/20261016-thinking-glass/core-tests.log`.
- Final FlowDeck build passed at 2026-10-16 11:46:09 UTC after the Files accessibility fix. Log: `.codex/evidence/20261016-thinking-glass/final-build-containment.log`.
- Independent Simulator audit PASS on iPhone 17 Pro / iOS 26.3. Main/child thinking rows are absent, tool results remain paired, and photo gaps remain 12 points. Each glass Close is the sole upper-right close control, measures at least 44 by 44 points, exposes its expected identifier, and dismisses. Light and dark More Actions rendering passed. Report: `.codex/evidence/20261016-194142-ios-visual-audit-thinking-glass/evidence.md`.

## Residual risks

Physical devices and real host mutations are outside this verification. The prior turn's iPad capture infrastructure failed; this change does not move adaptive toolbar controls.

## Audit fixes

- The first visual pass confirmed all three close controls and main/child thinking removal. It found the Files root identifier inherited by the close button, hiding `attachmentsClose` from automation. An accessibility container boundary on the Files root fixed it; the final binary passed exact-ID lookup and dismissal. This was a UIKit/SwiftUI-only change, so the unchanged package tests were not repeated.

## Cleanup

The audit restored light appearance and stopped its capture. The parent verified the fixture PID/command, stopped only that process, and confirmed ports 18891 and 18892 had no listeners. `git diff --check` passed. No commit, push, release, or production service change occurred.
