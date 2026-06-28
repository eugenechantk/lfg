# lfg iOS / iPadOS — MVP Feature Doc: Live Sessions

> **Goal:** a native SwiftUI iOS/iPadOS app that reaches **feature parity with the
> PWA's Live tab**, talking directly to an lfg host (this Mac) over **Tailscale**.
> **MVP scope = Live sessions only.** It includes one **backend prerequisite** —
> the *macOS host-enablement patch* (§8) — so CLI agents and the interactive
> prompt panel work with this Mac as the host. Auto agents, Terminal, Voice, and
> WhatsApp are explicitly out of scope (see §9).
>
> Grounded in `src/commands/serve.ts` (HTTP/SSE contract) and `web/src/App.tsx`
> (UI behavior). Screens referenced live in [`.claude/web-screen-captures/`](./web-screen-captures/).

---

## 1. Connection architecture (host = this Mac, over Tailscale)

The native app is a **pure client** of the lfg Bun server. There is no separate
backend to build — every Live feature is an existing HTTP/SSE endpoint.

### 1.1 The host
- lfg runs on this Mac: `bun run serve` → binds **`127.0.0.1:8766`** (loopback
  only; `LFG_HOST=127.0.0.1`).
- It is exposed to the tailnet by **`tailscale serve`** (not to the public
  internet):
  ```
  tailscale serve --bg --https=443 http://127.0.0.1:8766
  ```
  → reachable at **`https://<this-mac-magicdns-name>/`** (e.g.
  `https://eugenes-mac.tailXXXX.ts.net/`), **tailnet-only**, valid TLS via
  Tailscale's MagicDNS cert. Get the name with `tailscale serve status` /
  `tailscale status`.

### 1.2 The client
- **Base URL** = `https://<host-magicdns-name>/` (port 443, no `:8766` — tailscale
  serve fronts it). The app stores this as a single user-configurable setting.
- **Reachability requirement:** the iPhone/iPad must be **on the same tailnet**
  (Tailscale app installed + logged in + connected). No VPN session → host
  unreachable; the app must detect and surface this.
- **Auth model:** the lfg API is **unauthenticated by design** — the security
  boundary *is* the tailnet. The MVP sends **no tokens/cookies**; being on the
  tailnet is the credential. (Treat the base URL as sensitive; store in Keychain.)
- **TLS:** standard ATS-compatible HTTPS via the MagicDNS cert — no cert pinning,
  no exceptions needed.

### 1.3 Connection lifecycle the app must handle
- **Host discovery:** manual entry of the MagicDNS base URL in onboarding/settings
  (optionally a "paste from QR" later). Validate by `GET /api/sessions`.
- **Health/reachability banner:** distinguish *tailnet down* (no route) vs *host
  down* (route ok, connection refused) vs *ok*.
- **Reconnect:** SSE drops on network change/app resume — auto-reconnect with
  backfill (see §4).
- **Background:** iOS suspends sockets in background; on foreground, reconnect SSE
  and refresh the session list.

---

## 2. Data model (what the API returns)

### 2.1 `Session` (from `GET /api/sessions` → `{ sessions: Session[] }`)
| Field | Type | Use |
|---|---|---|
| `sessionId` | string (UUID) \| null | primary id; null = not yet resolved |
| `title` | string | card title (often the kickoff prompt; clip) |
| `agent` | `"aisdk"\|"claude"\|"codex"\|"codex-aisdk"\|"opencode"` | agent icon |
| `model` | string | model badge (sonnet, gpt-5.5, …) |
| `project` | string | repo/project name |
| `cwd` | string \| null | working dir |
| `status` | `"ok"\|"blocked"\|…` | drives state grouping |
| `statusReason` | `"model_unavailable"\|"out_of_credits"\|null` | paused banner |
| `statusDetail` | string | paused banner detail |
| `assignedUser` | string \| null | owner (filter/assign) |
| `lastUserText` | string | last user turn preview |
| `lastActivityAt` / `startedAt` | number | sorting/recency |
| `tmuxTarget` / `tmuxName` | string \| null | steering capability flags |
| `managed` | bool | lfg-owned session |

### 2.2 `Message` (transcript item; `msgWithHtml`)
Each message carries structured fields **plus prerendered `html`**. The PWA
renders the HTML. **Native decision (see §7):** either render the provided HTML in
a lightweight web view, or render from the structured fields natively. Messages
include: role (user/assistant/tool), text/markdown, tool-group summaries
("3 Read · 3 Bash · 6 results"), tables, and the "Actions:" footer.

### 2.3 `Prompt` (interactive selector; SSE `prompt` event / resolved server-side)
```
{ question: string,
  options: [{ index: number, label: string, selected: boolean, description?: string }],
  detail?: string }
```

