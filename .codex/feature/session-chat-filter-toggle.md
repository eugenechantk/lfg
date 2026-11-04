# Feature: Optional chat filter in Sessions

## User story and flow

Open Settings, then Sessions. Turn off Hide chat sessions to include durable chats in the Sessions list. Turn it on to hide them again. Save the choice on this device across launches. Existing installations keep chats hidden until the user changes it.

## Success criteria

- [x] A new preference defaults to hiding chat sessions. Verify with a fresh simulator preference and the existing Core membership tests.
- [x] Switching the preference updates the list immediately, including search results and list counts. Verify with the native fixture flow and Core membership tests.
- [x] The choice survives closing Settings and restarting the app. Verify with a recorded simulator flow.
- [x] Ordinary sessions remain visible, and task editing sessions remain hidden in both modes. Verify with Core regression tests and fixture rows.

## Implementation

Add the persisted preference to AppSettings and bind a native toggle in the existing Sessions settings section. Pass it through the shared membership rule at every iOS list entry point. Keep the source sessions available for chat navigation and notifications.

## Decision log

This request targets the Sessions section of the iOS/iPadOS settings sheet. The desktop keeps its existing default through the shared rule's default argument. No backend changes are needed. Existing grouping remains intact: Status keeps child agents inside their parent, while Directory and Host grouping can show their rows.

## Verification evidence

- The focused membership suite passed: 6 tests, including both filter modes, legacy IDs, provider directories and task editing exclusions. Log: `.codex/feature/session-chat-filter-tests.txt`.
- The full Core run passed: 652 XCTest cases (one skipped), plus 596 Swift Testing cases in 91 suites. Log: `.codex/feature/session-chat-filter-core-tests.txt`.
- FlowDeck iOS build passed at 06:55:07 UTC. Log: `.codex/feature/session-chat-filter-build.jsonl`.
- Independent native audit PASS: `.codex/evidence/session-chat-filter-toggle/evidence.md`. The recording proves default ON, immediate OFF/ON list and count updates, OFF persistence after full app restart, search in both modes, and continued Message tab access. Existing Status grouping keeps subagents inside their parent; Directory grouping verifies owned workers and their counts.
- All six source hashes still match the audited build. This follow-up has not been released to TestFlight.

## Residual risks

Native verification used isolated local fixture hosts and no production writes. The preference affects list presentation only. It does not change chat delivery or notification registration.
