# Durable chat sessions

Message opens lasting chat sessions. Each chat owns its instructions, private memory notes and complete history. It runs without Cua, Docker, a desktop, or a project directory.

## Runtime

The owning LFG host keeps a native Claude Code conversation using its existing authentication. A headless worker receives new messages over stdin and streams responses over stdout. It needs no tmux pane, terminal window, or Space.

Each chat saves a provider session ID and a private working directory. The host keeps the worker warm between turns. After three idle minutes it releases the worker; the next message resumes the same saved provider conversation. Host replacement also resumes that identity.

Durable chats use Claude Code's built-in tools, shell commands, file tools, configured MCP servers, skills and plugins. The worker loads the host's normal configuration and environment, like LFG's managed coding sessions. It uses the same full-permission mode (`--dangerously-skip-permissions`); managed host policy can still restrict capabilities. Interactive permission prompts have no client UI and are denied rather than left waiting. MCP services that need login must already be authenticated on the host.

The runner preserves Claude's default coding system prompt and appends the chat's current standing instructions. It verifies the matching provider conversation identity and accepts tool cycles while projecting only main-conversation assistant prose into LFG. Tool inputs/results, thinking, and subagent output are not rendered as chat text. Full tool activity remains in the native provider transcript. Worker processes and transcripts never appear as duplicate terminal sessions in discovery or search.

The working directory is the chat's provider directory, not a selected repository. Host-global MCP/skill configuration loads normally. Repository-local instructions and integrations are not automatically imported from an unrelated repository. Tools can use explicit paths to other host files. No project picker or Space is required.

This is host-user access, not filesystem isolation. Files, shell commands and MCP credentials belong to the selected host, not the iOS client. Chat settings and supplied context remain separate, but a tool-enabled agent can read other files allowed by that OS account. There is no container or per-chat OS sandbox.

Graceful host shutdown closes workers and their process groups, including ordinary shell and MCP children. Crash recovery inspects each saved worker lease and process-group identity and retires only a verified orphan before resuming. Failed identity inspection blocks recovery rather than risking concurrent writers. If a worker leader is gone but live tool processes remain, recovery preserves its lease and blocks resume; it cannot safely kill an unverified process group. Replies have a 30-minute execution limit; idle workers still close after three minutes.

## Data and memory

Records live under `LFG_DATA/chat-sessions`, normally `~/.lfg/chat-sessions`.

Each chat has one metadata file, separate turn files, and a private provider directory. Metadata records the provider conversation ID and applied settings revision. A turn contains a stable request ID, ordered user and assistant messages, and a completion state. Streaming updates only the active turn file. History pages read a bounded set of turn files using an index built at startup.

Standing instructions control future replies. Editable memory notes hold facts and preferences. A native provider manages its conversation context and compaction. LFG keeps the full original user-visible history independently. New turns carry current memory and new input, rather than reconstructing that history.

Instruction or model changes restart the warm worker and resume the same conversation with a freshly rendered system prompt. Memory notes accompany every turn so corrections override older replies. LFG supplies only this chat's instructions and memory. Tool access is not an isolation boundary for other files on the host. Settings use revision checks so an older editor cannot overwrite newer edits.

Earlier LFG-only chats import their saved summary plus unsummarized turns once. All original messages remain readable. A legacy import above 320,000 characters fails explicitly rather than silently dropping context.

## Recovery

One host process owns a chat store. A second live owner cannot open it. Acceptance hosts must use separate `LFG_DATA` directories.

After a host crash, the replacement marks unfinished turns interrupted and publishes an idle event. It keeps partial text and request receipts. It never automatically repeats an interrupted request. A confirmed repeated request returns its existing receipt. Reusing that identifier with different text fails.

Stop cancels the active provider process group. The conversation remains available for the next message. Completed file changes and remote tool actions are not rolled back. Intentionally detached background jobs are outside that process group.

## Session integration

The shared Session snapshot carries `kind: chat` and a stable `chat-…` identity. Chat snapshots use the same working, idle, and blocked vocabulary as other sessions. Host connectivity remains a separate concern.

The host combines chat and terminal snapshots for `/api/sessions` and notification observation. Chat creation, messages, and busy transitions enter the existing event journal. New chat events refresh live membership without waiting for terminal history. The creating client also refreshes membership directly. A timestamp fence prevents older snapshots from removing the new row. The terminal scanner excludes temporary chat worker processes. Chat routes reject terminal operations, including close, resume, and transfer.

The current compatibility snapshot uses PID zero and no terminal target. Consumers must branch on `kind`; PID zero does not name a process to control. The Mac shows chats in Message. The iPhone also routes chat rows in Sessions to the chat screen.

Chats can own scheduled tasks. One TaskStore, scheduler and API support coding sessions, chat instruction runs and fixed reminders. Chat settings filters the same records shown in Tasks. See [Scheduled tasks in chats](chat-jobs.md). Chat ownership does not move between hosts. Normal completion notifications use the existing watcher.

## API

- `GET /api/sessions/chats`: list durable chats.
- `POST /api/sessions/chats`: create with name, instructions, and memory.
- `GET /api/sessions/<chat-id>?before=<sequence>&limit=50`: read a history page and settings.
- `POST /api/sessions/<chat-id>/send`: accept text with a stable request ID.
- `POST /api/sessions/<chat-id>/interrupt`: stop the active turn.
- `POST /api/sessions/<chat-id>/settings`: update settings using the last read revision.

The separate `/api/message/spaces` prototype remains available to its existing clients. Native Message now uses the durable session routes.

## Verification

Run `bun test src/chat-sessions.test.ts src/chat-api.test.ts src/chat-claude.test.ts src/chat-native.test.ts src/chat-native-worker.test.ts` and `swift test --package-path ios/LFGCore`. Build and validate the native app through FlowDeck. The implementation and evidence ledger live in `.codex/feature/native-durable-chat.md`.
