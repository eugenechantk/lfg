# Feature: Interrupt Message Continues Session

## User Story

As an LFG user steering a busy session, I want “Send now (interrupt)” to stop only the current turn and immediately continue the same session with my queued message.

## User Flow

1. Send a message while the agent is working; LFG shows it in the pending strip.
2. Choose “Send now (interrupt).”
3. LFG interrupts the active turn.
4. LFG observes whether Claude started its native queued turn or absorbed the message into the turn that was aborted.
5. If the message was absorbed, LFG submits it as a fresh user turn once the agent is idle; if Claude already started it natively, LFG does not send a duplicate.

## Success Criteria

- [x] SC1: A Claude message already in the native queue is not treated as complete merely because Claude absorbs it into the turn that is then interrupted.
- [x] SC2: The selected message starts exactly once after the interrupt: Claude's native queued turn is retained, or an absorbed message is re-submitted after the pane becomes idle.
- [x] SC3: A pending Claude message still interrupts before delivery, and Codex’s existing sequencing remains unchanged.
- [x] SC4: Queue policy tests, related queue tests, type checking, and live end-to-end probes cover both Claude outcomes.

## Test Strategy

- Focused TypeScript policy tests encode the distinct Claude queued-message redelivery plan and preserve the existing pending/idle/Codex cases.
- Full Bun and TypeScript checks cover queue and host regressions.
- Disposable live Claude sessions prove both transcript orderings: native queue starts the fresh turn, or absorbed message is retyped after the interrupt marker.
- This is a host-only behavior change; the existing iOS action and endpoint contract are unchanged.

## Tests

### Unit

- `src/sendq-delivery-policy.test.ts`
  - Busy Claude + pending row interrupts, then delivers.
  - Busy Claude + native-queued row interrupts, then resolves whether Claude started it or it needs re-delivery.
  - Transcript classification covers absorbed, native-started, waiting, and stale-history cases.
  - Existing Codex and idle race plans remain unchanged.

## Implementation Details

The observed trace for session `0b4fd8c7-9756-4216-bb18-903ee9b87726` was:

1. queue row became `queued`;
2. Claude emitted `queue-operation remove` with `reason: absorbed_mid_turn`;
3. Escape emitted `[Request interrupted by user]`;
4. LFG promoted the absorbed row to `delivered`, although no new turn started.

The fix locks the durable row while Escape settles, then classifies Claude's raw transcript:

- a real matching user prompt after the interrupt means Claude's native queue started the new turn, so the receipt is completed without typing again;
- `remove` with `reason: absorbed_mid_turn` before the interrupt means the instruction died with the aborted turn, so the same row is reset to pending and re-driven after the pane is idle.

This preserves exactly-once execution across both races.

## Verification

- Focused policy/parser tests: 21 passed, 0 failed.
- Related queue/session tests: 75 passed, 0 failed.
- TypeScript: `bunx tsc --noEmit` passed.
- Live native-queue outcome: interrupt marker, one `promptSource: queued` user turn, one assistant response, and no retype.
- Live absorbed outcome: `absorbed_mid_turn`, interrupt marker, one `promptSource: typed` replacement turn, and one assistant response. The queue trace recorded `resolution: absorbed` followed by `send-now-redeliver`.
- Full Bun suite: 1,055 passed; the sole failure is the existing `src/codex-bin.test.ts` environment mismatch, where the globally installed Codex 0.159.2 wins over the test's fake PATH binaries.

## Residual Risks

- Transcript classification depends on Claude Code's current JSONL queue-operation and interrupt marker shapes. Unknown future shapes time out conservatively: LFG only re-drives if the pane is visibly idle.
- The full-suite Codex binary-selection failure remains unrelated and was not changed as part of this fix.

## Bugs

- Root cause confirmed from the supplied screenshot, `~/.lfg/sendq.log`, and the matching Claude transcript.
