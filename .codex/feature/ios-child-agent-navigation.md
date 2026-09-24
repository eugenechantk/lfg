# Feature: iOS Child Agent Navigation

## User Story

As an LFG iOS user viewing a main Codex agent, I can see its child agents, open a sheet containing only those children, and inspect each child transcript without leaving the sheet. The main agent remains visibly running while any child agent is still running.

## User Flow

1. Open a main Codex session that has spawned child agents.
2. Tap the child-agent button in the session header.
3. Review the main agent's child-agent list in a sheet.
4. Tap a child agent and view its transcript within the same sheet flow.
5. Dismiss the sheet to return to the main transcript.

## Success Criteria

- [x] SC1: A child-agent button is visible for a session with one or more descendant child agents and communicates the child count.
- [x] SC2: Tapping the button opens a sheet listing only child agents belonging to the viewed parent.
- [x] SC3: Tapping a listed child opens that child's transcript within the sheet, with a way back to the list.
- [x] SC4: A parent is considered running whenever its own status is running or any descendant child is running.
- [x] SC5: Child-agent relationships and running state update from refreshed host/session data without stale cross-parent entries.
- [x] SC6: Interactive controls and sheet anchors have stable accessibility identifiers for simulator verification.

## Test Strategy

Map parent/child relationships and effective running state into deterministic presentation helpers or store state. Cover empty, direct-child, unrelated-child, nested-child, terminal, and mixed-running cases with Swift tests. Build and run the app, then verify the sheet and nested transcript flow in Simulator with representative session data.

## Tests

- `src/codex-subagents.test.ts`: direct and nested descendant discovery, unrelated-thread exclusion, failed/stopped mapping, stale-running demotion, and parent-lineage transcript authorization.
- `ios/LFGCore/Tests/LFGCoreTests/ChildAgentSessionTests.swift`: parent-running promotion from a running child, terminal-child behavior, and server-count bridging before child summaries arrive.
- Full `LFGCoreTests`: 764 tests executed, 763 passed, 1 skipped, 0 failed.
- Focused backend suite: 46 passed, 0 failed.
- Full backend suite: feature tests passed, but the live-filesystem resumable-session tests exceeded Bun's default 5-second timeout while other LFG sessions were active. Their isolated correctness rerun passed 3/3 with a 20-second timeout; the full run was stopped after that environment-sensitive failure.
- TypeScript typecheck: passed.
- Simulator: verified the Working group and `1 child agent running` row while the fixture parent supplied `busy: false`; verified `childSessionsComposerBar` -> `childSessionsSheet` -> `childSessionRow_<id>` -> `childSessionTranscript`.
- The specialized visual-auditor launch was unavailable because its fixed `gpt-5.4` model is unsupported for this ChatGPT account. An independent fallback agent completed the same FlowDeck-only audit and returned PASS for SC1-SC6 after the accessibility anchors were corrected.

## Implementation Details

- Codex rollout metadata now retains `parent_thread_id`, agent path/role, and spawn depth. Child discovery walks that lineage recursively, so a parent owns direct and nested descendants but never unrelated threads.
- Child lifecycle is read from Codex `task_started`, `task_complete`, and `turn_aborted` records. A 30-minute staleness backstop prevents an abandoned `task_started` marker from keeping a parent running forever.
- The existing `/api/sessions/:id/subagents` and child-message routes now dispatch to Codex rollout lineage for Codex parents and keep the existing Claude sidecar path unchanged.
- Session-list enrichment attaches Codex child summaries before the existing work-activity fold, which promotes the parent `busy` state and exposes `runningChildAgentCount`.
- iOS applies the same OR-only effective-running rule to both session grouping and the detail header, using the freshest of parent busy, reported child count, and polled child summaries.
- The existing iOS sheet and nested transcript UI already matched the requested interaction; this change feeds it native Codex children rather than adding a second UI.
- Sheet and rendered-transcript accessibility IDs are attached to concrete list/content surfaces, because identifiers on abstract SwiftUI `Group` containers disappear from the runtime accessibility tree.
- Runtime evidence: `.codex/evidence/ios-child-agent-2026-09-23/child-agent-list.png`, `child-agent-transcript.png`, and `child-agent-flow.mov`.
- Independent audit evidence: `.codex/evidence/ios-child-agent-independent-audit/`, ending with `10-final-transcript-anchor` and `11-final-back-to-child-list`.

## Residual Risks

- Codex does not currently expose an explicit heartbeat for a child turn. The staleness backstop intentionally changes a silent `running` child to `unknown` after 30 minutes to avoid permanently pinning the parent as running.
- The visual proof used a unique-ID local facade over a real Codex parent/child transcript so the test row would not be deduplicated against the already-configured production host. Backend tests and direct local endpoint checks cover the native lineage path itself.

## Bugs

None found in the requested flow after implementation.
