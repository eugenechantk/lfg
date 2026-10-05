# Grok → lfg sessions: let Grok hand work to Claude Code / Codex and take it back

Date: 2026-10-04 · Status: 15 tools live as launchd services; canonical doc is `docs/mcp-server.md`

## The idea in one line

Put one **remote MCP server** in front of lfg's existing session API. Grok (the app or
Treehole) adds it as a tool source, starts a Claude Code or Codex session on the Mac,
and checks back for the result.

```
 Grok (app / Treehole)
      │  MCP tool call
      ▼
 xAI servers ──HTTPS──▶ lfg-mcp.eugenechantk.me
                          │ Cloudflare tunnel
                          ▼
                     lfg serve  /mcp
                          │ existing API
                          ▼
                 claude / codex in tmux
```

Grok's **servers** make the call, not your phone. So the endpoint must be reachable from
the public internet, and it must carry its own auth.

## What already exists

- lfg already drives sessions over HTTP: `new`, `send`, `interrupt`, `messages`, `close`,
  `session-states` (see `.claude/skills/lfg-sessions/SKILL.md`).
- Treehole already wires a remote MCP server (gbrain) into the Grok realtime session.
  Tools come from `proxy-vercel/api/proxy.js` → `/session-config`. Adding lfg there is one
  more entry with an `allowed_tools` list.
- The Grok app supports custom MCP connectors (grok.com/connectors → Custom), paid tiers,
  since 2026-05-06.
- The xAI API's MCP tool takes `authorization` (bearer) and `headers`, so a Cloudflare
  Access service token can ride along.

## The hand-off must be async

A Claude Code task takes minutes. A Grok tool call must return in seconds. So the tools
do not wait for the work:

| Tool | Does | Returns |
| --- | --- | --- |
| `start_task(prompt, agent, cwd?)` | `POST /api/sessions/new` | `sessionId` at once |
| `get_task(sessionId)` | state + last assistant turn | `working` / `needs_input` / `done` + reply text |
| `send_to_task(sessionId, text)` | `POST …/send` | queued |
| `stop_task(sessionId)` | `POST …/interrupt` | ok |
| `list_tasks()` | sessions Grok started | ids, titles, state |

"Handing back to Grok" is `get_task` returning `done` with the agent's final message.
Grok then continues the conversation with that text.

How Grok learns it is done:

1. **Ask** — "is it done?" → Grok calls `get_task`. Works everywhere. Start here.
2. **Push** — lfg already pushes "needs input / finished" to the phone. You tap, tell Grok.
3. **Wait in-call** (Treehole only) — Grok polls `get_task` every ~10 s while it chats.

Optional later: `quick_task(prompt)` runs `claude -p` with a ~20 s cap, for one-shot
questions like "what's in my Downloads folder".

## Status 2026-10-04 (what is live)

- **Target is Grok Bot**, the SpaceXAI + Cursor "AI teammate" app (beta 2026-08-11), not
  grok.com. It connects to custom MCP servers from Cursor's backend with a name, a URL
  and optional **headers**, which you give it in chat.
- **Grok Bot cannot use Managed OAuth.** Its dynamic registration includes
  `cursor://anysphere.cursor-mcp/oauth/callback`, and Access rejects non-https
  redirects, so registration fails before sign-in (Cursor forum, 2026). Cursor staff's
  workaround is an Access service token sent as `CF-Access-Client-Id` /
  `CF-Access-Client-Secret` headers.
- Live pieces:
  - `scripts/lfg-mcp.ts` + `src/mcp-server.ts` on `127.0.0.1:8791`, one tool
    `list_tasks`. Log: `~/.lfg/lfg-mcp.log`.
  - Tunnel `lfg-mcp` (`~/.cloudflared/lfg-mcp.yml`) routes only `^/mcp$` to 8791.
    Runs unbound (through the VPN), because en0 → edge:7844 is blocked right now.
  - Access app **LFG MCP (Grok)** on `lfg-mcp.eugenechantk.me`: policy "Eugene SSH"
    (me@eugenechantk.me), Managed OAuth on (redirects `https://grok.com/*`, token 15m,
    grant 336h). AUD in `.env` as `LFG_MCP_ACCESS_AUD`.
  - Verified: unauthenticated POST → edge 401 with RFC 9728 `resource_metadata`, never
    reaches the Mac; discovery + DCR endpoints served; non-`/mcp` paths 404.
