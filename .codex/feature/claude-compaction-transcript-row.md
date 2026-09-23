# Feature: Claude compaction transcript row

## User Story

As an LFG user reading a Claude Code session, I want Claude's synthetic compacted-context payload to appear as a concise activity row so that it is not mistaken for a message I sent.

## User Flow

1. Claude Code compacts a conversation and writes a transcript-only `user` row marked `isCompactSummary: true`.
2. LFG normalizes that row as a thinking-style activity with the text `Compacting conversation`.
3. The iOS transcript displays a brain-styled, non-expandable `Compacting conversation` row.
4. User-history readers skip the synthetic row and retain the preceding genuine user prompt.

## Success Criteria

- [x] SC1: A Claude row marked `isCompactSummary: true` normalizes to exactly one `thinking` message labeled `Compacting conversation`, without exposing its summary body. — **Verify by:** Bun regression test using the observed `cy-101835-59851` transcript shape.
- [x] SC2: The compact summary is excluded from genuine-user history while neighboring real prompts remain available. — **Verify by:** Bun tests for recent/all/last user-turn readers.
- [x] SC3: An unflagged user message remains a normal user text message, including one that starts with the same continuation sentence. — **Verify by:** Bun negative regression test.
- [x] SC4: The iOS presentation renders the marker as a non-disclosure thinking-style row titled `Compacting conversation`, while normal thinking remains titled `Thinking` and expandable. — **Verify by:** Swift package tests plus Simulator screenshot and accessibility-tree inspection.

## Test Strategy

- Backend unit/integration tests cover transcript normalization and all genuine-user readers at the structured `isCompactSummary` boundary.
- LFGCore Swift tests cover the presentation mapping independently of SwiftUI rendering.
- Simulator evidence covers the final SwiftUI appearance.

## Tests

- `src/sessions-compact-summary.test.ts`
  - flagged row normalizes to a concise thinking item (SC1)
  - flagged row is excluded from genuine-user readers (SC2)
  - same prose without the flag remains user text (SC3)
- `ios/LFGCore/Tests/LFGCoreTests/ThinkingPresentationTests.swift`
  - compaction marker maps to a static visible label (SC4)
  - ordinary reasoning maps to the existing expandable presentation (SC4)

## Implementation Details

- Use Claude's `isCompactSummary` field rather than matching prose.
- Preserve the existing `thinking` protocol kind so every client receives the correct semantic classification.
- Add a narrow presentation mapping for the sentinel text; do not change ordinary thinking blocks.

## Decision Log

- Chose the structured `isCompactSummary` flag over sentence-prefix detection because the live transcript supplies it and Claude may change the prose.
- Chose a static brain-styled row for the compact marker because the summary body must not be exposed and there is no meaningful disclosure content.

## Verification Evidence

| Criterion | Command / action | Observed result | Evidence |
| --- | --- | --- | --- |
| SC1–SC3 | `bun test src/sessions*.test.ts` | 126 passed, 0 failed; the new compact-summary suite passed all three cases. | Test output from 2026-09-23 11:08 HKT. |
| SC1–SC3 | Live isolated server against the observed Claude transcript shape and a three-row fixture | The flagged row was exactly `{ role: "user", kind: "thinking", text: "Compacting conversation" }`; `lastUserText` retained the genuine prompt. | `.codex/evidence/2026-09-23T11-10-44+0800-ios-visual-audit/api-fixture.json` |
| SC4 | `swift test` in `ios/LFGCore` | 580 XCTest cases passed with one optional skip; 174 Swift Testing cases passed, including both thinking-presentation tests. | Test output from 2026-09-23 11:08 HKT. |
| SC4 | `flowdeck build -S 84FF5190-D51E-4600-9EF7-D27D4FDF6D9F --json` | Debug build succeeded for the isolated iPhone 17 Pro simulator. | FlowDeck result at 2026-09-23 10:58 HKT. |
| SC4 | Independent fallback visual audit | PASS with no deltas: exact label and brain styling, no blue bubble, disclosure control, detail body, or private-summary leakage; adjacent messages normal. | `.codex/evidence/2026-09-23T11-10-44+0800-ios-visual-audit/REPORT.md` and `simulator.png` |

Additional check: `bunx tsc --noEmit` passed.

## Residual Risks

- The production `8766` server was deliberately not restarted from the shared dirty worktree, because unrelated in-progress server edits and active sessions are present. The source change takes effect on its next safe restart; the real parsing and UI seams were verified on isolated port `8767` without touching production state.
- The dedicated `ios_visual_evidence_auditor` role could not start because its fixed model is unsupported for this account. A separate fallback agent performed the same independent runtime/API/accessibility audit and returned PASS.

## Bugs

_None yet._
