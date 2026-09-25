# Feature: Task notification thinking rows

## User Story

As Eugene reading an LFG transcript, I want provider-generated
`<task-notification>` messages to look like thinking activity, so background
task lifecycle events are not mistaken for prompts I sent.

## User Flow

1. Claude Code finishes or updates a background task.
2. Claude writes a closed `<task-notification>` envelope into the transcript.
3. LFG shows that row with the existing collapsed thinking presentation.
4. Genuine user prose before or after the envelope remains a user message.

## Success Criteria

- [x] SC1: A closed `<task-notification>` envelope normalizes to
  `role: "system", kind: "thinking"` for Claude and Codex transcript shapes.
- [x] SC2: Mixed rows preserve source order and retain surrounding genuine user
  prose as `user/text` messages.
- [x] SC3: Incomplete or ordinary wrapper-like prose remains user text rather
  than being reclassified.
- [x] SC4: Task notifications are excluded from user-turn history readers.
- [x] SC5: iOS renders the normalized row through the existing collapsed,
  expandable thinking component rather than a user bubble.

## Test Strategy

- TypeScript normalization tests cover the observed Claude row, Codex parity,
  mixed content, malformed wrappers, stable IDs, and user-history exclusion.
- Existing Swift presentation tests cover the ordinary expandable thinking
  state used by the new normalized kind.
- A network-free debug fixture and Simulator audit prove the final iOS row.

## Tests

- `src/sessions-task-notification.test.ts`
  - closed Claude and Codex envelopes become system thinking messages
  - surrounding prose remains ordered user text
  - malformed wrappers remain user text
  - user-turn readers exclude task notifications
- `ios/LFGCore/Tests/LFGCoreTests/ThinkingPresentationTests.swift`
  - ordinary thinking remains collapsed and expandable

## Implementation Details

Extend the existing closed-wrapper tokenizer rather than adding a broad
angle-bracket heuristic. A complete task-notification becomes a
`system/thinking` segment and retains the original envelope as its expandable
detail; incomplete wrappers continue through the human-text path. The iOS
client already routes `kind: "thinking"` through `ThinkingView`. A stable
`thinkingDisclosure` accessibility identifier makes the collapsed/expanded
state directly verifiable in Simulator.

## Residual Risks

The Simulator audit uses a network-free fixture while TypeScript tests prove
provider normalization. The currently running long-lived host was not restarted,
so it will not use the new normalizer until its next intentional deploy/restart.

## Verification Evidence

- `bun test src/sessions*.test.ts`: 138 passed, 0 failed.
- `bunx tsc --noEmit`: passed.
- `swift test` in `ios/LFGCore`: 593 XCTest cases passed with one optional skip;
  182 Swift Testing cases passed.
- `flowdeck run` on the session-isolated iPhone 17 Pro simulator: build,
  installation, and fixture launch succeeded.
- Independent visual audit: **PASS**. The collapsed task event uses the gray
  Thinking row between normal messages; the first identifier-targeted tap
  reveals the exact envelope and the second restores a byte-identical collapsed
  accessibility tree. Report and artifacts:
  `.codex/evidence/20260924-101600-task-notification-independent-audit/`.
- `git diff --check`: passed.

## Bugs

_None yet._
