# Feature: Codex Memory Citation Rendering

## User Story

As an LFG iOS user, I can read Codex answers that cite saved memory without seeing the raw `<oai-mem-citation>` transport block or rollout UUIDs in the transcript.

## User Flow

1. Codex finishes an assistant response containing prose followed by an `<oai-mem-citation>` block.
2. The prose renders as the normal assistant response.
3. A compact `Memory sources` row appears immediately after it.
4. Tapping the row reveals each citation note and its source file/line range.

## Success Criteria

- [x] SC1: A valid Codex memory-citation block is removed from assistant prose and emitted as a distinct transcript message.
- [x] SC2: Assistant prose before and after a citation block is preserved in source order.
- [x] SC3: The compact row shows the citation count without exposing XML-like tags or rollout UUIDs.
- [x] SC4: Expanding the row shows every citation note and source file/line range.
- [x] SC5: Malformed or incomplete blocks are left untouched so transcript content is never silently discarded.
- [x] SC6: Ordinary assistant responses and existing system notices remain unchanged.
- [x] SC7: Simulator evidence confirms the collapsed and expanded iOS states.

## Test Strategy

- Bun normalization tests cover the exact supplied block, source ordering, block-only responses, malformed blocks, and unrelated markup.
- Swift Testing covers presentation parsing, count labels, citation details, and fallback behavior.
- A network-free debug fixture proves the real transcript component in Simulator without modifying a live session.

## Implementation Notes

- Normalize at the host boundary because the raw block is provider transport metadata, not Markdown.
- Emit a readable plain-text payload under the new `memory_citation` message kind so unsupported clients still have a useful fallback.
- Keep rollout IDs in the canonical transcript only; present their count in the normalized payload.

## Verification

- `bun test src/sessions-memory-citation.test.ts src/sessions-local-command-output.test.ts`: 12 passed, 0 failed.
- `bun test src/sessions*.test.ts`: 129 passed; four live-filesystem cases exceeded Bun's 5-second default. Their isolated rerun with `--timeout 20000` passed 7/7.
- `bunx tsc --noEmit`: passed.
- `flowdeck test -s LFGCoreTests ...`: 766 total, 765 passed, 1 skipped, 0 failed.
- Simulator recording and screenshots: `.codex/evidence/ios-memory-citation-2026-09-23/`.
- Independent visual audit: PASS, with evidence under `.codex/evidence/ios-memory-citation-independent-audit/`.
