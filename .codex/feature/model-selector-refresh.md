# Feature: Model Selector Refresh

## User Story

As an lfg user, I want Codex and Claude model pickers to offer current model versions so new sessions do not start on stale model IDs.

## User Flow

1. Open the web or iOS new-session UI.
2. Pick Claude, Codex, Claude AI SDK, Codex AI SDK, or opencode.
3. See current model IDs with a current default selected.
4. Start, resume, or recover a session and have the backend use the same current defaults.

## Success Criteria

- [x] SC1: Codex pickers/defaults use the current GPT-5.6 family instead of GPT-5.5/GPT-5.4 defaults. — **Verify by:** source scan plus package tests.
- [x] SC2: Claude pickers/defaults include current explicit Claude model IDs and default to Claude Opus 5 where lfg previously defaulted to Opus. — **Verify by:** source scan plus Swift package tests.
- [x] SC3: Server-side validation/defaults accept the same model IDs shown in the web/iOS pickers. — **Verify by:** package tests and source scan.

## Test Strategy

- Update existing Swift `AgentKind` catalog tests.
- Add/adjust Bun tests for tmux default model argv.
- Run the relevant TypeScript and Swift test suites that exercise model defaults.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/ModelsTests.swift`
- `src/tmux-argv.test.ts`

## Implementation Details

- OpenAI docs resolver returned latest model `gpt-5.6-sol`; OpenAI code-generation docs recommend the GPT-5.6 family for Codex/coding tasks.
- Anthropic model overview lists `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5`, and `claude-haiku-4-5` as current models.
- Keep Claude aliases in backend allowlists for backward compatibility, but make pickers/defaults use explicit current IDs.
- Updated backend defaults, web picker constants, iOS `AgentKind` catalogs, paused-session recovery actions, WhatsApp agent defaults, and action-agent defaults.

## Verification Evidence

| Criterion | Command/action | Observed result |
| --- | --- | --- |
| SC1, SC3 | `rg -n "gpt-5\\.5|gpt-5\\.4|model: \"opus\"|\\?\\? \"opus\"|Resume on Opus\"|const CLAUDE_MODELS|const AISDK_MODELS|const CODEX_MODELS|DEFAULT_MODEL|claude-opus-5" src web ios/LFG ios/LFGCore .codex/feature/model-selector-refresh.md -S` | No stale GPT-5.5/GPT-5.4 Codex defaults remained; remaining `opus` strings were alias compatibility or tests for arbitrary model persistence. |
| SC2, SC3 | `bun test` | 135 tests passed, 0 failed. |
| SC2, SC3 | `bunx tsc --noEmit` | Passed with no diagnostics. |
| SC2 | `swift test` in `ios/LFGCore` | 141 tests passed, 0 failed. |
| SC2 | `flowdeck test` | Blocked by project configuration: scheme `LFG` is not configured for `test-without-building`. Package-level Swift tests passed instead. |

## Residual Risks

- Final visual layout of long model IDs in the iOS/web pickers is not simulator/browser-audited in this pass.
- opencode provider catalog availability is not verified against a live account.
- FlowDeck project-level testing is blocked until the `LFG` scheme supports test-without-building.

## Bugs

_None yet._
