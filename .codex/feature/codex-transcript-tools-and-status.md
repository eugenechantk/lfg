# Feature: Codex Transcript Tools and Stable Status

## User Story

As an lfg iOS user watching a Codex session, I want code-change/tool activity to appear in the transcript and the session to remain Working for the full turn so that the client accurately reflects what Codex is doing.

## User Flow

1. Open a live Codex session in the iOS client.
2. Codex applies a patch and writes its structured `patch_apply_end` event.
3. The normalized transcript streams a “Code changes” `tool_use` row, which the existing transcript component renders as a collapsible block with file statuses and diffs.
4. While the Codex turn remains open, REST refreshes and SSE updates continue to agree that the session is busy.
5. When Codex writes its explicit turn completion or abort marker, the session becomes Idle.

## Success Criteria

- [x] SC1: Current Codex `patch_apply_end` records normalize to a visible “Code changes” block with stable IDs, file statuses, and patch details. — **Verify by:** Bun unit test with a real Codex 0.146 rollout-shaped fixture.
- [x] SC2: Current Codex `custom_tool_call` and `custom_tool_call_output` records remain visible as paired generic tool rows. — **Verify by:** Bun unit tests with string and structured output fixtures.
- [x] SC3: A structured running-turn verdict wins over a false Codex pane scrape in the REST session baseline, while completed/aborted turns remain idle. — **Verify by:** busy-derivation unit/structural regression tests plus the existing turn-state suite.
- [x] SC4: The normalized messages decode through `LFGCore.SessionMessage` and render through the existing iOS transcript tool-row path. — **Verify by:** LFGCore Swift tests, FlowDeck build/run, and simulator transcript inspection.
- [x] SC5: Existing server and LFGCore regression suites remain green. — **Verify by:** focused Bun suites, full `bun test`, `swift test`, and FlowDeck build.

## Test Strategy

- Add server unit fixtures copied from the current local Codex rollout vocabulary.
- Extend the shared busy-derivation guard so the REST baseline cannot bypass structured turn state for Codex.
- Reuse the existing Swift model and `ToolLineView`; no new iOS state owner or message kind is required.
- Exercise a live Codex transcript in Simulator after the server normalization is verified.

## Tests

### Server Unit

- `src/sessions-codex-transcript.test.ts`
  - current `patch_apply_end` becomes a “Code changes” block — SC1
  - current `custom_tool_call` becomes `tool_use` — SC2
  - current `custom_tool_call_output` becomes `tool_result` — SC2
  - failed/empty patch events and malformed tool records fail safely — SC1, SC2
- `src/session-state-parity.test.ts`
  - REST session enumeration uses the shared structured busy resolver — SC3
- `src/turn-state.test.ts` and `src/session-state.test.ts`
  - open, complete, and aborted Codex turns retain their existing semantics — SC3

### iOS Package

- Existing `ModelsTests` validates `tool_use` / `tool_result` decoding — SC4
- Full `LFGCore` package tests guard transcript storage/merge regressions — SC4, SC5

## Implementation Details

- Normalize structured `patch_apply_end` events into a single “Code changes” block using the existing `tool_use` client kind.
- Normalize both legacy `function_call` records and current `custom_tool_call` records into the same client-facing generic tool kinds.
- Use `call_id` as the cross-record stable identity when present.
- Make Codex REST busy derivation call the same `sessionTurnState` + `resolveBusy` path already used by the journal pump and push watcher.
- Preserve `transcriptRecent` only as a fallback when neither structured source nor pane cache has an opinion.

## Decision Log

- Keep the client schema unchanged. The server already exposes generic `tool_use` / `tool_result` kinds and the iOS view already renders them; adapting the new Codex vocabulary at normalization is the smallest durable fix.
- Prefer the structured patch event over heuristics that search the generic `exec` source for `apply_patch`; it carries authoritative file operations and diffs and remains stable if tool orchestration changes.
- Treat “running” as an open agent turn, not merely a live process. Explicit Codex completion/abort markers still resolve Idle.

## Verification Evidence

- Focused server suites: 62 passed, 0 failed (`sessions-codex-transcript`, session-state parity, turn-state, and session-state).
- Full server suite: 602 passed, 0 failed; TypeScript type-check passed.
- A current Codex 0.146 `patch_apply_end` rollout normalized to a stable `tool_use` message headed “Code changes” with the expected `A` file status.
- A live open Codex turn remained busy for 16 consecutive REST samples over 85 seconds, beyond the client freshness window, even when the pane signal was false.
- LFGCore regression verification passed: 302 XCTest cases and 58 Swift Testing cases.
- FlowDeck built, installed, and launched the app on the isolated `cc-019fff91` simulator. Simulator evidence shows the existing transcript renderer displaying a “Code changes” row while the session header remains Running: `.codex/evidence/codex-transcript-tools-and-status/code-changes-running.png`.
- Independent iOS visual audit: PASS — `.codex/evidence/20260814-173616-ios-visual-audit/evidence.md`. Its isolated Simulator evidence shows a real “Code changes” row, paired generic tool rows, and the same live Codex session still Running after 76 seconds; repeated API samples remained `busy: true`.
- Independent implementation audit: PASS — `.claude/evidence/20260814-173706-verification-audit/evidence.md`. It independently reran all focused/full server tests, TypeScript, LFGCore tests, and FlowDeck build/install/launch.
- `git diff --check` passed for the changed implementation, tests, and feature document.

## Residual Risks

- A currently running long-lived server process must be restarted or redeployed before it loads the updated normalizer and status resolver.
- A future Codex CLI may add new rollout event vocabularies; unknown records intentionally remain hidden rather than being misrepresented.
- The FlowDeck project scheme does not support `test-without-building`, so package test verification used the package test runner while FlowDeck separately verified the app build/run path.

## Bugs

- Fixed: current Codex patch events and custom tool records were silently dropped by `normalizeCodexLine`.
- Fixed: Codex REST busy state bypassed structured transcript turn state and could disagree with the live journal.
