# Feature: Model Selector Refresh

## User Story

As an lfg user, I want Codex and Claude model selectors to offer current provider models so that new sessions do not start on stale model IDs.

## User Flow

1. Open lfg on web or iOS and create a new agent session.
2. Choose Codex, Codex AI SDK, Claude, Claude AI SDK, or opencode.
3. Pick a current model from the selector.
4. Start the session and have the backend receive that same model value.

## Success Criteria

- [x] SC1: Codex selectors default to current Codex model IDs and no longer default to `gpt-5.5` -- **Verify by:** search source for stale Codex defaults and typecheck.
- [x] SC2: Claude selectors include current full Anthropic IDs while preserving Claude Code aliases -- **Verify by:** search source for stale Claude IDs and typecheck/package tests.
- [x] SC3: Backend allowlists/defaults match the web and iOS selector values -- **Verify by:** source inspection, TypeScript typecheck, and Swift package tests.
- [x] SC4: Local lfg host supports Codex CLI integration -- **Verify by:** `codex --version` and `codex app-server --help`.

## Platform & Stack

- **Platform:** Web UI + iOS shared model catalog + TypeScript CLI/server
- **Language:** TypeScript, Swift
- **Key frameworks:** Bun, React, Vite, Swift Package Manager

## Steps to Verify

1. Confirm local `codex` and `claude` binaries exist.
2. Update selector constants and backend defaults.
3. Run repository typecheck/tests proportional to the change.
4. Run LFGCore Swift package tests.
5. Search for old model IDs.

## Implementation Phases

### Phase 1: Selector and Default Refresh

- Scope: Update Codex, Claude, Claude AI SDK, opencode selector lists and default launch models across web/server/iOS shared catalog.
- Success criteria covered: SC1, SC2, SC3, SC4
- Verification gate: local CLI probes, stale-ID search, typecheck/tests.

## Decision Log

- Use OpenAI Codex docs as the source for Codex selector IDs: `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, and `gpt-5.3-codex-spark`.
- Use explicit Claude IDs (`claude-opus-5`, `claude-fable-5`, `claude-sonnet-5`, `claude-haiku-4-5`) in selectors/defaults, while preserving Claude Code aliases (`opus`, `fable`, `sonnet`, `haiku`) for compatibility with existing clients and transcript-derived resume.
- Update opencode Anthropic model IDs to `claude-fable-5`, `claude-opus-5`, `claude-sonnet-5`, and `claude-haiku-4-5`, preserving provider prefixes.

## Verification Evidence

| Criterion | Command / action | Observed result |
| --- | --- | --- |
| SC1-SC3 | `rg -n "gpt-5\.5\|gpt-5\.4\|gpt-5\.3-codex$\|claude-sonnet-4-6\|claude-opus-4-8\|claude-opus-4-6\|claude-3-5" -g "!node_modules/**" -g "!web/node_modules/**" -g "!web/dist/**" -g "!bun.lock" -g "!web/bun.lock" -g "!improvement-log/**" .` | No executable stale defaults remained; the only match was a negative Swift assertion proving `anthropic/claude-sonnet-4-6` is absent. |
| SC1-SC3 | `bunx tsc --noEmit` | Passed. |
| SC1-SC3 | `cd web && bun run build` | Passed: `tsc --noEmit && vite build`; Vite emitted only the existing chunk-size warning. |
| SC1-SC3 | `bun test` | Passed: 135 tests, 0 failed. |
| SC2-SC3 | `cd ios/LFGCore && swift test` | Passed: 141 tests, 0 failed. |
| SC4 | `command -v codex; codex --version` | `/opt/homebrew/bin/codex`; `codex-cli 0.145.0`. |
| SC4 | `codex app-server --help` | App server command is available and supports `--listen stdio://`. |

## Bugs

_None yet._
