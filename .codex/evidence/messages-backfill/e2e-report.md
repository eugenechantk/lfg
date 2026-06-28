# lfg Native iOS Transcript Backfill Evidence

Date: 2026-06-18

## Environment

- App: `dev.omg.lfg`
- Project: `ios/LFG.xcodeproj`
- Scheme: `LFG`
- Simulator: `iPhone 17`, iOS 26.2, UDID `AA8AA864-E30F-4483-A83F-5340A473719F`
- Backend: local mock API at `http://127.0.0.1:8766`

## Automated Checks

- `swift test` in `ios/LFGCore`: PASS, 7 tests.
- `flowdeck build`: PASS.
- `flowdeck run --json`: PASS, app built, installed, and launched.

## FlowDeck UI E2E Walkthrough

PASS:

1. Sessions list loaded a mocked live coding-agent session.
2. Session row showed the latest coding-agent tool result, `7 tests passed`.
3. Opening the session backfilled transcript history from `/api/sessions/:id/messages`.
4. Session detail rendered the user prompt, assistant summary, tool-use message, and tool-result message.
5. Live SSE stream remained connected after the transcript backfill.

Not run:

- A real agent was not spawned. The mock backend was used to avoid consuming local credentials or API quota.

## Screenshots

- `01-mock-session-list.jpg`
- `02-session-detail-messages.jpg`
- `03-session-detail-readable-messages.jpg`
