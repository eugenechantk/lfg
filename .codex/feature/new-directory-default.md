# New directory defaults

## User story

New sessions and tasks use Claude Default without a choice or directory history. Directory history supplies previous agent/model choices. Explicit choices stay selected.

## Success criteria

- [x] Fresh and empty directories choose Claude Default despite remembered Codex choices. Verify core tests and simulator.
- [x] Existing directory history still supplies its agent/model. Verify core tests.
- [x] New task and new session share this policy; explicit choices remain selected. Verify simulator recording and independent audit.

## Decisions

Keep exact-directory matching and the existing explicit-choice guard. Missing model metadata uses the known agent with CLI Default. Change the standalone scheduled-task composer from pinned Opus to Default. This is client-only and needs no host restart.

## Verification evidence

- Core suite: 649 XCTest cases, one skipped, zero failures; 502 Swift Testing tests passed. `new-directory-default/core-tests.txt`.
- Additional focused regressions: 15 XCTest cases and five Swift Testing tests passed. Includes all combinations of remembered agent and named/Default model for fresh or empty directories. `new-directory-default/focused-tests.txt`.
- iOS simulator build passed. `new-directory-default/ios-build.json`.
- Isolated desktop build passed, and all 259 desktop feature checks passed. `new-directory-default/desktop-tests.txt`.
- Independent visual audit PASS: remembered Codex choices do not affect fresh directories; historical Codex directory selects GPT-6.1 Sol; explicit Claude Opus survives directory and purpose changes. Both fresh creation requests recorded `agent: "claude", model: ""` for sessions and tasks. Report: `.codex/evidence/new-directory-default-visual/evidence.md`.
- No host restart needed. The client changes are built and verified, but not installed into user applications or released to TestFlight. No commit or push.
