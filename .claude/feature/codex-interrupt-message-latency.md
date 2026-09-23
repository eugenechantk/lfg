# Feature: Fast Codex interrupt with message

## User Story

As an LFG user steering a busy Codex session, I want “Send now (interrupt)” to stop the current turn and start my replacement message promptly, matching the responsiveness of Claude Code.

## User Flow

1. Send a follow-up while Codex is busy; LFG keeps it pending so it cannot be absorbed into the current turn.
2. Tap the pending row and choose “Send now (interrupt).”
3. LFG submits that one message to Codex’s native queue, then sends Escape.
4. Codex interrupts the current turn and immediately starts the selected message.

## Success Criteria

- [x] SC1: A busy Codex “Send now” bypasses LFG’s normal busy hold for only the selected message, queues it natively, then interrupts. — **Verify by:** focused send-queue policy tests plus a disposable live Codex timing probe.
- [x] SC2: An idle Codex does not receive Escape when “Send now” races with natural turn completion. — **Verify by:** focused send-now planning tests.
- [x] SC3: Claude’s existing interrupt-then-deliver behavior is unchanged. — **Verify by:** focused send-now planning tests and the full Bun test suite.
- [x] SC4: The change type-checks and does not regress queue delivery behavior. — **Verify by:** `bunx tsc --noEmit` and full Bun test suite.

## Platform & Stack

- **Platform:** LFG host/backend
- **Language:** TypeScript
- **Key frameworks:** Bun, tmux-driven agent sessions

## Steps to Verify

1. Run the focused send-queue delivery-policy tests.
2. Run the full Bun test suite and TypeScript type checking.
3. Restart the supervised LFG host.
4. Create a disposable busy Codex session, enqueue a replacement message, call “send-now,” and measure enqueue-to-user-turn latency.

## Implementation Phases

### Phase 1: Encode sequencing policy

- Scope: Add an explicit send-now plan for queued, busy-Codex, busy-Claude, and idle cases.
- Success criteria covered: SC2, SC3.
- Verification gate: focused policy tests pass.

### Phase 2: Fast-path busy Codex

- Scope: Let only the selected urgent row bypass the Codex hold, wait until Codex accepts it, then interrupt.
- Success criteria covered: SC1, SC4.
- Verification gate: focused and full tests pass; live timing probe confirms the selected turn starts promptly.

## Decision Log

- Keep normal Codex follow-ups held by LFG. Codex’s ordinary busy-send semantics steer the current turn after the next tool call, so changing all sends would revive the lost-follow-up bug.
- Change only the explicit “Send now (interrupt)” action. Codex’s TUI advertises that an already-native-queued message can be sent immediately with Escape, which is the closest match to Claude’s direct handoff.
- Do not send Escape to an idle session; a second/idle Escape can open history instead of stopping work.

## Verification Evidence

| Criterion | Verification | Observed result | Evidence |
| --- | --- | --- | --- |
| SC1 | `bun test src/sendq-delivery-policy.test.ts` | 16 passed, 0 failed, including the explicit busy-Codex bypass policy. | Terminal output, 2026-09-23. |
| SC1 | Disposable live Codex session `01a0cd71-61e3-7222-b6da-b170dc57d38b` | Row `b868ad5ad7ae0d68` began pending, entered Codex's native queue, received Escape 673 ms into the endpoint, became a durable user turn at 08:46:15.295Z, and replied `NEW_DONE` at 08:46:18.601Z. The endpoint returned in 772 ms; the replacement turn began about 0.85 s after the action. The interrupted `OLD_DONE` response did not run. The disposable session was then closed. | `~/.lfg/sendq.log`; `~/.codex/sessions/2026/09/23/rollout-2026-09-23T16-45-55-01a0cd71-61e3-7222-b6da-b170dc57d38b.jsonl`. |
| SC2–SC3 | `bun test src/sendq-delivery-policy.test.ts` | 16 passed, 0 failed, 29 assertions. Tests assert idle pending and idle native-queued rows never Escape, busy-Claude interrupt-then-deliver, busy native-queued interrupt-only, and busy-Codex deliver-then-interrupt. | Terminal output, 2026-09-23. |
| SC4 | `bunx tsc --noEmit` | Passed with no diagnostics. | Terminal output, 2026-09-23. |
| SC4 | `bun test --timeout 20000` | 971 passed, 0 failed, 2,173 assertions across 85 files. The default 5-second timeout was also attempted; three corpus-scanning resumable-session tests exceeded 5 seconds under load, then passed both in isolation and in the full suite with the 20-second test timeout. | Terminal output, 2026-09-23. |
| SC1–SC4 | Live host restart | Listener restarted from PID 96900 to PID 82636 for the live probe, then to PID 14943 after the idle-race fix; `/api/sessions` health probe returned `ok`. Existing agent sessions remained live. | Terminal output, 2026-09-23. |
| SC1–SC4 | Independent audit | Final verdict **PASS** after the verifier identified and the implementation fixed the idle native-queued Escape race. | `.codex/evidence/codex-interrupt-message-latency-audit/report.md`. |

## Bugs

- Independent audit found the first planner checked `queued` before checking whether the session had become idle, so an idle native-queued row could still receive Escape. Fixed by making known-idle state authoritative and covering both pending and queued idle rows in the focused regression test.
