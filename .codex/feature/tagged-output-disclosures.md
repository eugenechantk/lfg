# Tagged output disclosures

## User story and flow

Assistant outputs wrapped in standalone XML-style tags appear as collapsed tool disclosures. The header is the tag name. Expanding reveals only the enclosed text. Surrounding prose stays in order.

## Success criteria

- [x] Complete standalone tags render collapsed; expansion shows the exact enclosed content. Verify with parser tests and simulator interaction.
- [x] Multiple blocks, surrounding prose, nested content and Unicode remain intact. Verify with parser tests.
- [x] Code examples, inline mentions, incomplete tags and user messages stay unchanged. Verify with tests and UI integration review.
- [x] Raw messages and scheduler outcome parsing remain unchanged. Verify with host outcome tests.

## Decision log

Use a client display projection, leaving stored transcripts and scheduler input untouched. Reuse the existing tool disclosure view. Existing semantic memory-citation rows retain their current rendering.

## Verification evidence

- `swift test --package-path ios/LFGCore --filter TaggedOutputTests`: 7 tests pass. Covers exact bodies, nested tags, Unicode, empty tags, code examples, comments, incomplete tags and Windows line endings.
- `swift test --package-path ios/LFGCore`: 510 tests pass, including all seven parser tests.
- `bun test src/scheduled-task-outcome.test.ts src/scheduled-task-runtime-outcome.test.ts`: 13 tests, 101 assertions pass. No host/parser mutations.
- Final FlowDeck build/run succeeded on the dedicated iPhone 17 Pro simulator.
- Independent visual audit: PASS. Both tags default collapsed; expansion exposes exact content without wrapper tags; collapse hides it again. Surrounding prose, fenced examples and user text pass.
- Visual report, clean state captures and interaction recording: `.codex/evidence/20261021-155130-ios-visual-audit/evidence.md`.

## Residual risks

Verified on iPhone 17 Pro Simulator. No physical-device or release validation requested or performed.

Evidence logs: `.codex/feature/tagged-output-{tests,core-tests,outcome-tests}.txt`.
