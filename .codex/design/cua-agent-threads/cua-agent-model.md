# Cua agent models: verified documentation

Checked 2026-10-21 against Cua's current documentation. These are documented capabilities, not verification that every capability is present in our installed runtime.

## Agent outside a Space

An existing coding agent can connect to `cua daemon mcp`. The tools let it list, reuse or create Spaces, run guest commands, send files, obtain a desktop stream and call tools inside a Space. Several agents can connect to the same daemon. This supports LFG keeping its conversation runtime independent of desktop allocation. An agent still needs a running host or worker process; no desktop does not mean no compute.

Source: https://cua.ai/docs/spaces/guides/connect-your-agent

## Agent inside a Space

`agent_start` requires a Space and launches the coding-agent CLI as a detached process inside it. Cua supplies the Space's MCP tools and optionally additional MCP servers. Follow-ups continue the run; normalized events expose messages, tools, errors and turn completion. The run can survive a client disconnect. The reference explicitly says in-Space runs auto-approve tools, so inline approval cards in LFG do not by themselves enforce action approval.

Source: https://cua.ai/docs/spaces/reference/agents

## Persistence and sharing

Persistent agents have a named home in Cua Volume restored into their Space and saved after turns. Selected memory outlives runs and Space deletion; this is not live process migration or a promise that all credentials and full transcripts migrate. The guide also documents dedicated placement and shared placement in a named Space, requiring acknowledgment of the lack of isolation.

Sources: https://cua.ai/docs/spaces/guides/persistent-agents and https://cua.ai/docs/spaces/guides/connect-your-agent

## LFG choice

Use an agent runtime outside the desktop for chat, API/MCP and other work that needs no screen. Acquire a compatible Space through Cua tools only for desktop work. The current prototype's `agent_start` path instead runs inside a Space and must be changed to support this separation. Automatic pool allocation, exclusive control leases, the 4 GiB host reserve and enforced per-action approvals remain LFG responsibilities. Reusing a Space is documented; the complete allocation policy is our proposed orchestration.
