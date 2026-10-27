---
title: Durable chat architecture
subtitle: LFG owns the conversation. The provider runs one turn at a time.
template: doc
theme: blueprint
lang: en
source: Verified against codex/cua-message on 23 October 2026
---

The chat survives the provider process. Its host stores instructions, memory, summaries, and complete history. An idle chat needs no provider process or Space.

## A What connects to what

```flow
Native app -> Host chat API: create, send, settings, history
Host chat API -> Chat service: validate and coordinate
Chat service -> Chat files: persist conversation
Chat service -> Claude worker: run one text-only reply
Claude worker -> Chat service: partial text and result
Chat service -> Shared Session view: identity and status
Chat service -> Event journal: message and busy events
```

The worker uses the host's existing Claude sign-in. It starts in a temporary directory with tools and MCP disabled. LFG keeps the canonical history.

## B Three separate kinds of context

| Context | Who changes it | How a reply uses it |
|---|---|---|
| Standing instructions | The user edits chat settings | LFG adds them to the system prompt for every reply. |
| Private memory notes | The user edits chat settings | LFG supplies current facts and preferences in a separate context field. |
| Conversation summary | LFG generates it from older turns | LFG combines it with recent turns and the current message. |

Updated memory takes precedence over conflicting older conversation. Instruction and memory edits affect the next turn. Settings cannot change during an active turn.

Memory notes are currently user-edited. The model does not automatically rewrite them. Automatic summaries provide continuity from older conversation.

## C What persists

```tree
~/.lfg/chat-sessions/
  .owners/ | Prevent two live hosts from opening the same store
  chat-<uuid>/ | One durable identity
    session.json | Settings, summary, revision, status, and summary cursor
    turns/ | Complete ordered conversation
      <request-hash>.json | User text, assistant text, request receipt, and outcome
```

`LFG_DATA` can change the storage root. This adds JSON files, rather than a new SQL database. Atomic file replacement prevents readers from seeing half-written JSON.

The host retains all original turns after summarizing them. A startup index supports history pages without reading every turn for each page.

## D What happens when you send

1. The app sends text with a stable request ID.
2. The host saves the user turn and marks the chat working.
3. The host loads current instructions, memory, summary, and recent turns.
4. The host summarizes older turns when recent context exceeds its character budget.
5. A fresh Claude worker receives that context and the new message.
6. The host saves partial text and emits shared message events.
7. The host saves the outcome, clears busy status, and removes the worker.

The native chat currently polls its detail endpoint for updates. The host also publishes messages into the existing journal for shared consumers.

Summaries use the same text-only runner. A summary failure pauses the turn instead of silently dropping older context.

## E What the backend adds

| Module | Responsibility | Main operations |
|---|---|---|
| `src/chat-sessions.ts` | Durable store and turn coordinator | Create, settings, history, send, stop, summarize, and recover |
| `src/chat-claude.ts` | Temporary provider worker | Launch Claude, enforce empty tools, parse text, stop, and clean up |
| `src/chat-api.ts` | Chat endpoints | List/create, detail/history, send, settings, and interrupt |
| `src/commands/serve.ts` | Host wiring | Open the store, mount routes, append events, and combine Session snapshots |

`ChatRunner` is the provider interface. Claude is its first implementation. A future provider can use that interface without owning the durable history.

The API lives under `/api/sessions`. Chat creation uses `/api/sessions/chats`; individual actions use `/api/sessions/<chat-id>/...`.

## F How existing primitives fit

| Primitive | Relationship to chat | Current boundary |
|---|---|---|
| Session | A chat appears as `kind: chat` in the shared Session API. | A separate chat store backs this projection; terminal sessions remain unchanged. |
| Host | One host stores the chat and executes replies. | No cross-host transfer or cloud replication yet. |
| Status | Chat tracks idle, working, or blocked; the UI shows Ready, Working, or Paused. | Host connectivity and each turn's outcome remain separate. |
| Journal and notifications | Message and busy events use the existing journal and completion watcher. | Production APNs delivery was not exercised. |
| Terminal process | A temporary provider process executes a reply. | The scanner excludes it from terminal discovery; terminal controls cannot target a chat. |
| Space | No dependency for chat. | The separate Space prototype remains available to its existing clients. |
| Scheduled task | No attachment to a chat yet. | Scheduling and chat ownership remain separate. |

The design separates durable conversation from execution. This implementation does not introduce general-purpose Attachment or Run records across LFG.

## G Reliability and scope

One turn runs per chat. Different chats can run independently. Repeating an accepted request ID returns its existing receipt; different text with that ID fails.

Stop ends the worker and retains partial text. After a host crash, startup marks unfinished turns interrupted. It preserves history and never automatically replays them.

Settings carry a revision number. A stale settings editor must reload before it can overwrite newer changes.

This version supports text-only Claude chat, private settings, summaries, and local persistence. Shared project memory, automatic memory-note editing, tools, Spaces, and cross-host ownership are later extensions.

The chat worktree contains the locally verified implementation. Production hosts and releases remain unchanged.
