# Opening a Space from an agent thread

Revise the existing LFG UI Map artifact, page Chat & Cua Spaces (Oct 21):
https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD

Eugene asks to design the flow of opening a Space, and whether chatting needs one.

## Product direction

Chat is always available. An agent thread, its instructions, history and memory exist independently of a desktop. API/MCP/file work can run through the agent runtime without allocating a desktop. A coding agent still needs a running process somewhere; do not claim chat has zero compute cost.

Show a short, concrete linked phone flow, with existing Mac/iPad patterns where needed:
1. Open an agent thread and chat with no desktop assigned. No empty desktop frame or startup spinner should dominate normal chat.
2. A user asks for browser/desktop work, or explicitly chooses Open desktop from thread tools. The agent requests a desktop and posts a quiet inline line.
3. Reuse an available compatible desktop immediately. Show the assigned desktop and a Watch action. If it is occupied, never steal it from another agent, pending sign-in, or human controller.
4. If all compatible desktops are occupied, start another automatically only if capacity checks pass. Show inline startup stages, then a live strip/preview. The composer stays usable throughout.
5. Memory guard: after allowing for the new desktop's estimated peak allocation and all pending startup reservations, the host must retain at least 4 GiB available physical memory. Also check the shared Linux VM's capacity and pressure. Reserve atomically so concurrent starts cannot double-book memory. Include VM startup/growth only as needed. Do not pretend each container has a fixed 1 GB cost.
6. If capacity or memory fails, queue the desktop action and show inline: Waiting for a desktop. Pro needs to keep 4 GB free. Independent API/file work and chat can continue. Recheck when memory recovers or a compatible desktop is released. Include retry/cancel, startup failure and host-offline recovery without a blocking sheet.
7. Watch opens the existing live view. Take control retains existing pause/handoff, fullscreen, keyboard, zoom/pan and landscape behavior. Done releases manual control. Giving a desktop back must preserve the thread; a later request can reuse or start a different desktop.

Keep the flat agent conversation list, newest activity first, dots only with no status sections. Keep draft approvals and sign-in cards inline. Reuse the existing visual language and canvas; preserve all unrelated boards and pages. Stay focused on opening, allocation and release rather than redesigning everything again. This is design only; no app source changes, commits, pushes or deployment.

## Native Cua versus LFG orchestration

Verified current Cua documentation:
- https://cua.ai/docs/spaces/guides/connect-your-agent — an existing host-side agent gets Cua skills/MCP, can create/manage/control Spaces on demand. Thus a host-side agent can chat before creating a Space.
- https://cua.ai/docs/spaces/reference/agents — agent_start launches a coding-agent CLI INSIDE a specified Space, with its MCP tools, event stream and follow-ups. Our current prototype uses this mode and requires a Space for that run.
- https://cua.ai/docs/spaces/guides/persistent-agents — named agents have a Space and a durable home in Cua Volume; only selected memory files persist. It does not promise that a live agent process migrates freely between Spaces.

The no-desktop-until-needed model assumes LFG hosts the agent runtime separately and exposes Cua through tools. Shared-pool scheduling, fair leases and the 4 GiB admission guard are LFG features to implement, not Cua behavior already supplied. Record this distinction in notes. Do not draw a promise that agent_start can run without a Space, nor that merely opening a stream creates a desktop.

Read desktop-allocation.md in /Users/eugenechan/dev/personal/lfg/.codex/design/cua-agent-threads for the detailed guard. Complete the revised boards, publish to the SAME canvas, render affected states, and read back to verify the saved result. Use native Artifact tools. Report page, board links and actual limitations. You are not alone in the repo; preserve others' changes.
