# Durable chat coding capabilities

Product tier. Existing worktree: `.worktrees/cua-message`.

## User story and flow

A durable chat is a coding-agent session with saved identity, instructions and memory. Send a request in Message; the selected host uses tools, shell, files, configured MCP servers and skills; it returns the answer in the same conversation. Idle shutdown and restart preserve the provider session. No Space or terminal is required.

## Success criteria

- [x] SC1: Native launch enables built-in tools and normal host settings/MCP/skills, using the same permission bypass as managed coding sessions. Preserve the default coding system prompt and append chat instructions. Verify argument/environment tests and a real CLI tool probe.
- [x] SC2: Tool invocation/results do not abort a turn or leak raw tool payloads into assistant text. Verify parser tests and native worker integration with Read/Bash/MCP/Skill events.
- [x] SC3: Tools work across warm turns and resumed workers while current instructions and memory remain applied. Verify native worker tests and a real CLI resumed-turn probe.
- [x] SC4: Stop and crash recovery never replay actions and retire verified owned worker/tool children; unknown live groups must preserve their lease and block resume. Verify child-process cancellation, idempotency, idle and crash recovery tests.
- [x] SC5: Existing text-only fallback and summary runners retain their restrictions. Verify text-only parser/argument tests and chat regression suite.
- [x] SC6: Document host access and working-directory scope. Verify docs and independent backend/API audit.

## Platform

Bun/TypeScript backend. Native client contract and UI unchanged.

## Implementation

1. Add tests for capability-aware output parsing, native arguments and host environment, tool cycles/resume and cancellation.
2. Enable native coding launch, append persistent instructions to the default agent prompt, accept tool protocol, retain full host environment for MCP configuration.
3. Exercise an isolated scratch workspace using actual Claude CLI with local test MCP and skill; audit independently.

## Decision log

- User explicitly requests tools, shell, MCP, coding skills and files. Match existing managed Claude session full-permission mode rather than adding a new approval flow.
- Keep the private provider working directory for stable identity. Host-global configuration is discovered normally; repository-local setup is not automatically selected.
- Maintain text-only legacy/summary runner restrictions. Only native durable workers gain coding capabilities.
- Chat memory remains scoped in supplied context, not an OS filesystem isolation boundary. Tool-enabled host agents can access files permitted by the host OS account.
- Keep current text UI: tool protocol stays in Claude's native transcript; LFG streams assistant prose and shows working status. Structured tool cards are outside this request.
- Do not restart production, commit, push or release.

## Verification evidence

- Red tests: coding init/tool acceptance, appended prompt/discovery and host environment tests failed before implementation. `durable-chat-tools/red-tests.txt`.
- Automated regressions: 61 tests, 261 assertions passed across the five chat suites plus managed tmux launch and effort regressions. `durable-chat-tools/backend-tests.txt`.
- TypeScript: `./node_modules/.bin/tsc --noEmit` passed with no diagnostics. `durable-chat-tools/typecheck.txt`.
- Actual CLI acceptance: Claude Code 2.1.280, Sonnet 4.6, via `chatRoutes` -> `ChatSessions` -> `NativeClaudeRunner`. Real Read, Write, Edit, Bash, Skill and local MCP tool executed. File receipts verified; host-only test env value reached the MCP server. `durable-chat-tools/live-report.json` and `live-probe.ts`.
- Native worker exited after the test idle period. The second provider init used the same provider session ID, recalled the earlier file nonce, applied Pip-to-Miso memory and PROBE_BEFORE-to-PROBE_AFTER instruction edits, and appended a new shell receipt. Final real CLI probe passed after adding no-interactive-prompt policy.
- Native worker tests prove tool payloads, thinking and subagent text/results do not become main assistant prose; duplicate request receipts do not rerun actions; Stop kills a real ordinary child process in the worker group; crash/idle recovery and settings retain provider identity.
- Independent re-audit PASS across all six criteria: `durable-chat-tools/audit/recheck-report.md`. Reviewer reran 61 tests/261 assertions and typecheck, independently reviewed actual CLI tool receipts/transcript, and passed seven recovery probes including zombie leader, missing leader, failed inspection, unrelated PID, verified group, retry after cleanup and zombie-only cleanup. No open findings. No native UI changes were made, so this is a backend audit rather than simulator revalidation.


## Resolved issues

- Live acceptance attempt 1: Read/Write/Edit/Bash/MCP passed; the fixture's project-local skill was excluded by its intentional `--setting-sources ''` override. Provider correctly returned Unknown skill; it did not perform the skill action. Use an explicit isolated test plugin for acceptance, leaving production host discovery enabled. Evidence: `durable-chat-tools/live-report-attempt1.json`.
- TypeScript initially inferred environment spread without an index signature. Added an explicit environment record type; typecheck passed afterward.


## Scope and limits

Production host and existing live chats have not been restarted or modified. This implementation becomes active when this worktree's host code is deployed. No commit, push or release.

The real acceptance run used an explicit local plugin and local stdio MCP configuration, with unrelated host hooks and integrations disabled in the test wrapper. Production argument/env tests verify that discovery is enabled, but no third-party MCP service or arbitrary installed skill was invoked. Normal host settings, managed policy, authentication and service availability still determine actual configured integrations.

Tool calls stay in the native provider transcript. The current LFG chat projection contains user text and main assistant prose; structured tool cards and interactive approval UI are not added. No auto-replay follows interrupted turns, but tool effects already completed are not rolled back.

References: https://code.claude.com/docs/en/headless and https://code.claude.com/docs/en/cli-reference; installed `claude --help` was checked against v2.1.280.

## Independent audit fix F1

The independent audit found a live tool child after its group leader exited. Recovery previously treated leader ESRCH as proof the entire group was gone and removed the lease. It now inspects remaining non-zombie group members, preserves the lease, and refuses resume when ownership cannot be verified. It never kills an unverified numeric group, which may have been reused. For a verified live worker, recovery kills the group and waits boundedly for its ordinary children to exit. A new regression test covers lease preservation, live-child protection and recovery after cleanup.

First fix recheck exposed macOS `kill(group, 0)` returning EPERM for a group containing only reparented zombies. The group-state inspection now handles EPERM, treating live members as blocked and zombies as unable to write. Final 61-test recheck and typecheck passed.

The fixed-model auditor could not start because gpt-5.4 is unavailable on this account. An independent agent using the available model performed the same backend audit, reproduced F1, and passed the fixed implementation on re-audit. Its original FAIL report is retained in `durable-chat-tools/audit/report.md`.

## Final handoff

All six criteria passed. Independent source manifest: `durable-chat-tools/audit/recheck-source-manifest.json`. Main source fingerprints: `durable-chat-tools/source-sha256.txt`. `git diff --check` passed.

Updated the architecture section of the existing review page and its standalone HTML. Live share returned HTTP 200 and matched the local generated HTML. At 402×874 the capability table rendered with no horizontal overflow; screenshot `durable-chat-tools/review-architecture-mobile.png`. It uses the existing Mac-hosted share, with no media uploads. Production host, release state, database and existing chats remain unchanged.
