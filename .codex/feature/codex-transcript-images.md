# Feature: Codex Transcript Images

## User Story

As an LFG client user, I want images shown by Codex to appear in the session transcript so I can inspect the same visual output from LFG that I see in Codex.

## User Flow

1. Codex emits one or more image blocks from a tool result.
2. LFG normalizes the rollout without embedding base64 data in its message API.
3. The session transcript shows each image as a tappable image attachment.
4. Opening the attachment loads the original bytes from the connected LFG host.

## Success Criteria

- [x] SC1: A Codex `input_image` data URL becomes an assistant text message containing a stable markdown image reference. — **Verify by:** `sessions-codex-transcript.test.ts` single-image normalization test.
- [x] SC2: Image output remains visible even when the originating tool's textual output is intentionally hidden, while hidden envelope text stays hidden. — **Verify by:** `sessions-codex-transcript.test.ts` hidden `view_image` output test.
- [x] SC3: Multiple images preserve source order, persist distinct bytes, and do not put base64 data in normalized messages. — **Verify by:** `sessions-codex-transcript.test.ts` multi-image normalization test.
- [x] SC4: The reported session exposes five image references through `/api/sessions/:id/messages`, and every referenced image is fetchable through `/api/file` with an image content type. — **Verify by:** runtime API probe against session `01a013e0-5356-7db0-ba2d-14f63086ba31`.
- [x] SC5: Existing Codex transcript normalization remains green. — **Verify by:** full Bun test suite.

## Test Strategy

- Unit-test the Codex output parser and persistence boundary using tiny deterministic byte fixtures.
- Exercise hidden-output and ordinary tool-output paths.
- Probe the actual rollout through the running API to cover parsing, file persistence, and file serving together.
- Use the existing `MediaScanner` contract for client rendering; no new SwiftUI state or component is required.

## Tests

- `src/sessions-codex-transcript.test.ts`
  - normalizes hidden `view_image` image output to a served markdown reference — SC1, SC2
  - preserves multiple image blocks without leaking base64 into messages — SC3
- Existing Bun suite — SC5
- Runtime API probe for `codexy-155743-60737` — SC4

## Implementation Details

- Persist decoded Codex image blocks under the existing `lfg-uploads` temp root.
- Derive stable storage paths from content hashes so repeated transcript scans are idempotent and identical images are deduplicated.
- Keep textual output disposition unchanged; image attachments are independently visible.

## Decision Log

- Reuse markdown media references and `/api/file` rather than adding base64 fields to `SessionMessage`; this keeps transcript refreshes small and uses the client's established attachment UI.
- Limit scope to transcript normalization because the Swift client already scans and renders markdown image references.

## Verification Evidence

- `bun test src/sessions-codex-transcript.test.ts`: 14 passed, 0 failed; covers hidden output, persisted bytes, multiple-image order, unique IDs, and no base64 leakage.
- `bun test`: 651 passed, 0 failed across 57 files.
- `bunx tsc --noEmit`: passed.
- `swift test` in `ios/LFGCore`: 354 XCTest cases plus 84 Swift Testing cases passed, including `Uploaded attachments render as cards` and `Transcript resource index`.
- Real-session API probe: 44 Codex image references found overall; the final output has five references with five unique normalized IDs.
- Real-file probe: each of the final five `/api/file` requests returned `200 image/png` with non-zero bytes.
- Simulator transcript: the final Codex output renders as five separate compact `image.png` buttons — `.flowdeck/automation/sessions/98CC8660/screens/1787076289513.jpg`.
- Simulator Files & Links: the sheet lists the same five distinct image paths as file rows — `.flowdeck/automation/sessions/98CC8660/screens/1787076265814.jpg`.
- `flowdeck run -S 6534719E-2761-46B7-BF55-75C7439FDD45 --json`: build, install, and launch succeeded.
- Independent iOS visual audit: **PASS**. It independently reproduced five compact transcript buttons, five distinct Files & Links rows, a successfully opened image viewer, and five `200 image/png` file probes. Report: `.codex/evidence/20260819-020924-ios-visual-audit/evidence.md`.

## Residual Risks

_None identified. Codex-generated image files use the existing temporary attachment lifecycle; a later transcript scan recreates a missing temp file from the durable rollout data._

## Bugs

- [Resolved] B1: Multiple image messages from one Codex output initially shared the same truncated normalized ID, so SwiftUI collapsed the batch to one button. Each image ID now carries its source index; API and Simulator both show all five.
