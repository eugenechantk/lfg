# Feature: Dismiss Idle Live Activity

## User Story

As an lfg user, I want the fleet Live Activity dismissed when no session is working or waiting for input so that the Lock Screen never shows an empty widget.

## User Flow

1. One or more working or needs-input sessions keep the fleet Live Activity visible.
2. The final working session becomes idle, with no remaining prompt.
3. The server immediately sends an ActivityKit `end` event with immediate dismissal.

## Success Criteria

- [x] SC1: An existing Live Activity ends on the first observation with zero working and zero needs-input sessions. — **Verify by:** `src/push/watcher.test.ts` reducer regression test.
- [x] SC2: A needs-input session still keeps or starts the Live Activity. — **Verify by:** existing `src/push/watcher.test.ts` prompt precedence tests.
- [x] SC3: The relevant push watcher suite remains green. — **Verify by:** focused Bun test command.

## Platform & Stack

- **Platform:** Backend lifecycle for the iOS Live Activity
- **Language:** TypeScript
- **Key frameworks:** Bun test, APNs ActivityKit payloads

## Test Strategy

Pin the lifecycle in the pure `reduceFleetLiveActivity` reducer. The first empty observation from an existing activity must return `event: "end"`, `nextActive: null`, and an empty content state. Existing prompt tests protect the exception.

## Tests

- `src/push/watcher.test.ts`
  - `ends immediately on the first empty tick` — SC1
  - existing paused/prompt and prompt-over-busy cases — SC2

## Implementation Details

Remove the server-side empty-fleet debounce. Keep the ActivityKit end payload's immediate dismissal date and leave activity creation/update semantics unchanged.

## Decision Log

- Prefer the requested immediate dismissal over retaining the activity token across short gaps between turns. The previous two-minute debounce deliberately traded Lock Screen correctness for fewer push-to-start token rotations; the product behavior now explicitly chooses dismissal.

## Verification Evidence

- SC1: `bun test src/push/watcher.test.ts` passed `ends immediately on the first empty tick`; the independent reducer probe observed `event: "end"`, `nextActive: null`, empty content, and a dismissal date equal to the current tick.
- SC2: Existing prompt precedence tests passed; the independent reducer probe confirmed needs-input both preserves an existing activity and starts one when absent.
- SC3: `bun test src/push/watcher.test.ts` — 44 pass, 0 fail. `bun test` — 616 pass, 0 fail. `bunx tsc --noEmit` — pass.
- Independent audit: PASS — `.codex/evidence/20260815-211620-verification-audit/evidence.md`.

## Residual Risks

- Immediate end/start cycles rotate ActivityKit update tokens more often when sessions resume shortly after becoming idle.

## Bugs

_None yet._
