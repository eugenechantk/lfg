# Reliable follow-up delivery verification

## Automated suites

- `bun test`: 617 pass, 0 fail, 1,205 expectations across 54 files.
- `swift test` from `ios/LFGCore`: 305 XCTest cases plus 58 Swift Testing cases passed.
- `flowdeck build -S C309D597-2F8D-4B3D-9AC3-8729148BC88C`: passed.
- `flowdeck run -S C309D597-2F8D-4B3D-9AC3-8729148BC88C`: app installed and launched successfully.
- `flowdeck test`: unavailable because the LFG app scheme is not configured for test-without-building; the independently runnable LFGCore package suite is the Swift test gate.

## Disposable live probes

- Scratch server on port 8877 used isolated send-queue state and disposable Codex session `019fffe5-fd61-7300-9227-8a9f5de9b628`.
- A 69,721-byte/802-line synthetic paste delivered once in 485 ms.
- The exact 41,112-byte/469-line payload from the recent production failure delivered once in 510 ms.
- During a controlled `sleep 15` tool call, follow-up `8c39d959af928dbb` entered Codex's native queue in 498 ms. The pane showed `Messages to be submitted after next tool call`; transcript order contained one primary user turn, one follow-up user turn, and one `RUNNING_ACK`.
- The scratch session and server were closed after the probe.

## Production-port smoke test

- Reloaded the supervised listener on port 8766 once: PID 16291 was replaced by PID 41935 and `/api/sessions` returned normally.
- Disposable production session: `019fffee-d581-7491-9a59-e75730a35c65`.
- Idle multiline follow-up `f6180a4039884151` delivered in one attempt in 486 ms.
- Running follow-up `74567ec76a1c5fb0` entered the native queue in one attempt in 544 ms.
- Transcript counts were exactly one idle user turn, one idle acknowledgment, one running follow-up user turn, and one running acknowledgment, in order.
- The production disposable session was closed after verification.

## Simulator evidence

- `app-launch.png`: clean launch on the isolated simulator.
- `session-list.png`: successful connection to the disposable host and live session rendering.
- `native-queued-row.png`: app-originated follow-up send rendered in the session transcript during the live exercise.
