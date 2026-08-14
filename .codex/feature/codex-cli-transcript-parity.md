# Feature: Codex CLI Transcript Parity

## User Story

As an lfg user following a Codex session from iOS, I want every meaningful block shown by the Codex CLI to appear in the lfg transcript with the same semantic label, order, status, and content so that the mobile view is a faithful remote representation of the session.

## User Flow

1. Open a live or completed Codex session in lfg.
2. Codex reasons, searches, reads files, runs commands, calls MCP tools, applies patches, reports plans/progress, and responds.
3. lfg renders each CLI-visible block in transcript order using native iOS components.
4. Operational rollout bookkeeping that Codex itself does not show remains hidden.
5. Incomplete and failed blocks remain visible with an accurate state instead of disappearing.

## Success Criteria

- [x] SC1: Every current Codex rollout record category is inventoried and classified as CLI-visible or bookkeeping, with a captured rationale and representative fixture. — **Verify by:** a corpus audit over current local Codex rollouts plus comparison against a live Codex pane.
- [x] SC2: Every CLI-visible command, patch, MCP, web/search, reasoning/progress, plan, user, and assistant block normalizes into an ordered lfg transcript message with the CLI's semantic label and meaningful content. — **Verify by:** table-driven Bun normalization tests covering each observed visible category.
- [x] SC3: Completed, failed, and in-progress activities retain accurate state and do not create duplicate raw wrapper/result blocks when rollout records describe the same CLI activity at multiple lifecycle stages. — **Verify by:** Bun sequence tests over call/output/end records.
- [x] SC4: Bookkeeping-only records remain hidden and malformed/unknown records fail safely. — **Verify by:** table-driven negative normalization tests over the observed hidden vocabulary.
- [x] SC5: All normalized block kinds decode and render through the existing iOS transcript path with accessible labels and disclosure behavior. — **Verify by:** LFGCore tests, FlowDeck build/run, and Simulator inspection of a representative parity session.
- [x] SC6: Existing server and iOS behavior remains green. — **Verify by:** focused Bun tests, full `bun test`, TypeScript type-check, `swift test`, FlowDeck build/run, and independent iOS visual audit.

## Test Strategy

- Derive fixtures from current local Codex rollouts rather than guessing the protocol.
- Compare raw rollout sequences with the live Codex TUI pane to distinguish visible blocks from internal lifecycle events.
- Test normalization at both record and multi-record sequence level so lifecycle deduplication is explicit.
- Reuse the existing iOS message model and transcript components where their semantics are sufficient; add schema/UI only when a distinct CLI-visible state cannot be represented accurately.

## Tests

- `src/sessions-codex-transcript.test.ts` is the checked-in protocol fixture suite.
- It covers CLI labels and bodies for patch success/failure, direct and Code Mode command calls, `Explored` command grouping, plans, web begin/end, image viewing/generation, MCP lifecycle collapse, context compaction, sub-agent activity, waits, interrupted turns, errors/warnings/deprecations, review markers, legacy command/image records, direct provider calls, local-shell calls, hidden bookkeeping, malformed/unknown rows, and path relativization from paged transcripts.
- `src/session-state-parity.test.ts` retains the independent status regression table from the original Codex Running/Idle fix.

## Rollout → CLI Parity Matrix

