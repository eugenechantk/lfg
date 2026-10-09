# lfg MCP server (Grok Bot → lfg sessions)

A remote MCP server that lets an assistant on someone else's servers — today
**Grok Bot** (SpaceXAI + Cursor) — list, follow, start, steer, answer, stop and
close the Claude Code / Codex sessions lfg manages, and get the files those
sessions mentioned or wrote (nothing else on the Mac) — either read into the
conversation (`read_file`) or downloaded through an expiring link (`download_file`).

## Shape

```
Grok Bot (Cursor backend)
   │ POST /mcp + CF-Access-Client-Id/Secret
   ▼
Cloudflare Access app "LFG MCP (Grok)"
   │ tunnel lfg-mcp (routes only ^/mcp$)
   ▼
scripts/lfg-mcp.ts  127.0.0.1:8791
   │ loopback HTTP
   ▼
lfg serve  127.0.0.1:8766  →  claude / codex in tmux

caller's HTTP GET  https://lfg-files.eugenechantk.me/dl/<token>/<name>
   │ no Access app on this host; tunnel routes only ^/dl/
   ▼
scripts/lfg-mcp.ts → the one file that token names, until it expires
```

- **Separate process, separate tunnel, separate Access app.** The MCP server is
  not part of `lfg serve`, so changing it never restarts lfg. Its tunnel can only
  reach port 8791, so no policy mistake on `lfg-mcp.eugenechantk.me` exposes the
  full lfg API, the terminal or SSH.
- **Two auth layers.** Access rejects anything without a valid credential at the
  edge. The server then verifies `Cf-Access-Jwt-Assertion` for this app's AUD
  (`LFG_MCP_ACCESS_AUD` in `.env`) with `src/access-jwt.ts`; tunnelled requests
  without it, or with verification unconfigured, get 401. Loopback requests pass.
- **Transport:** Streamable HTTP, stateless. One JSON-RPC message per POST,
  `application/json` replies, 202 for notifications, 405 for GET/DELETE.
  Protocol versions 2025-11-25, 2025-06-18, 2025-03-26.

## Auth: why a service token

Grok Bot's custom MCP servers take a URL plus optional headers. Its OAuth path
registers a `cursor://` redirect, which Access Managed OAuth rejects (https
only), so Grok Bot uses an Access **service token** ("LFG MCP — Grok Bot",
expires 2027-10-04) through a Service Auth policy attached to this app only.
Managed OAuth is also on (redirects `https://grok.com/*`) for grok.com
connectors, which only do OAuth + PKCE; it has not been tried from grok.com.

Rotate: Zero Trust → Access controls → Service credentials → refresh the token,
then give Grok Bot the new headers. The old secret stops working at once.

## Tools (`src/mcp-lfg-tools.ts`)

| Tool | lfg endpoint | Notes |
| --- | --- | --- |
| `list_sessions` | `GET /api/sessions`, `/resumable` | state filter, closed optional; hides autopilot plumbing |
| `get_session` | sessions + `messages?limit=40` + `queue` | state, waiting question, undelivered sends, latest reply |
| `wait_for_session` | polls `/api/sessions` every 4 s | ≤55 s; 8 s grace so a fresh send can start |
| `get_transcript` | `messages?page=backward` | `limit` counts conversation lines; `before` cursor |
| `search_sessions` | live list + `/resumable?q=` | closed search can take ~15 s |
| `list_folders` | `GET /api/repos` | |
| `start_session` | `POST /api/sessions/new` | default `~/dev/inbox`; folder must be under ~/dev, ~/inbox, Desktop, Downloads or Documents; `~/dev/inbox/<name>` is created |
| `send_message` | `POST …/send` | absorbed mid-turn when busy; resumes a closed session |
| `answer_question` | `POST …/answer` | by number or label; refuses phone sign-in prompts |
| `interrupt_session` | `POST …/interrupt` | |
| `close_session` | `POST …/close` | `destructiveHint` |
| `resume_session` | `POST /api/sessions/resume` | |
| `list_session_files` | `messages?full=1` | files the session's whole transcript names, newest first |
| `read_file` | `messages?full=1` + local read | content into the conversation: text ≤500 KB; images as MCP image content (downscaled to a ≤2048 px JPEG by `sips` over 4 MB); PDFs via the PDFKit helper (below); other binaries → "use download_file" |
| `download_file` | `messages?full=1` + `DownloadStore` | any file type; returns `https://lfg-files.eugenechantk.me/dl/<token>/<name>`, valid 60 min by default (5 min–24 h) |

Every `tools/call` is logged with its arguments (clipped to 300 chars) to
`~/.lfg/lfg-mcp.log` — the audit trail of what the remote assistant asked for.

## File policy (`src/mcp-file-policy.ts`)

