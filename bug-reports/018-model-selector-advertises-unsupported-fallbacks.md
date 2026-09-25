# Bug 018: Model selector advertises unsupported fallbacks

## Status: FIXED — VERIFIED

## Description

The new TestFlight client shows newly bundled Claude and Codex model IDs when a
host does not implement `GET /api/models`. Starting or switching with those IDs
can fail with `model not found`, leaving no obvious known-working choice.

## Steps to Reproduce

1. Run the September 24 LFG host build, which predates `/api/models`.
2. Open the September 25 client and choose that host.
3. Open the model selector; its catalog request receives HTTP 404.
4. Observe that the client substitutes newly released full model IDs such as
   `claude-opus-5-5` and `gpt-6-astra`.
5. Start a session or switch a session to one of those IDs.
6. Observe the old host/provider returning an unknown-model or model-not-found
   error instead of starting or switching the chat.

## Root Cause

The newer client and server bundled newly released exact model IDs as their
fallback catalog. The long-lived September 24 host predates `GET /api/models`,
so the client received 404 and advertised those optimistic fallbacks anyway.
The old host then rejected `claude-opus-5-5` during request validation. In
addition, creation only reconciled a saved model when the selector was opened,
so a stale selection could bypass catalog validation entirely.

## Success Criteria

1. The legacy-host selector shows Claude aliases and Codex 5.6 compatibility
   models, not unverified Claude 5.5 or GPT-6 exact IDs.
2. A stale saved exact ID is replaced at submission time even if the selector
   was never opened.
3. Live catalogs from updated hosts continue to expose current exact IDs.
4. Starting and model switching remain available against the legacy host.
5. Updated hosts perform an actual Claude model change rather than silently
   retaining the launch-pinned model.

## Investigation Log

### Attempt 1

**Hypothesis:** The new client is falling back to optimistic current model IDs
because the long-lived production host has not been restarted onto the new
catalog endpoint.

**Changes:** None.

**Result:** Confirmed. `GET http://127.0.0.1:8766/api/models?refresh=1`
returns 404, and the host process started on September 24. The client fallback
currently defaults to `claude-opus-5-5` and `gpt-6-astra`; the old server's
Claude allowlist contains only older full IDs and aliases.

### Attempt 2

**Hypothesis:** Compatibility-safe bundled fallbacks plus reconciliation at the
create-request boundary prevent both selector-driven and persisted-model
failures without suppressing live catalogs from updated hosts.

**Changes:** Replaced optimistic bundled fallbacks with Claude aliases and Codex
5.6 IDs in TypeScript and Swift. Added request-boundary reconciliation and
regression tests while retaining dynamic-catalog decoding.

**Result:** Focused TypeScript and Swift regression tests pass. Simulator and
full-suite verification follow below.

### Attempt 3

**Hypothesis:** A successful legacy `/model` HTTP response may still leave a
managed Claude process on its launch-pinned model.

**Changes:** None initially; exercised the just-created Haiku test session by
requesting Sonnet and sending a follow-up.

**Result:** Confirmed. The queue delivered `/model sonnet`, but Claude recorded
`Kept model as Haiku 4.5`, and the follow-up assistant record remained
`claude-haiku-4-5-20251001`.

### Attempt 4

**Hypothesis:** Relaunching an idle managed Claude pane with `--resume` and an
explicit requested model makes switching authoritative while preserving the
conversation.

**Changes:** Updated the current server route to relaunch Claude for all model
switches and reject switches during active work, queued sends, or prompts.

**Result:** Confirmed on an isolated current-source server at port 8877. The
test session process changed PID, its command contained `--resume ... --model
sonnet`, its next reply was recorded as `claude-sonnet-5`, and the server then
reported model `sonnet`. The scratch server was stopped; the production host
was not restarted.

## Verification

- `bun test`: 1000 passed, 0 failed.
- `bunx tsc --noEmit`: passed.
- `swift test`: 191 tests passed.
- FlowDeck Debug build and launch: passed on the dedicated iPhone 17 Pro
  simulator.
- Legacy-host New Session selector: Claude aliases plus Codex 5.6 compatibility
  IDs only; no `claude-opus-5-5` or `gpt-6-astra`.
- Legacy-host chat creation: Haiku answered `ok` without a model error.
- Legacy-host existing-session switch menu: same compatibility-only catalog.
- Current-source host discovery: returned installed Claude Code 2.1.280 and
  Codex 0.156.0 catalogs, including the new exact IDs.
- Independent iOS visual audit: PASS. See
  `.codex/evidence/20260925-160942-ios-visual-audit/evidence.md`.
