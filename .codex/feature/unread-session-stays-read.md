# Feature: Unread Session Stays Read

## User Story

As an LFG user, when I open an unread session and then navigate elsewhere, that session must remain read unless a genuinely newer message arrives or I explicitly mark it unread.

## User Flow

1. Open the session list with an unread session.
2. Tap the unread session; it immediately leaves the Unread group and appears idle/read.
3. Open another session or return to the list.
4. The first session remains idle/read.
5. A newer message may make it unread again; the Mark as unread action may also do so explicitly.

## Success Criteria

- [x] SC1: Opening an unread session records its current latest message as seen.
- [x] SC2: Refreshing/reconciling the session list does not resurrect that same message as unread.
- [x] SC3: Navigating to another session and back to the list preserves the read state.
- [x] SC4: A genuinely newer latest-message ID still makes the session unread.
- [x] SC5: Explicit Mark as unread behavior remains unchanged.

## Test Strategy

- Add a deterministic multi-step regression test around open -> reconcile -> navigate away -> list grouping.
- Retain the existing `ReadState` and manual-unread unit coverage for new-message and explicit-unread semantics.
- Verify the full navigation sequence in Simulator with a recording.

## Tests

### LFGCore unit regression

- `ReadStateTests.testOpeningPrefersSessionLatestOverStaleLoadedTranscript` — SC1, SC2, SC3.
- `ReadStateTests.testOpeningFallsBackToLoadedTranscriptWhenSessionRowHasNoPreview` — preserves offline/deep-link fallback behavior.
- `ReadStateTests.testOpeningUsesStreamedTranscriptWhenItIsAheadOfSessionPoll` — preserves live-stream-ahead behavior.
- Existing `testNewMessageAfterSeenIsUnread` — SC4.
- Existing `ManualUnreadTests` — SC5.

## Implementation Details

- Root cause: `SessionStore.markOpened` unconditionally preferred the tail of an already-loaded transcript. When that history was stale, it persisted an older seen-message ID than the `Session.last.id` that made the row unread. Focus temporarily suppressed unread rendering; leaving the detail exposed the mismatch again.
- `ReadState.messageIDToMarkSeen` now reconciles the session preview and transcript tail by real message timestamp, preferring the tapped session preview when ordering is unavailable or tied.
- Focused live events mark their own message ID directly, preserving the stream-ahead-of-poll case.
- A debug-only `LFG_UNREAD_SESSION_FIXTURE` seeds the exact stale-history/two-session navigation sequence for repeatable Simulator verification.

## Residual Risks

- The Debug fixture isolates the reported state transition from real host timing. The production host/network path remains covered by the same `SessionStore` code but was not mutated merely to manufacture an unread session.
- Message timestamps are optional on the wire; when ordering metadata is missing or tied, the tapped session row deliberately wins because its message identity is what made the row visibly unread.

## Verification

- FlowDeck focused `ReadStateTests`: 17 passed.
- FlowDeck full `LFGCoreTests`: 789 passed, 1 pre-existing live-terminal integration test skipped.
- FlowDeck Debug app build: passed on isolated simulator `cc-01a0d6fb`.
- Independent visual audit: PASS. The continuous recording proves Unread 1 -> open -> Idle 2 -> open other -> Idle 2 with no resurrected Unread section.
- Evidence: `.codex/evidence/20260925-221239-ios-visual-audit/evidence.md`.

## Bugs

- Reported: an unread session becomes idle when opened, then becomes unread again after opening another session and returning to the list.