**Only files in the session.** `read_file` takes a `session_id` and reads a path
only if that session's transcript names it — in a reply or a tool call — as a
home-folder path (absolute or `~/`) or a temp path (`/tmp`, `/private/tmp`,
`/var/folders`). Both sides are resolved through symlinks, so a link the session
never named can't stand in for a file it did. There is no folder browser.

Even a mentioned file is refused when it is:

- in a hidden folder directly under `$HOME` (`~/.ssh`, `~/.cloudflared`,
  `~/.claude`, `~/.codex`, …), or in any hidden folder deeper down other than
  `.claude .codex .agents .github .worktrees .vscode` (so `.git` is out);
- named like a secret: `.env*` and `*.env`, keys and certificates, `*.private.*`,
  `auth.json`, databases, and the whole words secret(s), credential(s), creds,
  password(s), passwd, token(s), cookie(s) in anything that isn't a source file
  (`cookies.txt` is refused, `tokens.ts` isn't). Whole words, because substring
  matching refused `PaperBridge_company_secretary_form_draft.pdf` on 2026-10-05.

## Download links (`src/mcp-downloads.ts`)

`download_file` is how the computer calling the MCP gets the exact file: it
fetches the returned URL with a plain GET. The URL is a capability — 32 random
bytes, no login — so Grok Bot's backend or Eugene's phone can open it directly,
and anyone else holding it can too until it expires. Defaults keep that window
short (60 min, max 24 h).

- **Separate hostname, no Access.** `lfg-files.eugenechantk.me` has no Access
  app; the tunnel routes only `^/dl/` there, and `/mcp` is never reachable on it
  (404 at the tunnel, and the server would still demand the MCP app's JWT).
- **Store:** `~/.lfg/lfg-mcp-downloads.json` (0600) keyed by SHA-256 of the
  token, so the file on disk holds no live links; links survive restarts.
- **At download time** the file must still be a regular file at the same
  resolved path — swapping it for a symlink after the link was made returns 410.
- Response headers: `Content-Disposition: attachment` (`?view=1` → inline),
  `Cache-Control: private, no-store`, `X-Robots-Tag: noindex`,
  `Content-Security-Policy: sandbox`. Every download is logged
  (`download <token prefix>… <name> (<bytes>) from <ip>`).

## PDFs (`scripts/pdf-extract.swift`, `src/pdf-extract.ts`)

`read_file` on a `.pdf` runs a small PDFKit helper, compiled once into
`~/.lfg/cache/pdf-extract` (rebuilt when the source is newer; warmed at server
start). The reply is text first: every AcroForm field with its filled value
(PDFKit's page text leaves these out), then each page's text. A flattened form's
values are page text, so they come through either way. Page renders (≤1200 px
JPEG) are sent only for pages with no text (scans) by default, because a 10-page
form with images is a ~3 MB reply and the client's size limit is unknown;
`include_images: true` sends them within a 2.4 MB budget. `first_page` /
`max_pages` (default 10, max 30) pick the range.

What this does and doesn't buy: it stops direct reads of arbitrary files. It does
not stop an assistant from asking a session to name or print a file — the agents
run with full permissions, so `send_message` is already a way to reach anything.
The real boundary is the service token.

`checkPath` + `defaultRoots` remain only to limit the folders `start_session` may
start in (`~/dev`, `~/inbox`, Desktop, Downloads, Documents).

## Operations

- Services (launchd, KeepAlive): `dev.omg.lfg-mcp` (server, cwd = this repo, so
  Bun loads `.env`) and `dev.omg.lfg-mcp-cloudflared` (tunnel config
  `~/.cloudflared/lfg-mcp.yml`). Pro only; Air sessions are not reachable.
- Deploy a code change: `launchctl kickstart -k gui/$(id -u)/dev.omg.lfg-mcp`.
- Logs: `~/.lfg/lfg-mcp.log` (server; `client <name>` lines show who connected),
  `~/.cloudflared/lfg-mcp.log` (tunnel).
- Testing a NEW hostname from this Mac: do not `dig` it before the DNS record
  exists. The VPN answers all port-53 DNS itself and caches NXDOMAIN for ~30 min
  (it did for `lfg-files`). Check with DNS-over-HTTPS
  (`curl -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=<host>&type=A'`)
  and test with `curl --resolve <host>:443:<ip>`.
- The tunnel runs through the default route (the VPN) because en0 → edge:7844 is
  blocked by the VPN's kill switch; MCP traffic is small.
- `cloudflared tunnel route dns` obeys `tunnel:` in `~/.cloudflared/config.yml`
  over the name you pass. Always `cloudflared tunnel --config <yml> route dns
  --overwrite-dns <uuid> <host>` and read the `tunnelID=` it prints.

## Risks

- The service token is remote control of the Mac's agents, which run with
  `--dangerously-skip-permissions`. It lives in Cursor's backend and in the Grok
  Bot chat it was pasted into.
- Prompt injection: an assistant that reads web pages or posts can be steered to
  call these tools. The server instructions tell it to act only on Eugene's
  requests, but that is advice, not enforcement.
