# Feature: System transcript notices

## User Story

As Eugene reading an LFG transcript, I want local slash commands and their
status output to look like system activity, so they are never mistaken for
messages I sent to the agent.

## Observed Example

Claude session `lfg-52b00a` records a model switch as two ordinary user rows:

```xml
<command-name>/model</command-name>
<command-message>model</command-message>
<command-args>opus</command-args>

<local-command-stdout>Set model to `Opus 5.5` and saved as your default for new sessions</local-command-stdout>
```

Before this change, the normalized API reported both as `user/text`, so iOS
rendered them as blue user bubbles. Codex local-command output was already
separated from real user prose, but still used the tool-result card instead of
thinking-style chrome.

## User Flow

1. Run a local command such as `/model opus` in Claude Code or Codex.
2. Open the same session in LFG.
3. See the command and its output as compact, full-width system notices.
4. Continue to see genuine prompts as trailing user bubbles.

## Success Criteria

- [x] SC1: Claude `<command-name>` rows normalize to a system notice containing
  the command plus its arguments.
- [x] SC2: Claude and Codex `<local-command-stdout>` rows normalize to system
  notices without exposing the XML wrapper.
- [x] SC3: Mixed Codex rows preserve source order and keep ordinary prose as
  genuine user text.
- [x] SC4: System notices do not count as user bubbles for transcript spacing,
  newest-user tracking, or user-turn history.
- [x] SC5: iOS renders a system notice with the compact full-width visual
  language of the thinking row, not the user bubble or tool-result card.
- [x] SC6: Existing transcript normalization remains green.

## Test Strategy

- TypeScript unit tests cover Claude and Codex wrapper parsing, malformed input,
  source ordering, stable IDs, and exclusion from human-turn readers.
- Swift package tests cover the notice presentation text.
- Simulator validation uses a network-free debug fixture containing user text,
  a local command, and model-change output.

## Tests

- `src/sessions-local-command-output.test.ts`
  - Claude command and stdout rows become system notices.
  - Codex standalone and mixed wrapper rows become system notices.
  - Ordinary and malformed wrapper-like prose remains user text.
  - Human-turn readers ignore notices.
- `ios/LFGCore/Tests/LFGCoreTests/SystemNoticePresentationTests.swift`
  - Notice text is trimmed and has a stable fallback.

## Implementation Details

Use a dedicated `system_notice` transcript kind. The role remains `system`.
This avoids reclassifying unrelated system tool results and gives clients an
explicit presentation contract.

## Residual Risks

The debug fixture proves the presentation in Simulator. The running host has
not been restarted, so its live REST API still uses the pre-change normalizer
until the next intentional server deploy.

## Verification Evidence

- Exact live transcript probe: the two rows from `lfg-52b00a` normalize as
  `system/system_notice`, with visible text `/model opus` and the Opus 5.5
  confirmation.
- TypeScript: 67 tests passed across local-command normalization, Codex
  transcript parity, recent user turns, and session search. `tsc --noEmit`
  passed.
- Swift: the full `LFGCore` suite passed, including 177 Swift Testing cases.
- Simulator: FlowDeck built and launched the fixture on the session-isolated
  iPhone 17 Pro simulator. The accessibility tree exposes both notices as
  static text with the `localCommandOutputNotice` identifier, between two
  ordinary user bubbles.
- Build warnings: 29 existing warnings, 0 new warnings.
- Durable screenshot and report:
  `.codex/evidence/20260923-system-transcript-notices/`.
- Independent audit limitation: the `ios_visual_evidence_auditor` could not
  start because its fixed `gpt-5.4` runtime is unsupported for this account.
  The recorded result is therefore self-verification, not an independent PASS.

## Bugs

_None yet._