- Not yet durable: the server and tunnel run as background jobs of one Claude session,
  not launchd agents.

### Service token (done 2026-10-04)

Token "LFG MCP — Grok Bot" (expires 2027-10-04), reusable policy "LFG MCP Grok Bot
token" (Service Auth), attached to LFG MCP (Grok) only. Verified with curl through
Cloudflare: initialize, tools/list, list_tasks all 200 (23 sessions); wrong secret → 401;
the same token on lfg-pro → 403.

### Next step for Grok Bot

1. Create a service token "LFG MCP — Grok Bot" (Access controls → Service credentials).
2. Add a Service Auth policy for that token to the LFG MCP (Grok) app.
3. Tell Grok Bot: add MCP server `lfg`, URL `https://lfg-mcp.eugenechantk.me/mcp`,
   headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`.
4. Ask Grok Bot "what coding sessions are running on my Mac?" and watch
   `~/.lfg/lfg-mcp.log` for `POST /mcp tunnel → 200`.

The secret then lives in Cursor's backend and in that Grok Bot chat. Rotate it if the
chat is shared. Keep the tool set read-mostly until prompt-injection guards exist.

## Auth and reachability (updated 2026-10-04: target is the Grok app)

**Constraint:** the Grok app's Custom connector only does **OAuth 2.1 + PKCE**. It does
not accept a pasted bearer token (OpenMSP PR #15). Its dialog can ask for a Client ID +
scopes, and it uses dynamic client registration when the server offers it.

### Recommended: Cloudflare Access "Managed OAuth" (no OAuth code in lfg)

Access became a standard OAuth server for MCP clients on 2026-03-20. It does dynamic
registration (RFC 7591), PKCE, and RFC 8414/9728 discovery, then forwards the same
`Cf-Access-Jwt-Assertion` header a browser login gets.

```
Grok ──▶ lfg-mcp host ──401──▶ Grok
Grok ──register + PKCE──▶ CF Access
You  ──log in once──▶ CF Access
Grok ──token──▶ CF Access ──JWT──▶ lfg /mcp
```

Setup:

1. New hostname `lfg-mcp.eugenechantk.me` on the Pro tunnel, routing only `/mcp`.
2. A new Access application for it. Policy: your email only. Advanced → Managed OAuth on.
   Allowed redirect URIs: `https://grok.com/*` (confirm the real one on first connect).
3. lfg verifies `Cf-Access-Jwt-Assertion` on `/mcp` with the existing `src/access-jwt.ts`
   (already used for `/api/term`). This blocks anything that bypasses the edge.
4. grok.com/connectors → New → Custom → paste the URL → log in once in the popup.

Token life: access token 15 min, refreshed silently; refresh grant 1–2 weeks
(configurable), then Grok asks you to log in again.

Unproven: Grok's client against Access's Managed OAuth. The first connect attempt proves
or kills it. Plan pricing for Managed OAuth is not stated in the docs.

### Fallback: a small OAuth server inside lfg

If Grok and Access don't get along: lfg serves the discovery metadata, `/oauth/register`,
`/oauth/authorize`, and `/oauth/token` for one user, with PKCE S256. The authorize page
sits behind the normal Access browser login, so "who are you" still comes from Access.
About 200–300 lines, plus a token store.

### Rejected

- Static bearer token: the Grok form rejects it.
- Secret in the URL with no auth: works, but the key leaks into every log that records
  URLs, and anyone holding it can run an agent on your Mac.

## Risks

- **This is remote control of the Mac.** Anyone with the token runs an agent with your
  files and logins. Token in a secret store, rotate it, log every call.
- **Prompt injection.** Grok reads web and X content. A hostile post could steer Grok to
  call `start_task` with a harmful prompt. Mitigations: allowlist `cwd`, no tool that runs
  shell directly, label Grok-started sessions so they show in the lfg app, and optionally
  require a phone confirm before a Grok-started session runs.
- Grok-started sessions should fold under one parent ("Grok") in the lfg list, so they do
  not clutter real work.

## Recommended path

1. Set up the hostname + Access app with Managed OAuth, in front of a stub `/mcp` with one
   tool (`list_tasks`). Connect it in the Grok app. This proves auth before real work.
2. Build the five tools in `lfg serve` (prototype tier).
3. If step 1 fails, build the fallback OAuth server instead.
