# Revision: agent threads with a shared Space pool

Revise the completed Chat & Cua Spaces design on the EXISTING LFG UI Map canvas:
https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD
Existing page: Chat & Cua Spaces (Oct 21), id cua-spaces, version 92.
Existing sources: .claude/design/chat-cua-spaces/.

## Eugene's correction

The primary model is messaging different agents. Each agent has its own instructions or personality and a lasting conversation. Agents use a shared repository and a pool of Spaces to do their work. Spaces are resources, not the primary navigation or identity. Reuse an available compatible Space. Start another automatically when compatible Spaces are occupied by other agents.

Sign-in requests and drafted replies belong INLINE in the transcript, never in a sheet or a pinned blocking panel. They must not cover the conversation or stop unrelated agent work. The specific action that needs sign-in or approval waits; other independent work can continue. Nothing sends without the user's approval. Show waiting, answered, expired and completed inline states. An inline sign-in card may open the necessary secure login surface on explicit tap; never put credentials directly into the agent conversation.

## Design the recommended flow

Message opens agent threads, with agent name, identity, personality/instructions summary and readable activity/unread states. Create an agent or open an existing thread, give it work, and see results inline. Reuse existing Sessions/Tasks components, typography, spacing, soft-blue user bubbles and dark appearance. Agent setup can use existing creation patterns, but sign-in and draft cards stay inline.

Thread identity, instructions and history persist independently of Space allocation. Show subtle contextual desktop/Space access only when useful. Users should not select/create a Space before messaging an agent. Preserve live watch, takeover, portrait/landscape, zoom/pan, right-click and keyboard controls already designed. Show who currently controls a shared desktop. Human takeover pauses the current controller and blocks other agents from acquiring that desktop until Done releases it.

Define and illustrate the allocation states: reusing an available desktop; starting a desktop because all compatible ones are busy; waiting at a capacity limit; an offline host; and switching desktops without losing the thread. Sharing a repository does not mean simultaneous cursor control: one desktop has one exclusive controller at a time. CLI/filesystem work can proceed separately where safe. A Space waiting on sign-in must not be handed to another agent in the middle of that sign-in. Account and folder permissions must remain scoped; do not imply unrelated agents automatically share private accounts. Distinguish shared project files from each agent's instructions and memory. Mention isolated git worktrees as an implementation consideration in design notes, not product jargon.

Include phone, narrow Mac, wide Mac and iPad adaptations. Rework the current page coherently rather than creating another canvas or leaving contradictory Space-first navigation. Preserve all unrelated canvas pages and boards. Use the Apple HIG skill for native navigation, inline feedback and accessibility where relevant. This is design work only. Do not change app source, commit, push, deploy or touch production services. You are not alone in the repo; preserve other edits.

Deliver rendered, linked artboards on the same shared canvas and update local design notes. Read back the saved page to verify persistence, and render/check the changed boards. Report the page link, board count, reused patterns, allocation rules, and any actual tool limitation. If native Artifact tools are unavailable in this CLI environment, state that clearly; do not invent an undocumented API or silently substitute a separate canvas. Complete local revised artboards before reporting that blocker.
