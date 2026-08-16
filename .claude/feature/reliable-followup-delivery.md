# Feature: Reliable follow-up delivery

## User Story

As an LFG user, I want follow-up messages sent to idle or running sessions to be accepted promptly and delivered exactly once so that “Queued” represents real agent-side ordering, not an indefinite server-side hold.

## User Flow

1. Open a live idle or running session.
2. Send a short, multiline, or large pasted follow-up.
3. LFG immediately attempts submission to the agent composer.
4. An idle agent records the turn immediately; a running agent holds it in its native next-turn queue.
5. The pending row resolves exactly once when the transcript records the user turn.

## Diagnosis

- The durable send trace contains 251 message lifecycles. LFG intentionally held 58 of them server-side whenever pane scraping said the agent was busy.
- 53 messages waited more than 10 seconds before delivery even began; 45 waited more than one minute. P90 start latency was 386 seconds and the maximum was 3,001 seconds.
- This is a policy failure, not merely a polling delay: `kick()` refuses to call `deliver()` while `agentBusy()` is true, even though both Codex and Claude provide a native next-turn queue and the delivery code already supports the `queued` state.
- A separate fresh idle failure involved a very large multiline paste. Large Codex pastes render as a collapsed pasted-content marker that the current confirmation probe may not recognize.
- Once a message has entered an agent’s native queue it can no longer be safely removed or edited. Existing client actions must not pretend a rejected server removal succeeded.

## Success Criteria

- [x] SC1: An online follow-up begins a delivery attempt promptly whether the target session is idle or running; no pane-busy gate can hold it indefinitely. — **Verify by:** server unit tests plus a live running-session API probe showing `pending` transitions to `queued` or `delivered` within 2 seconds.
- [x] SC2: Short, multiline, and large pasted follow-ups sent to an idle Codex session each produce exactly one user turn without a failed queue row. — **Verify by:** focused parser/send tests and disposable live Codex sessions.
- [x] SC3: A follow-up sent during a running turn enters Codex’s native queue promptly, preserves ordering, and surfaces exactly once after the next tool boundary. — **Verify by:** disposable live Codex session running a controlled long tool call, queue snapshots, transcript counts, and pane captures.
- [x] SC4: Remove/Edit remains truthful: a message still held by LFG can be removed, while a message already committed to the agent cannot disappear locally when server removal is rejected. — **Verify by:** server queue-action tests and LFGCore/SessionStore tests for failed removal handling.
- [x] SC5: Existing queue recovery, deduplication, Claude/Codex composer parsing, and iOS optimistic reconciliation remain green. — **Verify by:** `bun test`, relevant Swift tests, and independent verification audit.

## Platform & Stack

- **Platform:** Bun/TypeScript server plus iOS SwiftUI client safety handling
- **Languages:** TypeScript, Swift
- **Key frameworks:** Bun test, tmux, Swift Testing/XCTest, SwiftUI

## Steps to Verify

1. Run focused server tests for immediate delivery policy, native-queued reconciliation, and large-paste recognition.
2. Run relevant LFGCore/iOS unit tests for queue-action failure handling.
3. Run `bun test` and the applicable Swift test suites.
4. Reload the LFG server.
5. Exercise idle and running sends against disposable Codex sessions, recording queue latency, pane state, transcript count, and cleanup.
6. Run the independent verification audit.

## Test Strategy

- Server unit tests pin the policy that both idle and busy online sessions choose immediate delivery, recognize literal and collapsed paste composers, and reject removal after native commitment.
- LFGCore unit tests pin the client-side mutation rule: offline/local and successfully removed server-held rows may disappear, but a server-rejected row remains pending.
- Disposable live Codex sessions prove the real tmux/API behavior for idle, large-paste, and mid-turn sends, including latency, ordering, and exactly-once transcript counts.

## Tests

- `src/sendq-delivery-policy.test.ts`
  - idle and busy sessions both select immediate delivery — SC1
  - literal, Claude pasted-text, and Codex pasted-content composers confirm insertion — SC2
  - pending removal succeeds but native-queued removal is rejected — SC4
- `ios/LFGCore/Tests/LFGCoreTests/QueueAckResolutionTests.swift`
  - local/offline removal, accepted server removal, and rejected native-queue removal — SC4
- Existing `src/sendq.test.ts`, `src/tmux-codex-pane.test.ts`, `src/sendq-store.test.ts`, and optimistic-send Swift tests remain regression coverage — SC3, SC5

## Implementation Phases

### Phase 1: Server delivery policy and paste recognition

- Scope: Remove the unbounded busy hold, submit online follow-ups to the native agent queue, recognize large pasted-content composer markers, and cover ordering/reconciliation.
- Success criteria covered: SC1, SC2, SC3
- Verification gate: Focused Bun tests and disposable live server probes pass.

### Phase 2: Truthful queue actions and regression verification

- Scope: Prevent unsafe remove/edit behavior after native commitment, preserve pending UI state on rejected actions, run full regression suites, and independently audit.
- Success criteria covered: SC4, SC5
- Verification gate: Swift tests, full Bun suite, live probes, and audit pass.

## Decision Log

- Recommend native queuing over the current hold-in-LFG policy. Reliability and prompt acceptance are the primary contract; edit/remove is only truthful before native commitment.
- Preserve “Send now (interrupt)” for native-queued messages because interrupting a running turn is the one operation the agent queue supports safely.
- Use disposable sessions for live probes; do not inject diagnostic messages into Eugene’s active work sessions.

## Verification Evidence

- `bun test`: 617 passed, 0 failed across 54 files.
- `swift test` in `ios/LFGCore`: 305 XCTest cases and 58 Swift Testing cases passed.
- FlowDeck: the LFG app built and launched successfully on the session-isolated iPhone 17 Pro simulator. The app scheme has no test-without-building action, so package tests provide the Swift unit-test gate.
- Disposable scratch host: idle sends covered short/multiline, a 41,112-byte real failed payload, and a 69,721-byte synthetic paste; every message delivered in one attempt and surfaced exactly once.
- Disposable running session: native queue acceptance took 498 ms; the pane displayed Codex’s next-tool-call queue notice; the follow-up surfaced once in transcript order.
- Reloaded production host: idle delivery completed in 486 ms; a follow-up sent during a controlled running turn entered the native queue in 544 ms and surfaced exactly once.
- Simulator captures: `.claude/evidence/20260814-reliable-followup/`.
- Independent server audit: PASS. It independently measured idle delivery at 520 ms, two ordered running follow-ups at 1,333 ms and 564 ms, exactly-once short/multiline/large-paste delivery, truthful 200/409 removal semantics, queued-row retention across clear, and full test suites. Evidence: `.claude/evidence/20260814-reliable-followup-audit/evidence.md`.
- Independent iOS visual audit: PASS. Remove and Edit rejections kept the native-committed row visible; Edit left the composer empty; the paired server request returned 409. Evidence: `.claude/evidence/20260814-reliable-followup-ios-audit/evidence.md`.

## Bugs

- Follow-ups can remain `pending` for minutes because `kick()` stops at the pane-busy gate.
- Large pasted follow-ups can fail composer confirmation.
- Client remove/edit paths discard local state even when the server rejects the operation.
