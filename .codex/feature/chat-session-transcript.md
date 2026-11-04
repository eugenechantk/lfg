# Durable chats use the Session transcript

Product tier. Durable chats should display the coding agent's intermediate prose, grouped tool calls/results and child agents through the existing Session components.

## Contract and guard

Keep durable identity, instructions, memory, scheduling and offline queue. Add an optional transcript snapshot per saved turn using SessionMsg/SessionMessage. Older hosts and saved chats retain the text fallback. Replace each live turn snapshot atomically, rather than merging stale partial rows. Never display the provider's private-memory/request envelope or scheduled-job control envelope.

This is a medium-risk data/UI integration. Existing chat tests cover worker ownership, stop/resume, queue reconciliation, jobs and history. New tests cover native event normalization, intermediate ordering, tool pairing, child isolation/lifecycle, saved reload, backward-compatible cache decoding and optimistic sends.

## Success criteria

- [x] Intermediate prose and tool calls/results survive completion and reload with stable identities. Verify native-worker and transcript tests.
- [x] Child agents show running/completed/failed/stopped status and inspectable transcripts without finishing the parent turn. Verify reducer/worker tests and native recording.
- [x] Chat uses TranscriptMessageView, TranscriptStepGrouper/ToolStepGroupView and the Session subagent components. Verify native tools expansion and child navigation.
- [x] Streaming updates replace partial text, not stale cached prose or duplicated final replies. Verify projection tests and native recording.
- [x] Offline queue, cached history, keyboard transitions and Sessions filtering still work. Verify package tests and bounded native regression flow.
- [x] Public transcript excludes private request and job-result envelopes. Verify backend tests.

## Decision log

Reuse the Session data and rendering primitives while preserving the durable chat's transport and queue. A terminal, Space and desktop are not required. Existing Session scrolling remains unchanged.

## Verification evidence

- Screenshot review: `.codex/feature/chat-session-transcript-ui-canvas/index.html` and `canvas.png`. All 29 captured states are listed in `manifest.json`; coverage and evidence limits are in `coverage.md`. The gallery reuses the current audited UI captures and includes five recordings. Share: https://share.eugenechantk.me/durable-chat-screenshots-66e172/ (served from the MacBook Pro, no login; stops at reboot until restarted).

- Backend targeted suite: 42 tests, 229 assertions pass. Logs: `.codex/feature/chat-session-transcript-backend-tests.txt`.
- TypeScript `tsc --noEmit` passes.
- LFGCore: 591 tests across 91 suites pass. Tests include rich snapshot replacement, offline cache restart, old-cache compatibility and retained older pages.
- Independent backend audit PASS: 51 tests and 270 assertions, including eight independent probes and scheduled-job privacy checks. Report: `.codex/evidence/chat-rich-transcript-backend-audit/evidence.md`.
- Final shared-model iOS compile passes at 05:23:26 UTC on 2026-11-04. Mac compile passes at 05:23:01 UTC; 287 desktop checks pass.
- Independent native audit PASS on iPhone and iPad. Recorded flows verify tool/result expansion, live and completed child transcripts, same-ID text updates, navigation/relaunch persistence, keyboard draft retention and offline queued messages. Report: `.codex/evidence/chat-session-transcript-audit/evidence.md`.
- Completed subagents remain available from Chat settings after their active pill disappears. The finished composer has no empty pill spacing.
- The auditor reviewed the final declaration-only model extraction; it is byte-identical except the final newline. Both final native builds and package tests pass.
- Saved FlowDeck defaults are unchanged, canonical XcodeGen is restored, and all owned UI sessions, recordings and fixture servers are stopped. Fixture ports are closed. Changes remain uncommitted and undeployed.

## Compatibility and lifecycle details

New turns retain structured activity in their existing atomic turn receipts. Each poll replaces the whole saved turn snapshot, so streamed and final rows cannot accumulate stale duplicates. The existing public text response stays compatible with older clients.

Scheduled runs use the same structured activity capture. Their public parent/child rows and child summaries omit partial and complete job-result control blocks. A live/completed integration test verifies intermediate prose and tool results remain visible while the saved notification decision still drives the scheduler. It also checks detail, child transcript and generic Session responses. The independent privacy probe exposed the child-summary path; that path now stores the sanitized metadata too.

Older turns recover activity from the most recent 1 MiB of their provider log when available. Import requires a recognized request envelope and a timestamp inside the saved turn. Unrelated input closes ownership. Missing, truncated or unavailable provider history keeps its saved text fallback; no action is replayed.

Task lifecycle events can omit tool IDs. The reducer retains task-to-tool ownership, excludes shell/ambient tasks from subagent indicators, and ignores stale runs. The [official SDK reference](https://code.claude.com/docs/en/agent-sdk/typescript#sdktaskstartedmessage) documents lexical start ordering for run IDs and task-ID fallback. Background child completion and subsequent assistant output keep the warm worker alive. The shared busy event includes child activity and background follow-ups.

The first independent audit exposed repeated-prompt history contamination, retained ownership after unrelated input, a worker restart after asynchronous follow-up, and an optional-ID lifecycle mismatch. Permanent regression tests and independent reproducers now pass for these corrections.

## Boundaries

The rich UI change targets iOS/iPadOS. Desktop shared sources must still compile. No commit, push, host restart, deployment or TestFlight build is authorized by this request. Native evidence uses isolated fixture hosts, not a production provider account.

The standalone desktop build compiles selected Core files directly. The unchanged SessionMessage, ToolCallInfo and MessagesResponse types now live in SessionTranscriptModels.swift, included by both builds with ChildAgentSessions.swift. The iOS-only host-file client helper stays outside the standalone desktop dependency graph. This is a type-only extraction; package/native compile gates verify the shared contract.
