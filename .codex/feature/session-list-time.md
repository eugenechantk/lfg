# Feature: Session list time

## User story
The time beside a working session should show how long its current live session has run. Idle and closed rows should show how long it has been since conversation activity.

## Success criteria
- Working rows use `startedAt`, not the timestamp of the latest message.
- Idle, unread, closed, paused, and needs-input rows use `lastActivityAt`.
- A working row with no start time does not mislabel message age as runtime.
- The compact time updates while the list remains open, and accessibility text names the meaning of the time.

## Test strategy
- Swift package tests cover timestamp selection and missing values.
- Build and inspect a simulator list with working, idle, and closed rows.

## Implementation
`SessionListTime` selects the clock from the Working group. `SessionRow` formats that clock using the existing compact style and refreshes it each second. The accessibility label distinguishes runtime from time since activity. A DEBUG-only fixture provides stable Working, Idle, and Closed rows for simulator checks.

## Verification
`swift test --filter SessionListTimeTests`: 3 passed. `flowdeck build --json`: passed, including the fixture. The independent iPhone 17 Pro visual audit passed for Working, Idle, Unread, and Closed. It recorded the live list advancing across a minute boundary and the fixture's Working, Idle, and Closed times advancing without navigation. Report: `.codex/evidence/20260930-131251-ios-visual-audit/evidence.md`.

The real Idle rows available during the audit lacked activity timestamps, so the fixture supplied that state. A Working row with missing `startedAt` was tested in Swift but was not rendered in the simulator.
