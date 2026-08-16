# Feature: Historical Optimistic Message Reconciliation

## User Story

As an LFG user, I want old messages that already landed in a Codex transcript to disappear from the pending/optimistic UI so that the bottom of a session shows only genuinely pending work.

## User Flow

1. Open a long-running Codex session with historical user turns.
2. LFG binds the pane to its real rollout and loads full history.
3. The client reconciles each optimistic send against transcript turns at or after that send time.
4. Already-landed rows disappear; genuinely unsent or queued rows remain actionable.

## Success Criteria

- [x] SC1: `codexy-153628-89613` binds to rollout `019fff33-6f44-7e00-8b36-b57f762833ce` even though that rollout file appeared 170 seconds after process launch. — **Verified by:** focused Codex binding test plus live `/api/sessions` probe.
- [x] SC2: A historical matching user turn beyond the newest 30 user messages reconciles an old optimistic send. — **Verified by:** `OptimisticSendReconciliationTests`.
- [x] SC3: A same-text user turn from before the optimistic send does not falsely reconcile it. — **Verified by:** `OptimisticSendReconciliationTests`.
- [x] SC4: Existing queue, transcript, and optimistic-send behavior remains green. — **Verified by:** focused Swift tests, full LFGCore tests, Bun tests, and simulator validation.

## Test Strategy

- Add a server regression for a real rollout born 170 seconds after pane launch while retaining rejection of the 30-minute phantom rollout.
- Add Swift unit tests for timestamp-aware full-history reconciliation, pre-send duplicate rejection, and the existing bounded fallback when no send timestamp exists.
- Validate the session detail in Simulator and independently audit the user-visible result.

## Tests

- `src/codex-bind.test.ts`
  - accepts a delayed-but-valid rollout inside the widened launch window — SC1
- `ios/LFGCore/Tests/LFGCoreTests/OptimisticSendReconciliationTests.swift`
  - finds a landed historical turn beyond the old 30-turn tail bound — SC2
  - ignores a matching turn predating the optimistic send — SC3
  - preserves the tail-bounded fallback without a timestamp — SC4

## Implementation Details

- Keep the fast 30-user-turn fallback for callers without a send timestamp.
- When the optimistic send timestamp is known, search all later user turns lazily and stop once messages are older than the send time plus a clock-skew allowance.
- Widen the promptless Codex rollout launch window from two to five minutes; filesystem birth time still rejects the observed 30-minute metadata-only phantom.

## Decision Log

- Use temporal causality rather than a fixed tail count. The transcript match must occur after the local send, which both avoids false matches and permits old landed turns to reconcile.
- Preserve existing uncommitted queue-delivery changes and edit only the reconciliation seam they already use.

## Verification Evidence

- `bun test src/codex-bind.test.ts`: 19 passed, 0 failed.
- `swift test --filter OptimisticSendReconciliationTests`: 8 passed, 0 failed.
- Full `swift test` in `ios/LFGCore`: 308 XCTest cases and 58 Swift Testing cases passed.
- `bunx tsc --noEmit`: passed.
- Full `bun test`: 621 passed, 0 failed.
- `flowdeck build`: succeeded for the LFG iOS project.
- Live `/api/sessions` returned the expected session ID and transcript for `codexy-153628-89613:0.0` after the supervised server reloaded.
- Live full-history fetch returned 1,001 transcript messages, including 49 user turns.
- Dedicated Simulator `cc-01a0056d` opened the exact session and showed the genuine final assistant response directly above the composer, with no bottom-appended user messages.
- Independent iOS visual audit: **PASS**. Evidence and report are in `.codex/evidence/20260815-205626-ios-visual-audit/`.

## Residual Risks

- A clean Simulator cannot reproduce the original device's persisted outbox rows. The reconciliation seam is therefore covered directly by timestamp-aware unit tests, while the live Simulator verifies session binding, transcript rendering, and absence of new spurious bottom rows.

## Bugs

- Fixed: old acknowledged messages could remain bottom-appended because reconciliation scanned only the newest 30 user turns.
- Fixed: the live pane was unidentified because its real rollout file birth time was 170 seconds after process launch, outside the two-minute bind window.
