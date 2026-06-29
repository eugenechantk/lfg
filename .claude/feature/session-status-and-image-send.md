# Fix: stale session status + failed image sends

Tier: Product (shipping server + iOS client).

## Issue 1 — session stays "Working" after it's actually done

### Symptom
A finished session keeps showing as running/working for a while. Sending to it then
shows a "pending" bar instead of sending directly, even though the agent is idle.

### Root cause (verified)
- `busy` on the iOS client is populated **only** from the `/api/live/stream` SSE
  `busy` events (`SessionStore.apply` → `busy[sid] = value`). The REST session list
  (`listSessions`) carries `status` (ok/blocked) but **no busy field**.
- The SSE stream is **capped at 24 ids** (`serve.ts` `.slice(0, 24)` and
  iOS `ensureStream` `prefix(24)`). The host currently has **34 tmux sessions**.
- The server emits `busy` only **on change** (`bsig !== lastBusy`). So a session that
  was busy, then dropped out of the top-24 live window (or the window churned as other
  sessions became more active), never receives its `busy=false` — the client's
  `busy[sid]` stays `true` indefinitely. `group(for:)` then keeps it under "Working",
  and `sendWithAttachments` computes `idle = prompts==nil && busy != true` = false →
  shows the pending bar.
- Pane-based `isBusy` itself is correct: idle panes (collapsed "✻ Baked for 3m 56s"
  summary, no token meter, no "esc to interrupt") read not-busy; running panes read busy.
  The bug is **delivery/coverage of the busy signal**, not its computation.

### Fix
Make `busy` authoritative from the periodic REST refresh so un-streamed sessions can't
get stuck:
- **Server**: add a `busy` field to the `Session` returned by `listSessions`, computed
  cheaply from transcript mtime freshness (`now - lastActivityAt < window`) — no extra
  `tmux capture-pane` spawn (listSessions already stats the transcript). Same tradeoff
  the code already accepts for bare CLI sessions (`BARE_BUSY_WINDOW_MS`).
- **iOS**: on each `refresh()` (3s), seed `busy[sid]` from `Session.busy` for sessions
  **not** in `streamedIDs`. Streamed sessions keep their accurate pane-based SSE busy as
  an override. This corrects any session that fell out of the live window, including one
  that finished right as it was dropped.

Net: SSE stays the fast, accurate path for the focused + top-24 sessions; the REST
baseline guarantees nothing stays stuck "Working" beyond one 3s refresh.

### Additional root cause found during implementation (2026-06-29)

The doc above blamed only the 24-cap, but the *in-window* sessions were stuck too.
Second bug: `busy` is a **delta-only** signal — the multiplexed `/api/live/stream`
emits a `busy` event only when the value changes vs a per-connection `lastBusy`
map that defaults to `"0"` (idle). The priming loop calls `pollOne` with that map
empty, so an **already-idle** session sends NO `busy` event on (re)connect. The
client churns/reopens this stream constantly (its id set is reranked by activity
and capped at 24), and the client's `busy[sid]` is sticky across reconnects — so a
session that finished while the client held a stale `busy=true` never received the
`false` and stayed on "Working" even while in-window.

### What was implemented + verified
- **Server `listSessions`** (`src/sessions.ts`): added `busy` to `Session`.
  Pane sessions → transcript-freshness (`REST_BUSY_WINDOW_MS = 12s`); aisdk/codex
  harnesses → accurate registry `busy`. Verified live: REST now returns `busy` on
  all 37 sessions; both stuck sessions read `busy=false`.
- **Server live stream** (`src/commands/serve.ts`): seed `lastBusy` with a sentinel
  before the first `pollOne` so the initial poll always emits an explicit busy
  snapshot (fixes the in-window/reconnect case).
- **iOS** (`Models.swift` + `SessionStore.swift`): added `busy: Bool?` to the model;
  `refresh()` seeds `busy[sid]` from REST for non-streamed sessions, SSE overrides
  for streamed ones.
- **End-to-end verified** in the simulator app: header shows "1 running"; the two
  previously-stuck sessions ("set up testflight…", "issues with the status…") now
  sit under IDLE. Screenshot evidence captured.

## Issue 2 — sends to idle sessions fail, especially with image attachments

### Root cause (verified)
- iOS uploads each attachment, then sends `([typed] + paths).joined(separator: "\n")`
  (`SessionStore.swift:601`) — so an image message is multi-line: `text\n/path/img.png`.
- Server delivery types it with `tmux send-keys -t … -l <text>` (`tmuxType`). An embedded
  `\n` is sent as a **real line break**. Verified against `cat`: `"hello world\n/path"`
  arrived as two lines — the first line submits immediately.
- In the Claude TUI this submits the text alone, leaving the path stranded in the
  composer. `deliver()`'s needle check (full normalized text) never matches, it retypes
  3×, and ends `failed: "message never left the input box after retries"` — while the
  agent may have received several partial messages.

### Fix
Handle multi-line message text in the send path so it lands as a single composer entry:
- **Server (primary, general)**: in the send path, when `text` contains a newline, insert
  it via tmux **bracketed paste** (`tmux load-buffer -` + `tmux paste-buffer -p -t …`)
  instead of `send-keys -l`. The Claude TUI treats bracketed-paste newlines as soft
  newlines (no premature submit), then a single `Enter` submits the whole thing. Fixes
  image sends and genuine multi-paragraph messages alike.
  **Must verify against the real Claude TUI** (not just `cat`) — bracketed paste is an
  application-level behavior.
- **iOS (cheap safety net)**: join attachment paths with a space, keeping `typed` and the
  paths on one line, so the common image case never relies on multi-line handling.

## Verification plan
- Issue 1: with >24 live sessions, let one outside the window finish; confirm it flips to
  Idle within ~3s in the list and a send goes straight through (no pending bar).
- Issue 2: send a message with an image to an idle session; confirm one user turn lands
  with the image, agent responds, queue shows delivered (not failed).
