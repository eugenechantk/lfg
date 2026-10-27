# Provider continuity: recommendation

This is a design recommendation, not an implemented change. The current runner still starts fresh for every turn and disables provider transcript persistence.

## Current behavior

LFG sends standing instructions, editable memory, a rolling summary, recent turns, and the current message to a fresh Claude worker. It keeps the full original transcript on disk. It does not send the full unbounded history forever.

This gives LFG direct control over context and provider portability. It also makes LFG responsible for summarization and reconstruction that a native agent runtime already provides.

## Recommended direction

Keep the durable LFG Session and associate it with a saved provider conversation ID. Send new messages to that conversation. Let the provider runtime manage its working context and compaction. Keep tools disabled for this chat primitive.

Keep a worker warm while a chat is active if measurements justify it. Save the provider ID so the host can resume the same conversation after an idle shutdown or restart. Process lifetime must not define conversation lifetime.

LFG should continue to own user-visible identity, instructions, memory notes, host ownership, read state, status, request receipts, and a transcript projection. The provider keeps its native execution transcript. A binding records provider, conversation ID, and the settings revision applied to that conversation.

The native adapter must reconcile accepted requests after failures. It must not silently retry a turn whose delivery or completion is uncertain.

## What native sessions support

Claude's Agent SDK supports both a live multi-turn client and a disk-backed session ID that a new process can resume. Codex App Server exposes persistent threads, resume, and new turns.

Sources: [Claude session modes](https://platform.claude.com/cookbook/claude-agent-sdk-04-migrating-from-openai-agents-sdk), [Codex App Server](https://learn.chatgpt.com/docs/app-server).

## What staying alive does not solve

The model still needs conversation context for each inference. Claude documents that a resume sends conversation context again and can reuse an unchanged cached prefix. Cache lifetime and process lifetime are separate. A live process does not provide unlimited model memory.

Sources: [Claude prompt caching](https://code.claude.com/docs/en/prompt-caching), [Claude context management](https://code.claude.com/docs/en/how-claude-code-works).

## Instructions and memory still need an adapter

Keep instructions and editable memory outside the provider's compacted conversation. Ensure the latest revision reaches the next turn.

The installed Claude CLI documents system-prompt snapshots on resumed conversations. Its default can retain the original system prompt until compaction, despite different text on a later launch. Its `--system-prompt-snapshot off` option requests fresh rendering where supported. A resumed adapter must verify instruction changes rather than assume launch options refresh them.

Memory updates also need an explicit path into the live conversation. Reusing a session ID alone does not refresh user-edited memory notes.

Before replacing the current runner, verify multi-turn recall, instruction edits, conflicting memory corrections, compaction, crash recovery, request reconciliation, and empty-tool enforcement. Only then remove LFG's duplicate summary path for this adapter.

Source: installed `claude --help`, checked 24 October 2026; [resumed prompt behavior](https://code.claude.com/docs/en/prompt-caching#resuming-a-session).
