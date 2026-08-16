# Feature: Codex Live Rollout Binding

## User Story

As an LFG client user, I want a live Codex pane to open the transcript that the process is actually using so that a running session never renders as an empty conversation.

## User Flow

1. Open a live Codex session from the LFG session list.
2. LFG resolves the pane to the rollout created for that live process.
3. The session view renders the existing conversation while preserving its live busy state.

## Success Criteria

- [x] SC1: An abandoned metadata-only rollout whose embedded timestamp resembles the process start cannot outrank the rollout file actually created at launch. — **Verify by:** `bun test src/codex-bind.test.ts`
- [x] SC2: Existing promptless, prompt, resume, and fork binding behavior remains green. — **Verify by:** `bun test src/codex-bind.test.ts`
- [x] SC3: `codexy-185136-73608` resolves to its populated `a287…` rollout and returns messages. — **Verify by:** live `/api/sessions` and `/messages?limit=20` probes after restarting the LFG host.

## Platform & Stack

- **Platform:** Node-compatible backend/CLI
- **Language:** TypeScript
- **Key frameworks:** Bun

## Steps to Verify

1. Run the focused Codex binding tests.
2. Run the broader session/transcript tests.
3. Restart the LFG host through its existing supervisor workflow.
4. Query the live session row and message endpoint for `codexy-185136-73608`.

## Implementation Phases

### Phase 1: Regression and selector correction

- Scope: incorporate filesystem creation time into launch-time rollout selection.
- Success criteria covered: SC1, SC2.
- Verification gate: focused and broader backend tests pass.

### Phase 2: Live verification

- Scope: reload the host and probe the affected session through the public API.
- Success criteria covered: SC3.
- Verification gate: affected row points to `a287…` and messages are non-empty.

## Decision Log

- Prefer filesystem creation time as an additional launch-binding signal. Codex can create a metadata-only rollout later while preserving the original process timestamp in `session_meta`; that embedded timestamp alone is not proof that the file existed at launch.
- Keep `sessionId` and transcript response contracts unchanged; only correct which rollout wins the existing heuristic.
- Audited downstream `sessionId` consumers in server routing, journaling, leases, send queues, search indexing, and iOS persistence/navigation. They all consume the selected rollout ID as the stable key; no contract or migration change is required.

## Verification Evidence

| Criterion | Command/action | Observed result |
| --- | --- | --- |
| SC1 | `bun test src/codex-bind.test.ts` | 18 passed, including the late metadata-only rollout regression. |
| SC2 | `bunx tsc --noEmit && bun test` | Type-check passed; 620 tests passed with 0 failures. |
| SC3 | `GET /api/sessions` filtered to `codexy-185136-73608` | Returned `sessionId` `01a0050c-a287-7ad1-b930-4223a6242ac3`, the populated rollout path, the current user request, and `busy: true`. |
| SC3 | `GET /api/sessions/01a0050c-a287-7ad1-b930-4223a6242ac3/messages?limit=20` | Returned 7 normalized recent messages rather than the previous empty array. |
| SC1–SC3 | Independent verification audit | PASS; the auditor independently reproduced 18 focused test passes and observed 12 live messages. Evidence: `.claude/evidence/20260815-204326-verification-audit/evidence.md`. |

## Bugs

_None open._
