# Shared conversation heading

Product tier. Chats must use the Session conversation heading, including its navigation setup and docked file-pane version.

## Success criteria

- [x] Both screens use one navigation header implementation with the same title, status, controls, background and transition setup. Verify by native iPhone comparison and build.
- [x] Tapping a chat title reveals its complete selectable title, like Sessions. More still opens chat settings. Verify by native recording.
- [x] The iPad file-pane header uses one shared component, including spacing, sidebar action and More glyph. No duplicate headers; closing the pane restores the normal header. Verify by native iPad recording.
- [x] Existing Session title disclosure and options continue to work. Chat queues, settings and resource access remain intact. Verify focused Core tests and native interaction.

## Refactor guard

Low-risk extraction of existing Session UI. Keep the Session implementation as the reference. Status resolution already has deterministic package tests. Native geometry, title disclosure and toolbar transitions need recorded verification; do not add tests that inspect source or repeat layout constants.

## Scope

ConversationChrome.swift, SessionDetailView.swift and the iOS branches of ChatSessionsView.swift. Preserve all existing dirty work. No commit, deployment or build release requested.

## Decision log

Chat's principal title already used SessionTitleBarContent, but navigation configuration and its tap action differed. Its file-pane header duplicated the Session header and omitted horizontal padding. Share those surrounding components as well. Awaiting optional device clarification; proceed with the iPhone/iPad native headers based on the current app flow.

## Verification evidence

- Build PASS: `.codex/feature/shared-conversation-heading-build.jsonl`.
- All 37 focused Core tests in four suites passed before and after extraction. Logs: `shared-conversation-heading-before-tests.txt` and `shared-conversation-heading-after-tests.txt`.
- Independent native audit: PASS. Report: `.codex/evidence/shared-conversation-heading/evidence.md`. Equal-width iPad docked controls, title and status geometry match exactly. Transcript and composer remain usable, and closing the pane preserves the draft.
- Source hashes saved under `shared-conversation-heading/source-hashes.json`.

Phone evidence confirms matched native header placement, title disclosure and selection, correct More routing, and queued/working status. Independent iPad comparison also passed.

Independent phone comparison: PASS. Back and More frames match exactly. Status baseline and height match. Both title cards measure x0/y116/w402/h74. Chat title selection and More routing work. An AX capture session became stale during a status probe; reboot and relaunch recovered the owned simulator. No product defect was found.

Final state: owned fixture servers, UI sessions, apps and recordings stopped. Original FlowDeck configuration preserved. No commit or deployment.

## Release

Committed and pushed in `7dccd94` and `76e525d`. Both host servers are updated. TestFlight 1.4.1 (202611041803) passed canonical verification and is available to internal testers. See `.codex/releases/202611041803.md`.
