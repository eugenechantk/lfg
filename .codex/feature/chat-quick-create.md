# Instant durable chats

## User story and flow

Tap New chat and start typing immediately. The client saves a randomly named conversation locally, uses Claude Default, leaves instructions and memory empty, and prefers the configured default host. Known-unreachable hosts yield to an available host before registration. All-hosts-offline creation and messages remain queued.

The user can ask the conversation to save an explicit standing instruction, memory, name or model change. A chat-scoped profile tool applies requested fields and reports a saved receipt. Existing settings remain available. A currently executing turn retains its accepted instructions; changes apply to subsequent turns.

## Success criteria

- [x] SC1: Every New chat entry opens the conversation without a setup form. Recorded dock and More flows pass on iPhone/iPad. A fresh empty-fixture recording verifies the empty-list button opens Scout in one tap and registers exactly one chat on Pro, none on Air.
- [x] SC2: Names come from a bundled pool, avoid existing names, and default instructions/memory/model remain empty. Core tests and native settings pass.
- [x] SC3: Prefer the default host, fall back before registration, and retain offline creation/ordered queues and uncertain-owner safety. Core and native offline/reconnect checks pass.
- [x] SC4: The owning conversation can read/save only its own profile with revision checks, including during a turn; future turns use the persisted changes. MCP route tests and native fixture flow pass.
- [x] SC5: iOS and standalone desktop sources compile; existing transcript/queue tests pass. Builds and regression tests pass.

## Decisions

This is product-tier work. Use the existing durable workspace and registration flow, not a second creation transport. Pick the initial name from a local list; no model call is needed. Do not inject invented standing instructions.

Full migration of already registered conversations needs a separate decision: provider state, host files and scheduled jobs currently belong to one host. Initial host fallback is already safe before registration. Never re-register an uncertain accepted creation on another host.

## Verification evidence

- Core: 594 tests across 91 suites pass, including new defaults, naming exhaustion, preferred-host and offline creation cases. `.codex/feature/chat-quick-create-core-tests.txt`.
- Backend: 50 targeted tests, 285 assertions pass. `.codex/feature/chat-quick-create-backend-tests.txt`. TypeScript `tsc --noEmit` passes.
- Independent backend audit PASS: two independent probes / 29 assertions and 39 regression tests / 229 assertions. Scope, revision concurrency, partial validation rollback, user/scheduled turn guards, accepted-versus-next-turn settings and reload persistence pass. `.codex/evidence/chat-quick-create-backend-audit/evidence.md`.
- FlowDeck iOS build passes at 06:01:36 UTC; standalone Mac build passes at 06:02:35 UTC on 2026-11-04. Logs are under `.codex/feature/chat-quick-create/`.
- Independent native audit PASS: `.codex/evidence/chat-quick-create-ui-audit/evidence.md`. Final iOS viewport build passes at 06:17:10 UTC. Phone receipt `38E9B16F-93EC-4E2F-9DDB-BAF718DF9082`; iPad receipt `E184E652-05C2-452A-BA2E-F417CDDF93C5`. Nine final screenshots and three recordings capture the current build, including the fresh empty-list entry check. Earlier unaffected creation/default/profile/transport flows retain their separate receipts.
- Review gallery: https://share.eugenechantk.me/instant-chats-68fa0a/ — local files under `.codex/feature/chat-quick-create/review/`. The page has no login and runs from the MacBook Pro; sharing stops at reboot until restarted. The prior transcript gallery now links here and labels its older captures.
- Gallery verification: nine images decode, three recordings are present, phone width has no horizontal overflow, and the public URL returns HTTP 200. Fixture ports 18976/18977 are closed. Final source hashes and backend audit hashes match.
- Both named session-owned simulators were shut down before validation; the other active LFG simulator belongs to a separate worktree. Saved FlowDeck defaults remain unchanged. Canonical XcodeGen is restored; owned UI sessions/recordings are stopped and keyboards restored. The private fixture was stopped after review.
- Final TypeScript check passes after the descriptor-only clarification. Affected source paths pass `git diff --check`; unrelated concurrent files remain untouched.

## Scope

Initial creation and host fallback are implemented. Existing registered conversations keep their current host and queue while it is offline. Full transfer of existing history, files and scheduled jobs is outside this change, pending the host-transfer decision.

No commit, push, deployment, server restart or TestFlight build is authorized for this change. Native verification uses isolated fixture hosts and a fake provider that calls the real profile MCP route; it does not verify live model intent selection.

## Verification setup correction

The first phone launch repeated the single-value `--launch-env` flag. Only the final value took effect, so the app loaded cached configured hosts. The auditor tapped New chat once but sent no message and changed no settings. The empty Rowan chat registered on the local production host (`chat-462fd626-d584-46ee-9af1-897a39ff6359`, createdAt `1793772297301`). It remains untouched; no agent turn ran. Those initial captures are excluded from fixture evidence. Subsequent validation must pass all environment values in one flag and confirm fixture API calls before UI mutations.

## Native finding and correction

The reviewer found that a short completed reply and its tool group could sit behind the composer. Separating the composer into a VStack alone did not fix it. The final correction also removes the transcript's expanded top-safe-area sizing and compensating margin, keeping the ScrollView within the actual remaining viewport. The diagnostic group IDs did not surface in AX, so the auditor used visible child bounds and screenshots. Final tool-row bounds are y643–666, reply y681–726, and composer text y763. Tool expansion/detail and current-build keyboard draft retention pass. The shared toolbar/input controls and keyboard notifications remain in use.

Research: Apple's [default scroll anchor documentation](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:)) separates initial position, size changes and undersized-content alignment. The measured native result, rather than the anchor configuration alone, is the acceptance gate.