### 2.4 `QueueItem` (outbound message delivery; SSE `queue` event)
`{ id, text, status: "delivered"|"queued"|"failed"|…, attempts, error? }`

### 2.5 `Repo` (`GET /api/repos` → `{ repos }`): `{ name, cwd }[]`
### 2.6 `User` (`GET /api/users`): emails from `LFG_USERS`
### 2.7 `Usage` (`GET /api/claude/usage`): `{ fiveHour:{pct,resetsAt}, sevenDay:{pct,resetsAt} }`

---

## 3. API contract — everything the Live MVP needs

Base = `https://<host>/`. All JSON unless noted.

| Capability | Method & path | Body → Response |
|---|---|---|
| List sessions | `GET /api/sessions` | → `{ sessions: Session[] }` |
| Repos (for picker) | `GET /api/repos` | → `{ repos: {name,cwd}[] }` |
| Users (for owner/filter) | `GET /api/users` | → users |
| Claude usage | `GET /api/claude/usage` | → usage (cached ~60s; may 502 if no creds) |
| **Create session** | `POST /api/sessions/new` | `{ cwd, prompt, model?, agent?, user? }` → `{ ok, sessionId, tmuxName, cwd, agent }` |
| Resumable list | `GET /api/sessions/resumable?limit=30` | → `{ sessions }` |
| **Resume session** | `POST /api/sessions/resume` | `{ sessionId, model?, user?, prompt? }` → `{ ok, sessionId, resumedFrom }` |
| Transcript (initial / paged) | `GET /api/sessions/:id/messages?limit=30` · `?full=1` · `?page=backward&before=<n>&limit=220` | → `{ id, messages[], total?, nextBefore? }` |
| **Multiplexed live stream** | `GET /api/live/stream?ids=<sid,sid,…>` (≤24) | SSE: `msg` / `prompt` / `busy` / `queue` + heartbeats |
| Single-session stream | `GET /api/sessions/:id/stream` | SSE (same event types) |
| **Send message** | `POST /api/sessions/:id/send` | `{ text }` → `{ ok, msg }` |
| **Answer prompt** | `POST /api/sessions/:id/answer` | `{ index }` → `{ ok }` |
| Dismiss prompt | `POST /api/sessions/:id/dismiss` | → `{ ok }` (Esc-cancels selector) |
| **Interrupt / stop turn** | `POST /api/sessions/:id/interrupt` | → `{ ok }` |
| **Switch model** | `POST /api/sessions/:id/model` | `{ model }` → `{ ok }` |
| **Rename** | `PUT /api/sessions/:id/title` | `{ title }` → `{ ok }` |
| **Assign owner** | `POST /api/sessions/:id/user` | `{ user\|null }` → `{ ok }` |
| **End session** | `POST /api/sessions/:id/close` | → `{ ok }` |
| Retry queued msg | `POST /api/sessions/:id/queue/:mid/retry` | → `{ ok, msg }` |

**Model allowlists:** Claude CLI `["fable","opus","sonnet","haiku"]`; ai-sdk
`["opus","sonnet","haiku"]`; codex/opencode validated by shape. Unknown Claude
model = hard 400 (the app must constrain the picker).

---

## 4. Realtime / SSE event model

`GET /api/live/stream?ids=...` is the heart of Live. The app subscribes to the
sessions currently on screen (≤24 ids) and receives:

| SSE `event:` | `data` | Meaning / UI effect |
|---|---|---|
| `msg` | `{ sid, m: Message }` | append/stream a transcript message for `sid` |
| `prompt` | `{ sid, prompt: Prompt\|null }` | show/clear the **interactive prompt panel** |
| `busy` | `{ sid, busy: bool }` | working spinner vs idle |
| `queue` | `{ sid, queue: QueueItem[] }` | outbound delivery status |
| `: hb` | — | heartbeat every 15s (liveness) |

**Backfill:** on connect, the stream replays the **recent ~40 messages** per
session before going live. For deep scrollback, page via
`GET /api/sessions/:id/messages?page=backward&before=…`.

**Native SSE:** implement an `EventSource`-style reader over `URLSession`
bytes/streaming (no native EventSource — use `URLSession.bytes(for:)` and parse
`event:`/`data:` frames). One stream for the visible set; resubscribe when the
visible set changes; reconnect on drop with fresh backfill.

---

## 5. Feature parity checklist (PWA Live → native requirement → API)

Every item below is **in MVP**. ✅ = must ship for parity.

### 5.1 Session list *(shots 01, 03, 12)*
- ✅ Empty state ("No running sessions" + New session CTA).
- ✅ **State grouping** (Idle / Working / needs-input) with counts — derived from
  `status` + live `busy`/`prompt` events.
