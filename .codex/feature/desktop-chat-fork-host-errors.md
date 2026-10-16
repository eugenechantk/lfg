# Desktop task chat and fork failures

## User story
The desktop client must start task chats and fork sessions on their owning host, including this Mac.

## User flow
1. Open Tasks, enter a task chat request, and start the conversation.
2. Choose Fork session on an existing conversation.
3. Open the resulting conversation in iTerm on the correct host.

## Success criteria
- [ ] Task chat creates a usable conversation. Verify with a disposable chat through the real API and desktop flow.
- [ ] Fork creates a distinct conversation on the source host. Verify with a disposable source and the real desktop action.
- [ ] Failures identify the actual cause. Verify targeted regression cases.
- [ ] Relevant tests pass and an independent auditor verifies the result.

## Investigation
The Pro host answers /api/info, /api/scheduled-tasks, and validation requests on both creation routes.
The running desktop app uses /Applications/lfg.app and the configured local host is http://localhost:8766.

## Decisions
Use the existing standalone desktop build script: this target has no Xcode project.
Use disposable conversations for runtime verification. Do not modify scheduled tasks or fork an active user conversation.

## Verification evidence
Pending.

## Runtime results — 2026-10-16
No source changes were made. The reported failure has not reproduced.

- Pro: local task-chat API returned HTTP 200 and a real Claude session. The assistant replied `DESKTOP_CHAT_PROBE_OK`.
- Pro: the installed app's Tasks + form accepted a prompt, started a chat, and attached iTerm to `lfg-c2815e`. Its transcript contains `DESKTOP_UI_CHAT_PROBE_OK`.
- Pro: the installed app's `--fork-session` hook ran the same SessionStore action as the menu. Both Claude and Codex returned success and distinct branches on localhost.
- Air: local task-chat API returned HTTP 200. Its assistant replied `DESKTOP_AIR_CHAT_PROBE_OK`.
- Air: the installed app's `--fork-session` hook created a distinct local Claude branch and returned success.
- Both installed clients configure their own machine as `http://localhost:8766`.
- All seven probe conversations were closed through the host API. The Pro smoke chat continuation preference was cleared.

Evidence: `.codex/evidence/desktop-chat-fork-20261016/` contains API responses, desktop fork results, UI accessibility trees, transcript output, and cleanup responses.

## Blocker
The exact error, failing session/task, and affected Mac are unknown. The user was asked for the error text and Pro/Air identity. Successful disposable flows do not establish that the reported failure is fixed. Existing-task edit chat and the user's original source session were not exercised. No speculative patch or restart was applied.
