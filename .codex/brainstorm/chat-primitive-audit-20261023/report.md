---
title: Ship the lasting chat first
subtitle: Current worktree audit and a minimal fit with LFG
template: doc
theme: shadcn
lang: en
---

The chat prototype exists, but it still binds each conversation to a Cua Space. Ship a durable chat kind of Session with its own instructions and memory. Keep desktop allocation outside this first release.

## A What actually exists

| Area | Current implementation | Gap for the requested release |
|---|---|---|
| Backend | Create/list Spaces; send/follow up; read events; interrupt; power; browser control; video relay | Chat execution still requires a Space |
| Persistence | One JSON record per Space; saved user messages, cached events, provider run references | No independent chat record, instruction field, or memory field |
| Continuity | Follow-ups reuse the Cua run; restarted desktops start a fresh run with saved context | Restart context uses only the final 16,000 characters; no rolling summary |
| Native UI | Message destination on Mac and iPhone; list, create sheet, transcript, composer, errors, live desktop | UI creates Spaces; no instruction or memory editor |
| Shared LFG integration | Uses the existing host server and configured host authentication | Separate message API, status path, and polling; no shared chat notification integration |
| Designs | Agent thread list, create agent, thread settings, chat, Mac and iPad boards | These are HTML mockups; they are ahead of the native implementation |

This is a working desktop-agent prototype. Removing its desktop controls alone will not produce independent chat.

## B Two worktrees, different jobs

**Implementation:** `.worktrees/cua-message`, branch `codex/cua-message`, HEAD `effc5b5`.

The branch has two commits absent from current main. Current main has six commits absent from this branch. The common ancestor is `5c0aac3`.

The commits add the host backend and image profile, then idle cleanup and restarted-Space reconnection. Native Message views, client models, and build wiring remain modified or untracked. Committing only the existing branch tip would omit the native UI.

**Design:** `.claude/worktrees/cua-agent-threads`, branch `worktree-cua-agent-threads`, HEAD `05e73db`.

This branch has no unique commits relative to current main and is fourteen commits behind it. Its untracked design folder contains 23 HTML boards and generator scripts. Its latest design describes named agents with private instructions, memory, and a lasting conversation. It treats desktops as optional resources.

The native implementation still uses the earlier Space-first flow. The newer design does not prove those features exist in product code.

## C Backend and data model today

```flow
Native Message UI -> LFG host: selected computer
LFG host -> Space record: read and save JSON
LFG host -> Cua adapter: start or follow up
Cua adapter -> Space: agent runs inside
Space -> LFG host: cursor-based events
```

`src/cua-message.ts` defines the record and routes under `/api/message/spaces`. `src/commands/serve.ts` stores records under the LFG data directory in `cua-messages/`.

The record combines three lifetimes:

- Conversation: stable UUID, name, user messages, cached assistant events, creation and activity times.
- Execution: provider choice, current and previous Cua run IDs, event cursors, pending send, error.
- Desktop: Cua Space identity, container identity, power state, mounted paths, guest authentication flag.

Writes use a temporary file and atomic rename. A process-local lock serializes operations on one record. Request IDs prevent a confirmed send from running twice. An uncertain send stays pending and blocks another send. A confirmed rejection clears that pending state.

Creation immediately provisions a desktop. Sending rejects stopped or unavailable Spaces. A first message checks Cua authentication and persistent-home support, then calls `agent_start` with the Space identity. Follow-ups use `agent_message`.

LFG names a Cua persistent home, but it neither stores nor manages a user-editable instruction or memory document. Any provider memory inside that home is outside this record. Saved conversation history is not a complete memory system.

After a desktop stops, LFG retires the run reference. A later message starts a new run with the final 16,000 characters of saved conversation. This proves basic recovery, but older decisions can fall outside that window.

The record also stores growing message and event arrays. Detail responses include the record, and event reads rewrite it. Long chats need paginated history and bounded context preparation.

## D Native UI today versus the newer design

`shared/Message/MessageSpacesView.swift` supplies the shared native interface. `MessageSpaces.swift` supplies its client and transcript projection.

The implemented flow selects a computer, creates a named Space, chooses Claude Code or Codex, and opens Chat or Live Space. Chat joins streamed text fragments and reduces tool activity to short labels. It polls every two seconds while the detail screen is active.

The UI exposes raw agent or power status. The composer requires a Space identity and usable power state. Creating a Space blocks dismissal until the request completes. The list sorts by creation time, oldest first, rather than recent conversation activity.

The native code does not implement the newer agent thread list, standing instructions, private memory editing, or shared unread and needs-you behavior. The newer design also includes desktop controls and account cards that the first chat release can omit.

For chat first, keep Message as the destination. Use a recent-activity list, a simple creation sheet, the transcript, and a composer. Add settings for instructions and memory. Reuse existing transcript and composer styling where their dependencies permit it.

## E How the chat fits existing LFG primitives

```flow
Message screen -> Durable Session: kind is chat
Durable Session -> Conversation store: history, instructions, memory
Durable Session -> Owning host: executes turns
Owning host -> Provider binding: replaceable runtime
Owning host -> Shared state and events: app updates and notifications
```

This is the proposed model. The current `Session` type remains a process-derived view with PID, command, transcript path, and terminal ownership. It cannot represent this model unchanged.