- ✅ Session card: agent icon, clipped title, **model badge**, **live status dot**,
  ⋯ menu.
- ✅ Pull-to-refresh / auto-refresh of `GET /api/sessions`.

### 5.2 Create session *(shots 05–07)*
- ✅ Composer with task field.
- ✅ **Agent picker** — CLI vs ai-sdk × claude/codex/opencode (`agent` param).
- ✅ **Model picker** — list constrained per agent allowlist.
- ✅ **Repo picker** — from `GET /api/repos`.
- ✅ **Owner picker** — from `GET /api/users`.
- ✅ **Claude usage readout** — from `GET /api/claude/usage` (graceful when 502).
- ✅ Start → `POST /api/sessions/new`, then deep-link into the new session.

### 5.3 Resume *(shot 14)*
- ✅ "Resume a recent session" list (`/resumable`) with repo + relative time.
- ✅ Resume → `POST /api/sessions/resume` (claude-only; handle `alreadyLive`).

### 5.4 Transcript *(shots 02, 03)*
- ✅ Live streaming via SSE `msg`.
- ✅ Markdown, inline code, lists/headings.
- ✅ **Collapsible tool-call groups**.
- ✅ **Tables** (at minimum readable; copy/fullscreen are nice-to-have).
- ✅ "Actions:" footer.
- ✅ "Connecting to live transcript…" state.
- ✅ Infinite scrollback (`?page=backward`).

### 5.5 Steering
- ✅ **Send message** composer (`/send`) + queue status (`queue` event).
- ✅ **Interactive prompt panel** (`prompt` event) → tappable option rows →
  `/answer {index}`; **dismiss** (`/dismiss`). *(Requires §8 host patch to fire on
  this Mac.)*
- ✅ **Interrupt/stop** current turn (`/interrupt`).
- ✅ **Switch model** mid-session (`/model`).
- ✅ **Rename** (`PUT …/title`).
- ✅ **Retry** failed queued message (`/queue/:mid/retry`).

### 5.6 Lifecycle & ownership *(shot 04)*
- ✅ Session ⋯ menu: **Assign to** (`/user`), **Stop** (`/interrupt`), **End
  session** (`/close`).
- ✅ **Paused banner** for `status==="blocked"`: model-unavailable →
  "Resume on Opus" (`POST /model {model:"opus"}`); out-of-credits → explain.
- ✅ **User filter** (All / Unassigned / per-user) over the list.

### 5.7 Theming & layout *(shots 12–13, 16–17)*
- ✅ Light + dark (follow system, with manual override).
- ✅ iPhone: single-column stacked cards.
- ✅ **iPadOS: rail + tiled stage** — session rail + multi-column pinned
  transcripts; keyboard shortcuts (j/k/o/p/x/Enter/Esc) as a fast-follow.

---

## 6. Native UX additions (beyond raw parity, low-cost, high-value)
- **Push-style local notifications** when a watched session goes **needs-input**
  or **idle** (from the `prompt`/`busy` events while connected). True remote push
  needs a server change — out of MVP.
- **Haptics** on send / prompt-arrival / completion (parity with PWA haptics).
- **Handoff / deep links** (`lfg://session/<id>`).
- **Background-safe reconnect** + last-state cache so cold open shows something.

---

## 7. Key implementation decisions to make early
1. **Transcript rendering: HTML vs native.** The API ships prerendered `html` per
   message. Fastest path to parity = render that HTML (WKWebView per transcript or
   an attributed-string HTML pass). Cleaner long-term = render natively from the
   structured fields. **Recommendation:** start with HTML rendering to hit parity,
   migrate hot paths (bubbles, tool groups) to native incrementally.
2. **SSE client.** Build a small reusable `EventSource` over `URLSession.bytes`;
   one multiplexed stream for visible sessions.
3. **State store.** A single observable session store keyed by `sessionId`,
   reducing `sessions` snapshots + SSE deltas (`msg/prompt/busy/queue`).
4. **Base-URL/config** in Keychain; reachability via a lightweight `GET /api/sessions` ping.

---

## 8. Backend prerequisite — macOS host-enablement patch *(in scope)*

This Mac is the host, but lfg's process introspection is **Linux-only** (it reads
`/proc` and uses `pgrep -af`). Today that means: on a macOS host, **CLI/tmux**
claude/codex sessions are spawned and run, but are **not enumerated** by
`GET /api/sessions`, so they can't be shown or steered — and because only the
**ai-sdk** path lists (which renders `AskUserQuestion` as plain transcript text,
not a blocking `prompt` event), the **interactive prompt panel never fires**.

