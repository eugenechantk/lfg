# lfg Native iOS E2E Evidence

Date: 2026-06-18

## Environment

- App: `dev.omg.lfg`
- Project: `ios/LFG.xcodeproj`
- Scheme: `LFG`
- Simulator: `iPhone 17`, iOS 26.2, UDID `AA8AA864-E30F-4483-A83F-5340A473719F`
- Backend: local `bun run src/cli.ts serve` at `http://127.0.0.1:8766`

## Automated Checks

- `swift test` in `ios/LFGCore`: PASS, 7 tests.
- `flowdeck run --json`: PASS, app built, installed, and launched.
- `flowdeck test`: FAIL, because the generated `LFG` scheme is not configured for `test-without-building`. There is no XCTest/UI test target yet.

## FlowDeck UI E2E Walkthrough

PASS:

1. Sessions tab loads against live backend with no connection error.
2. New Session opens from Sessions.
3. New Session shows backend repo `lfg`, default backend `claude (ai sdk)`, model `opus`, and owner `Unassigned`.
4. New Session prompt accepts typed text.
5. Cancel returns to Sessions without creating a real agent session.
6. Settings shows server URL, default agent/model/repo, and security warning.
7. Agents tab loads live `/api/agents` data.
8. Agent Detail opens and shows status, Run Agent button, Reports section, and empty reports state.
9. Auto tab opens and shows empty findings/auto-agent state.

Not run:

- Pressing `Start` in New Session and `Run agent` in Agent Detail. Those actions can spawn real local agents and consume local credentials/API quota.

## Screenshots

- `01-sessions.jpg`
- `02-new-session.jpg`
- `03-new-session-typed.jpg`
- `04-settings.jpg`
- `05-agents.jpg`
- `06-agent-detail.jpg`
- `07-auto.jpg`
