---
title: Durable chats across hosts
subtitle: Feasibility confirmed; automatic host switching is a proposed change.
template: doc
theme: blueprint
lang: en
---

## A Decision

**Yes. Keep one durable LFG chat and let eligible hosts run its turns.** I recommend automatic switching between completed turns first.

The current release keeps each registered chat on one host. Host switching needs shared state and execution ownership. It is more than changing the request URL.

## B What the user would see

- The same chat name, history, instructions and memory remain visible.
- The default policy becomes Auto. Prefer the current host while it works.
- If Pro becomes unavailable, Air can run the next turn after a safe transfer.
- Show the current execution host and a brief switch status.
- Keep a specific-host option for work that needs that machine.
- Keep Create and Send available. If no eligible host can run, messages remain queued.

A failed public tunnel does not prove that a machine stopped. An outbound host connection to the coordinator can keep that host usable.

## C Proposed architecture

```flow LR
Client -> Coordinator: queue message
Coordinator -> [(Chat state)]: save and claim
Coordinator -> Pro: current runner
Coordinator --> Air: eligible standby
```

The coordinator must remain reachable independently of either Mac. Putting the only coordinator on Pro would prevent switching when Pro shuts down.

- **Session:** the stable chat identity, transcript, instructions and memory.
- **Attachment:** the current host worker and its native provider conversation.
- **Run:** one message execution, with a shared request receipt and exclusive claim.
- **Automation:** an existing scheduled Task that submits a Run for the chat.

A small cloud coordinator is my recommended shape. Cloudflare Durable Objects are one candidate for serialized state and storage. This is a proposal, not provisioned infrastructure. [Cloudflare documentation](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/)

## D What must be portable

| State | Current implementation | Required change |
| --- | --- | --- |
| Chat history, instructions and memory | Host-local files; partial client cache | Store an authoritative shared copy with ordered revisions |
| Native agent conversation | Provider ID and local transcript | Mirror full provider history, or rebuild a new provider binding from a complete LFG checkpoint |
| Files and credentials | Belong to each host | Resolve required files and tools before dispatch; keep credentials on authorized hosts |
| Runs and receipts | Locks and receipts inside one host | Share claims, receipt IDs and attempt outcomes |
| Jobs and notifications | Existing host-owned scheduled Tasks | Share scheduling ownership and delivery receipts if jobs must move too |

Claude documents cross-host resume through mirrored session storage or transferred transcript files. Its SDK offers a SessionStore adapter. Our runner currently launches the CLI directly, so adopting that interface requires a runner change and version checks. [Claude cross-host session guidance](https://code.claude.com/docs/en/agent-sdk/sessions#resume-across-hosts) [External session storage](https://code.claude.com/docs/en/agent-sdk/session-storage)

Conversation history does not carry the filesystem. SDK transcript storage also does not mirror file-checkpoint backups. Workspace transfer needs a separate mechanism. [Session semantics](https://code.claude.com/docs/en/agent-sdk/sessions) [Storage limitations](https://code.claude.com/docs/en/agent-sdk/session-storage)

## E Safe transfer

```sequence num
participants: Client, Coordinator, Pro, Air
note Coordinator: Previous turn and checkpoint are committed
Client -> Coordinator: Save next message with stable ID
Coordinator -> Coordinator: Confirm previous ownership ended
Coordinator -> Air: Grant a new execution version
Air -> Coordinator: Load committed context
Air -> Air: Restore provider state and run
Air -> Coordinator: Save result and context checkpoint
Coordinator --> Client: Stream committed result
Pro -> Coordinator: Rejoin after recovery
Coordinator --> Pro: Reject stale ownership
```

The coordinator grants one execution claim at a time. A newer claim invalidates older result writes. Hosts must stop accepting new work when they lose ownership.

Phone reachability alone must not authorize takeover. The original host may still be working through another network path.

Completed-turn checkpoints must reach shared storage before LFG marks them safe for transfer. Otherwise a new host could resume stale history. LFG must verify checkpoint durability; a mirror alone does not establish a safe transfer point.

## F Files, tools and interrupted actions

A new host must have the required model access, skills, MCP servers and files. A chat about general planning can move easily. A task editing a file stored only on Pro must wait for Pro or use a verified shared copy.

An old worker can still have a shell command or network request in flight. A lease cannot undo an action that already reached another system.

For an uncertain in-flight action, preserve the Run and reconcile its outcome. Do not automatically repeat an order, submission, file mutation or notification. Stable message IDs alone do not guarantee exactly-once external effects.

This is why I recommend completed-turn switching first. Keep composition available during recovery, while affected execution waits for a safe outcome.

## G Backend work and existing primitives

1. Add shared chat storage and provider checkpoints. Preserve the existing chat ID and editable context revisions.
2. Add host heartbeats and capability checks. Prefer the current eligible host to avoid needless movement.
3. Add transactional Run claims, ownership versions and shared request receipts. Enforce them on hosts, including direct API sends and scheduled Tasks.
4. Replace permanent client owner pinning with the authoritative current Attachment. Preserve the local offline queue and stable IDs.
5. Route portable chat jobs through the same Task primitive. Do not copy jobs into two independent schedulers.

LFG already has terminal-session transcript transfer checks and synced heartbeat leases. Reuse their host discovery and preflight ideas. A synced lease file alone does not provide an atomic claim across hosts.

Do not sync the whole .lfg folder. It contains machine identity, device registration and local scheduler state. Separate portable conversation data from machine data.

Upload an initial complete checkpoint before LFG enables portability for an existing chat. A partial phone cache cannot recover history that remains only on an offline host.

## H Evidence and next validation

Two isolated feasibility tests pass with nine assertions:

- Sending the same chat ID to a fresh host does not transfer the earlier conversation.
- Copying a complete LFG checkpoint and creating a fresh provider binding preserves chat identity, instructions, memory and prior text context.

These tests use temporary stores and fake providers. They do not prove actual provider transcript migration, tool-state continuity or distributed ownership.

The current text-import path has a 320,000-character guard and does not reproduce native tool history. Long chats need a provider transcript or a verified compacted checkpoint.

Before sign-off, test competing workers, stale ownership, lost acknowledgments and provider restoration. Also test missing files, interrupted tool actions, duplicate jobs and simultaneous client sends.

Reviewed source: the released chat-host-availability worktree. Relevant files are ChatSessions.swift, chat-sessions.ts, chat-native.ts, leases.ts, scheduled-tasks.ts and commands/serve.ts. The current release has host-local storage and owner pinning; this investigation changes no product code or deployments.

Renderer note: version 0.5.10 is available. Updating is optional and was not performed.