| Primitive | Role in chat first | Current integration work |
|---|---|---|
| Session | Durable conversation identity; chat is one kind alongside terminal sessions | Add durable chat storage and a common session projection; preserve independently started terminal agents |
| Host | Owns chat storage, provider credentials, turn execution, and recovery | Reuse host configuration and routing; initially pin each chat to one host |
| Runtime binding | Connects a chat to its current provider conversation or process | Replace Cua Space/run dependence; a stopped process must not close the chat |
| Turn or run | Tracks one submitted message and its reply | Persist request identity and lifecycle; a Cua run is not a scheduled TaskRun |
| Status | Reports working, idle, or blocked from runtime evidence | Feed a normalized chat state into shared presentation; keep host reachability separate |
| Event journal | Delivers updates and reconnect replay | Extend the common event path; the journal has bounded retention and cannot be the full transcript |
| Notifications | Report reply completion using the same normalized state | Existing watcher discovers terminal sessions; wire chat transitions into it deliberately |
| Scheduled task | Starts bounded work and tracks an outcome | Keep its current behavior; linking tasks to a chat can come later |
| Space | Optional future desktop resource | No role in the first chat release |

A chat waiting for your next message is idle. Authentication failures or usage limits block execution. An offline host is a connection problem. None should invent a question that needs answering.

Reuse the state vocabulary and notification rules. Terminal sessions still need their existing evidence reducer. A managed chat can use explicit provider events instead of terminal scraping.

The current Cua implementation bypasses this shared session path. Its own event cursor does not feed the LFG journal, session list, fleet counts, or session push watcher.

## F Smallest useful release

**Long-running means durable conversation, not a permanently running process.** Keep the chat when the app closes or the provider process stops. Start or resume execution when a message arrives.

Store these small pieces:

- Chat identity: ID, name, owning host, provider, model, and activity time.
- Standing instructions: editable text with a revision.
- Private memory: editable facts plus a rolling conversation summary and the last covered message ID.
- History: ordered user and assistant messages, with pagination.
- Execution: provider binding and durable per-turn request ID, state, and error.

Before each turn, prepare context from the instructions, memory, summary, recent messages, and new message. Keep full history even when the host compacts active context. Update summaries through host orchestration; the assistant does not need file tools to maintain memory.

Use a host-side text provider adapter. The exact CLI or API transport needs selection and a small runtime check during implementation. Existing terminal launch code permits tools and broad file access, so it cannot serve as a text-only runner unchanged. Enforce an empty tool set at the runtime boundary.

Serialize turns per chat. For the first release, Stop can end the active turn before another send. Preserve request IDs across uncertain delivery and offer reconciliation instead of asking users to inspect Cua.

Build the chat store and runner first, then shared status/events, then the native list and editors. Extract useful delivery and transcript code from the prototype. Keep its desktop subsystem separate. This avoids making a chat release depend on finishing desktop orchestration or a wholesale terminal-session rewrite.

## G Verification and release boundary

**Checked now:** 41 focused backend tests passed with 180 assertions across message routes, lifecycle, containers, and streaming. These tests use temporary records and mocked runtimes. They cover follow-ups, duplicate protection, uncertain delivery, saved replies, restart context, and desktop cleanup.

**Historical evidence:** worktree notes record real Claude and Codex replies, same-run follow-ups, native builds, and simulator audits. Later notes record full-screen desktop control. Those results concern the Space-backed prototype. I did not repeat live provider calls or native builds during this audit.

**Not established:** a released independent chat, LFG-owned instructions and memory, tool-free execution, cross-host chat failover, or shared chat notifications. Production deployment state was not inspected.

Before shipping, verify instruction and memory isolation, context compaction, restart recovery, durable request handling, and tool disablement. Verify reply status while the app stays closed. Run native checks after adapting the UI.

## H Source pointers

All implementation paths below are relative to `.worktrees/cua-message/`.

| File | Relevant evidence |
|---|---|
| `src/cua-message.ts:8` | Space, message, and event shapes |
| `src/cua-message.ts:107` | Space list and immediate provisioning |
| `src/cua-message.ts:145` | Detail polling and saved events |
| `src/cua-message.ts:154` | Space-dependent sending, deduplication, and restart context |
| `src/commands/serve.ts:1357` | Host wiring and record directory |
| `shared/Message/MessageSpacesView.swift:11` | Native Space list and create flow |
| `shared/Message/MessageSpacesView.swift:141` | Chat, raw status, polling, and controls |
| `ios/LFGCore/Sources/LFGCore/MessageSpaces.swift:3` | Client model and send eligibility |
| `src/sessions.ts:149` | Existing process-derived Session shape |
| `src/session-state.ts:234` | Shared display state vocabulary |
| `src/journal.ts:1` | Bounded event replay, distinct from canonical history |
| `src/push/watcher.ts:1` | Session-based notifications |
| `.codex/feature/cua-message.md` | Historical acceptance evidence |
| `.codex/feature/cua-codex-image.md` | Historical Codex verification |
| `.codex/feature/cua-space-fullscreen.md` | Historical native control verification |

The newer design lives in `.claude/worktrees/cua-agent-threads/.claude/design/chat-cua-spaces/design.md`.

Audit date: 23 October 2026. This audit adds documentation only. It does not change, commit, merge, or deploy product code.
