# Consolidated Improvement Log — 2026-09-23

## Scope

This digest consolidates the non-empty improvement logs created after the
2026-08-23 digest. The older historical backlog recorded in that digest remains
open. Source logs are retained because deleting them requires explicit approval.

## Recurring themes

### Verify the real user-visible operation

- A passing build, route probe, or precondition check is not enough when the
  requested outcome is an interaction or deployment. Exercise the exact UI or
  API path and retain durable evidence of the final state.
- For TestFlight, verify the uploaded IPA version/build and Apple-side build
  status; do not stop at a successful upload response.
- For transcript work, validate against observed production JSONL shapes as
  well as small fixtures. Real corpora repeatedly exposed provider-specific
  rows that synthetic examples missed.

### Protect live sessions and user input

- Avoid broad key injection, composer clearing, or process replacement on live
  agent panes. Resolve the exact target and preserve drafts, queues, sessions,
  and unrelated host state.
- Treat interrupt, send-now, model-switch, handoff, and resume behavior as state
  machines. Re-check state immediately before the mutating action because busy,
  idle, queued, and prompt states can change during the request.

### Keep verification tools exact and reproducible

- Use the documented FlowDeck invocation, simulator ownership, and output
  fields. Several detours came from guessed flags or interpreting test-count
  summaries incorrectly.
- When an independent verifier cannot run because its fixed model or
  credentials are unavailable, retry only when useful, then perform and label a
  self-audit rather than implying independent verification.
- Slow corpus scans can exceed a default test timeout. Re-run the exact failing
  test in isolation before classifying it, then use a justified suite timeout
  without weakening assertions.

### Maintain accurate operational memory

- Re-check repository configuration, current scripts, and live state before
  trusting old notes. Stale signing, deployment, host, and simulator details
  caused avoidable work.
- Record only verified facts, include the actual command or seam used, and
  update durable guidance when the same mistake recurs.

### Make shared-tree work revert-safe

- Inspect the complete dirty tree before release and include intentional work
  even when it predates the current session.
- Group commits by revert boundary where files permit it. When multiple features
  deliberately overlap in central files, prefer one coherent release-boundary
  commit over fragile hunk staging that can separate code from its tests.
- Re-check the tree after builds and deployments for generated or normalized
  project changes, and commit only intentional repository-owned artifacts.

## Actions adopted

1. Require exact end-to-end evidence for UI, host, and TestFlight outcomes.
2. Preserve live pane input and re-evaluate mutable state at action time.
3. Use observed transcript corpora alongside focused fixtures.
4. Treat isolated reruns as mandatory evidence before labeling a timeout flaky.
5. Audit the full working tree both before and after release automation.
6. Keep source improvement logs until explicit deletion approval is given.

## Open backlog

- The historical pre-2026-08-23 backlog identified in
  `consolidated-2026-08-23.md` is not claimed as processed here.
- Source-log deletion remains pending explicit approval.