To make CLI agents + the prompt panel work with this Mac as host, the MVP includes
a **backend-only patch** (no app changes). It is gated to Darwin so **Linux
behavior is unchanged**.

### 8.1 What's `/proc`-bound today (the work surface)
| Location | Primitive | Linux impl | macOS replacement |
|---|---|---|---|
| `sessions.ts` `listClaudeProcs()` | list `claude`/`codex` procs **with full cmdline** | `pgrep -af claude` / `-af codex` | `pgrep -f claude` → pids, then `ps -o pid=,command= -p <pids>` (BSD `pgrep` lacks `-a`) |
| `sessions.ts:811,947` | **pid → cwd** | `readlink(/proc/<pid>/cwd)` | `lsof -a -p <pid> -d cwd -Fn` → parse `n…` line |
| `sessions.ts:814,950,1066` | **pid → start time** | `statSync(/proc/<pid>).ctimeMs` | `ps -o lstart= -p <pid>` (parse) |
| `sessions.ts:196` (`readPidSession`) | pid **starttime** for disambiguation | `/proc/<pid>/stat` field 22 | `ps -o lstart= -p <pid>` |
| `sessions.ts:1136` `ppidOf()` | **pid → ppid** | `/proc/<pid>/stat` field 4 | `ps -o ppid= -p <pid>` |
| `tmux.ts:109` | pid **comm/ppid** (pane→proc resolution) | `/proc/<pid>/stat` | `ps -o ppid=,comm= -p <pid>` |

### 8.2 Approach
- Add a small **`procinfo` platform shim** exposing 4 primitives:
  `listProcs(nameFilter) → {pid, cmd}[]`, `cwdOf(pid)`, `startTimeOf(pid)`,
  `ppidOf(pid)` (and a `comm` where needed).
- Implement each with `process.platform === "darwin"` → `lsof`/`ps`, else the
  existing `/proc` reads. Centralize so the call sites in `sessions.ts` / `tmux.ts`
  just call the shim.
- Keep results shaped exactly as today (ms epoch for start time, absolute cwd) so
  downstream logic — the newest-unclaimed-in-cwd heuristic, the aisdk
  phantom-child filter, prompt resolution — is untouched.
- **Perf note:** `lsof`/`ps` per pid is heavier than a `/proc` read. Batch where
  possible (`ps` accepts multiple `-p` pids in one call; `lsof -p` can take a
  comma list) and cache within a single `listSessions` pass.

### 8.3 Acceptance for the patch
On this Mac: starting a **CLI** claude or codex session makes it appear in
`GET /api/sessions` with correct `cwd`/`title`/`tmuxTarget`; driving it to an
`AskUserQuestion`/permission/plan selector emits a `prompt` SSE event; answering
via `POST /api/sessions/:id/answer {index}` advances it. Existing **ai-sdk**
sessions are unaffected. Running the same build on Linux is byte-for-byte
behavior-identical (Darwin branch never taken).

### 8.4 Fallback
If the patch slips, the app still ships against the **ai-sdk** path (list, create,
stream, send, interrupt, model-switch, rename, assign, close, usage all work). The
prompt/answer UI is built regardless and simply stays dormant until the patch
lands (or the host moves to Linux).

---

## 9. Out of scope (MVP)
- **Auto** agents (scheduling, findings, reports, actions).
- **Terminal** (PTY websocket).
- **Voice** (dictation/TTS/STT) — optional fast-follow; `/send` covers text.
- **WhatsApp** sidecar.
- **Runtime extensions / extra nav tabs.**
- Remote push notifications (needs server support).

---

## 10. Definition of done (MVP)
On a phone on the tailnet, pointed at this Mac, the user can: see all live
sessions grouped by state with live transcripts; create a session (agent/model/
repo/owner) — **including CLI claude/codex agents** — and land in it; resume a
recent session; send messages and see queue status; **answer an interactive
prompt (Postgres/SQLite/MySQL-style option rows) with one tap**; interrupt, switch
model, rename, reassign, and end a session; see the paused banner and recover;
filter by user; all in light/dark, with the iPad rail+stage layout.

This requires the **§8 macOS host-enablement patch** to have landed (CLI sessions
enumerate + `prompt` events fire on this Mac). Without it, every ai-sdk-path
feature still works and the prompt/answer UI is built but dormant.

### Build order
1. **§8 backend patch** (procinfo shim) — unblocks CLI sessions + prompt panel locally.
2. **Connection + session list + transcript stream** (§1, §3, §4, §5.1/5.4).
3. **Create / resume** (§5.2–5.3).
4. **Steering + lifecycle** (§5.5–5.6), incl. the prompt panel now that §8 is in.
5. **Theming + iPad rail/stage** (§5.7).