| Rollout record(s) | lfg / Codex CLI cell | Classification |
| --- | --- | --- |
| `event_msg.user_message` | user turn | Visible; response-item user copies are hidden |
| assistant `response_item.message` | assistant commentary/final answer | Visible; legacy `event_msg.agent_message` copy is hidden |
| `response_item.reasoning.summary` | Thinking | Visible when summary text exists |
| `exec_command` / `local_shell_call` + output | `Ran` or grouped `Explored`; meaningful output | Visible; Code Mode envelope is removed |
| `write_stdin` + output | `Interacted with background terminal` | Visible |
| `patch_apply_end` | `Added`, `Edited`, or `Deleted`, line counts, diff | Visible; apply-patch wrapper/output is hidden |
| Code Mode `update_plan` | `Updated Plan` with note and step states | Visible; wrapper output is hidden |
| Code Mode web call + `web_search_end` | `Searching the web`, then `Searched the web for …` | Visible |
| MCP function call + `mcp_tool_call_end` + function output | one stable `Called server.tool(args)` cell plus meaningful result | Visible; lifecycle duplicates collapse onto the call id |
| `view_image` / `image_generation_end` | `Viewed Image` / `Generated Image` | Visible |
| `context_compacted` | `Context compacted` | Visible |
| `sub_agent_activity` | `Started`, `Interacted with`, or `Interrupted` agent | Visible |
| `wait_agent` + output | `Waiting for agents`, then `Finished waiting` | Visible |
| `turn_aborted` | `Conversation interrupted …` | Visible |
| `error`, `warning`, `guardian_warning`, `deprecation_notice` | native error/warning/notice cell with the CLI message | Visible |
| `entered_review_mode` / `exited_review_mode` | `Code review started …` / `Code review finished` | Visible |
| legacy `exec_command_end` / `view_image_tool_call` | same stable `Ran`/`Explored` / `Viewed Image` activity as the corresponding call | Visible; lifecycle duplicates collapse |
| token/task/thread/world-state/tool-discovery/compaction payloads | none | CLI-hidden bookkeeping |

## Implementation Details

- `CodexNormalizationState` is scoped to one REST transcript scan or one journal watcher. It remembers the rollout cwd and call disposition, allowing relative CLI paths and suppression of wrapper outputs without cross-session state.
- Code Mode JavaScript is scanned without evaluating it. Only `tools.*` calls outside string literals are recognized; JSON arguments and the small object-literal shapes Codex emits are decoded defensively.
- Shell calls are classified as `Explored` only when every command is a read/list/search operation. Mixed or mutating commands remain `Ran`, matching the TUI's classification rule.
- Patch summaries reproduce the CLI verbs and aggregate/per-file `(+N -N)` counts, then retain the underlying diff/content inside lfg's existing collapsible tool row.
- Paged REST scans seed the rollout cwd from `session_meta`, preserving the CLI's workspace-relative paths even when the visible window begins deep in the file.
- MCP start/completion records share a stable activity id; completed REST scans collapse them to one cell and the raw function result remains hidden.
- Existing `tool_use`, `tool_result`, and `thinking` message kinds are sufficient, so no client schema migration is required.

## Decision Log

- “Exactly” means semantic parity—activity category, user-facing label, order, state, and meaningful body—not a pixel clone of terminal typography.
- Hidden rollout bookkeeping stays hidden when the Codex CLI also hides it.

## Verification Evidence

- Corpus replay: a historical MCP-heavy rollout returns 10 `node_repl.js` cells with 10 unique activity ids and zero raw `Called mcp__…` wrapper cells.
- Current scratch API: session `019fff8a-4468-7352-9e17-424c3fe327ea` remains `busy: true`, `status: ok` throughout the live turn.
- Server: full Bun suite passed (609 tests / 1,192 assertions); the focused parity suite, TypeScript check, and `git diff --check` also passed after the final protocol change.
- iOS core: 302 XCTest cases and 58 Swift Testing cases passed.
- Native app: FlowDeck built, installed, and launched LFG on the isolated iPhone 17 Pro simulator. Screenshots under `.codex/evidence/codex-cli-transcript-parity/` show `Working`, `Ran`, `Explored`, and `Edited` semantic cells.
- Independent visual audit: PASS. The final scratch build showed `Explored`, `Ran`, `Edited`, terminal interaction, agent waits, no raw Code Mode wrapper rows, and six `busy: true` samples across 77 seconds. See `.codex/evidence/20260814-180819-ios-visual-audit/evidence.md`.

## Residual Risks

- Codex may add new rollout record types in a future CLI release. Unknown records intentionally fail closed rather than exposing transport payloads; the fixture matrix should be extended when the protocol changes.
- The long-lived server on port 8766 must be restarted or redeployed before the normal app path loads this working-tree implementation.

## Bugs

_None yet._
