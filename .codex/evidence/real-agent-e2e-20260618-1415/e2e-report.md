# lfg Native iOS Real-Agent E2E Evidence

Date: 2026-06-18

## Environment

- App: `dev.omg.lfg`
- Project: `ios/LFG.xcodeproj`
- Scheme: `LFG`
- Simulator: `iPhone 17`, iOS 26.2, UDID `AA8AA864-E30F-4483-A83F-5340A473719F`
- Server: local `bun run src/cli.ts serve` at `http://127.0.0.1:8766`
- Agent: real managed `aisdk` session, model `haiku`
- Session ID: `f485b2e1-8868-445b-a1a1-c667ea67a5e4`

## Automated Checks

- `swift test` in `ios/LFGCore`: PASS, 7 tests.
- `flowdeck run --json`: PASS, app built, installed, and launched.

## Real-Agent Flow

PASS:

1. Started the lfg server against this checkout.
2. Spawned a real managed `aisdk`/`haiku` agent session through `/api/sessions/new`.
3. Launched the native iOS app and confirmed the real session appeared in the Sessions list.
4. Opened the native session detail and confirmed real agent transcript messages rendered.
5. Sent `Reply exactly: LFG_E2E_FOLLOWUP_OK` from the native composer.
6. Confirmed the server transcript received the user message and assistant reply.
7. Found that the assistant follow-up did not appear in the native detail until refresh/backfill.
8. Added a short post-send transcript backfill loop in the native app.
9. Rebuilt and relaunched the native app.
10. Sent `Reply exactly: LFG_E2E_FOLLOWUP_2_OK` from the native composer.
11. Confirmed `LFG_E2E_FOLLOWUP_2_OK` appeared automatically in the native detail transcript without a manual refresh.

## Screenshots

- `01-real-agent-session-list.jpg` - real agent appears in the Sessions list.
- `03-real-agent-list-fresh.jpg` - real agent detail shows transcript markers.
- `09-list-after-refresh.jpg` - manual refresh backfilled first follow-up reply into the list preview.
- `13-after-fix-relaunch.jpg` - rebuilt app cold-start backfill shows first follow-up reply.
- `15-after-fix-followup-2-visible.jpg` - fixed app shows second assistant reply in the detail transcript automatically.

## Notes

- Homebrew `tmux` was installed because lfg cannot spawn managed sessions without `tmux`.
- The real agent briefly ran its own `flowdeck run` command while responding to the smoke-test prompt. No repo files were modified by the agent.
