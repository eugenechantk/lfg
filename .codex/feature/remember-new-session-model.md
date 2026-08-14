# Feature: Remember New-Session Model

## User Story

As an lfg iOS user, I want the create-session view to remember the model I last selected so that repeated sessions do not reset to Claude Opus 5.

## User Flow

1. Open the create-session view.
2. Select a model (and its associated agent runtime).
3. Keep it with Done or swipe dismissal, or discard it with Cancel.
4. Dismiss or complete the create-session flow.
5. Open the create-session view again, including after relaunching the app.
6. See the last kept agent and model already selected.

## Success Criteria

- [x] SC1: Keeping a model with Done or swipe dismissal persists both its agent runtime and model identifier across create-view presentations and app launches. **Verify by:** focused selection tests plus Simulator interaction recording.
- [x] SC2: Cancelling the model picker does not replace the last remembered selection. **Verify by:** Simulator select/cancel/close/reopen recording.
- [x] SC3: With no stored selection, the view uses the existing Claude default; an unknown agent also uses that global default, while a removed model for a known agent uses that agent's current default. **Verify by:** focused missing/stale selection tests plus fresh-Simulator first-open evidence.

## Test Strategy

Keep preference storage with the existing `AppSettings` `UserDefaults` shell. Extract agent/model validation into the platform-neutral `AgentModelSelection` value in `LFGCore`, and keep the SwiftUI view responsible only for owning draft state and committing the final value when the model sheet closes.

## Tests

### Package Unit

- `ios/LFGCore/Tests/LFGCoreTests/ModelsTests.swift`
  - restores a valid agent/model pair — SC1
  - falls back when values are missing — SC3
  - falls back safely when the stored agent or model is stale — SC3

### Runtime

- Confirm a non-default model, close/reopen the create view, and relaunch the app — SC1.
- Select a different model and cancel, then close/reopen — SC2.
- Select a different model and swipe-dismiss the picker, then close/reopen — SC1.

## Implementation Details

- Persist the pair when the model sheet closes. Done and swipe dismissal keep the live choice; Cancel first restores the opening snapshot.
- Validate the restored pair against `AgentKind.models` to avoid reviving removed or mismatched model identifiers.
- Preserve the existing Claude default for first launch or an unknown stored agent; preserve a known runtime when only its stored model has gone stale.
- Store through `AppSettings`, alongside the app's existing persisted create-flow preferences.

## Decision Log

- Persist when a kept picker closes rather than only on session creation, so the choice survives dismissing the overall create view while picker cancellation still means cancellation.
- Persist agent and model together because model names can overlap between runtimes and the model picker changes both values atomically.

## Residual Risks

An app reinstall intentionally clears `UserDefaults`, including this preference.

## Verification Evidence

| Criterion | Verification | Observed result | Evidence |
| --- | --- | --- | --- |
| SC1 | Select `gpt-5.6-terra`, tap Done, close/reopen; select `gpt-5.6-luna`, swipe-dismiss, close/reopen; terminate/relaunch app | Terra restored after Done; Luna restored after swipe dismissal and after relaunch | `.codex/evidence/20260814-114220-ios-visual-audit/00-persistence-flow.mov`, screenshots/trees `03`, `04`, `06`, `07`, `08` |
| SC2 | Select `claude-fable-5`, tap Cancel, close/reopen | Remembered chip remained `gpt-5.6-terra` | `.codex/evidence/20260814-114220-ios-visual-audit/05-cancel-reopen-still-terra.jpg` |
| SC3 | Fresh isolated Simulator first open; `swift test --filter ModelsTests/testAgentModelSelection` | First open showed `claude-opus-5`; 4 focused tests passed with 0 failures | `.codex/evidence/20260814-114220-ios-visual-audit/02-first-open-default-claude-opus-5.jpg`, audit report |
| Regression | `swift test` in `ios/LFGCore` | 302 XCTest cases and 58 Swift Testing cases passed with 0 failures | Command output in development session |
| Build | `flowdeck build --json` | Build succeeded after the final dismissal-path change | Command output in development session |
| Independent audit | iOS visual evidence auditor | **PASS** | `.codex/evidence/20260814-114220-ios-visual-audit/evidence.md` |

## Bugs

_None yet._
