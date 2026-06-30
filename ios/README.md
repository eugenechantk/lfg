# lfg — Native iOS / iPadOS client

A native SwiftUI client for the `lfg serve` backend. It lets you start, watch,
steer, and answer your Claude Code / Codex agent sessions from your phone or
iPad, streaming live over your Tailscale tailnet. It is a pure client — it
spawns no agents itself; the host (`lfg serve`) owns all agent processes.

Spec: [`../.claude/ios-mvp-live-sessions-feature-doc.md`](../.claude/ios-mvp-live-sessions-feature-doc.md) ·
Verification: [`../.claude/ios-mvp-verification-report.md`](../.claude/ios-mvp-verification-report.md)

---

## What it does

The app gives you the **Live sessions** surface from the lfg web UI, as a native
app with push notifications:

- **Session list** — every live agent session on the host, grouped by status
  (*Needs you · Paused · Working · Idle*) or by directory. A top badge shows
  connection health and how many sessions are running. Filter by assigned user
  (All / Unassigned / a teammate).
- **Live transcript** — open a session and watch its transcript stream in real
  time: assistant prose (GFM markdown), collapsible thinking blocks, tool calls,
  and inline media (images, video, PDFs, file cards) served from the host.
- **Steer a session** — send a message, switch the model mid-run, stop a running
  turn, rename, assign to a user, or end the session. Multi-line messages and
  image attachments are supported.
- **Answer interactive prompts** — when a CLI agent surfaces a blocking selector
  (AskUserQuestion, permission, plan approval, trust), it appears as a tappable
  prompt panel you answer with one tap.
- **Start / resume sessions** — pick an agent, model, and working directory, then
  your first message kicks off a new session. Resumable (closed) sessions can be
  revived.
- **Push notifications** — get a push when one of your sessions finishes a turn
  or needs your input; tapping it deep-links straight to that session.

### UX behaviors worth knowing

These are the non-obvious interactions the app implements deliberately:

- **Optimistic sends.** Your message appears as a user bubble the instant you
  hit send — before any network round-trip. An *idle* session shows it as a
  finished bubble immediately; a *busy* session shows a muted "Sending…" bar in
  a strip above the composer until the agent picks it up; a *wake-up* send to a
  reaped session shows a muted "Waking session…" bubble until the server resumes
  the conversation. Each optimistic bubble is reconciled away once the real user
  turn lands in the transcript. Failed sends surface a **Retry**.
- **Sends outlive the view.** A send is owned by the store under a background-task
  assertion, so leaving the session, popping the nav stack, or backgrounding the
  app the instant after tapping send never drops the message.
- **Optimistic session creation.** Starting a session navigates to it instantly
  with a placeholder id and a kickoff bubble; the real `POST /new` runs in the
  background and the placeholder is remapped to the server id once it lands.
- **Smart auto-scroll.** The transcript auto-follows new messages only while you
  are at the bottom — scroll up to read history and it won't yank you back down.
  Double-tap the top third to jump to the start, the bottom third to jump to the
  latest.
- **Deep-link resolution.** A tapped notification cold-launches into the session
  even if its pane was reaped — the app reconnects, refreshes, and (if closed)
  pulls the session from the resumable list so the transcript still opens. The
  push payload embeds a compact session snapshot so the screen renders instantly
  before the refresh completes.
- **Resilient live stream.** A watchdog drops a silently-stalled SSE connection
  (backgrounded app, dropped radio, black-holed socket) after 35s and reconnects;
  a clean server-side close also triggers a reconnect via the 3s poll.

---

## Architecture

```
LFGApp (entry)
 ├─ AppSettings        persisted host URL, default owner, group mode, user filter
 ├─ SessionStore       @Observable single source of truth — reduces REST snapshots
 │                     + SSE deltas into per-session state the views render
 ├─ PushManager        APNs lifecycle (permission → token → register → tap routing)
 └─ RootView           adaptive NavigationSplitView (iPhone stack / iPad rail+stage)
     ├─ SessionListView    grouped/filtered list + connection banner
     ├─ SessionDetailView  live transcript, composer, prompt panel, toolbar actions
     ├─ NewSessionView     agent/model/dir selectors + kickoff composer
     └─ SettingsView       host config, notifications, directories

LFGCore (SPM package — no UIKit, fully unit-tested)
 ├─ Models       Codable API types (lenient decoding — every field optional)
 ├─ LFGClient    stateless async HTTP/SSE client (Sendable)
 ├─ SSEParser    incremental SSE parser + frame → LiveEvent decoder
 └─ Push         pure push-payload parsing + registration state machine
```

- **`project.yml`** — XcodeGen is the source of truth for the Xcode project. Edit
  this, not the `.xcodeproj`, then run `xcodegen generate`.
- **`LFG/`** — the SwiftUI app target (`com.eugenechan.lfg`).
- **`LFGCore/`** — an SPM package holding all the non-UI logic so it can be unit
  tested without a simulator. Dependency: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)
  (in the app target) for GFM rendering.

**Why the split:** everything that can be reasoned about without Apple's runtime
(API shapes, SSE parsing, push payload parsing, state machines) lives in
`LFGCore` with tests; the app target is the thin, side-effecting SwiftUI shell.

---

## Backend connection

The app talks to `lfg serve` over plain HTTP + Server-Sent Events. There is **no
auth** — the security boundary is your Tailscale tailnet (the lfg API is
unauthenticated by design; keep the device on the tailnet).

**Set the host in-app** (Settings, or first-run Connect screen):
- **Simulator:** `http://127.0.0.1:8766` (simulators share the Mac's loopback).
- **Real device:** the host's Tailscale MagicDNS https URL (tailnet-only).

### Endpoints used (`LFGCore/LFGClient.swift`)

| Purpose | Call |
| --- | --- |
| List sessions (3s poll + reachability) | `GET /api/sessions` |
| Transcript / pagination | `GET /api/sessions/:id/messages` |
| Outbound queue (reconcile fallback) | `GET /api/sessions/:id/queue` |
| Create / resume | `POST /api/sessions/new`, `/resume` |
| Send / answer / dismiss / interrupt | `POST /api/sessions/:id/{send,answer,dismiss,interrupt}` |
| Model / title / owner / close | `POST|PUT /api/sessions/:id/{model,title,user,close}` |
| Retry queued message | `POST /api/sessions/:id/queue/:mid/retry` |
| Upload image (returns host path) | `POST /api/sessions/:id/upload` |
| Resumable sessions | `GET /api/sessions/resumable` |
| Dirs / repos / users / usage | `GET /api/{dirs,repos,users,claude/usage}` |
| Push register / unregister | `POST /api/push/{register,unregister}` |
| Serve a host file (images/PDF/etc.) | `GET /api/file?path=…` |
| **Live stream (SSE)** | `GET /api/live/stream?ids=…` |

**Live stream:** subscribes to up to 24 sessions (the focused session is always
included), the server backfills ~40 recent messages per session then streams
`msg` / `prompt` / `busy` / `queue` deltas plus a `: hb` heartbeat every 15s.
SSE blank lines are the dispatch boundary, so the client splits raw bytes on
`\n` itself (`URLSession.bytes.lines` swallows the blanks). See
`SessionStore.ensureStream` / `LFGClient.liveStream`.

**Push:** the server sends `{ aps, sid, kind, session }`. A Debug build talks to
the APNs **sandbox**, Release (TestFlight/App Store) to **production** — driven
by the `aps-environment` entitlement and reported to the server on register so
it pushes to the right APNs environment. The host needs APNs configured
(`LFG_APNS_*`).

> **macOS host note:** CLI/tmux agent enumeration and the interactive prompt
> panel rely on the `src/procinfo.ts` shim because macOS has no `/proc`. On Linux
> it works unchanged.

---

## Build & run

Use **FlowDeck** for all build/run/test/simulator/device work — never raw
`xcodebuild`/`simctl`/`devicectl`.

```bash
cd ios && xcodegen generate     # regenerate the Xcode project from project.yml
# from repo root:
flowdeck build
flowdeck run
```

Then set the server URL in-app (see **Backend connection** above).

### Tests

```bash
cd ios/LFGCore && swift test    # Models, SSEParser, Push — pure unit tests, no sim
```

`swift test` is fast and deterministic (no simulator). UI-affecting changes must
additionally be verified live in the simulator/device — a green unit suite is not
"verified" on its own (see the project memories on verifying the real seam).

---

## Project facts

| | |
| --- | --- |
| Bundle id | `com.eugenechan.lfg` (display name **lfg**) |
| Deployment target | iOS 17.0 (iPhone + iPad, `TARGETED_DEVICE_FAMILY 1,2`) |
| Swift | 6.0, **strict concurrency: complete** |
| Push subsystem / logger | `dev.omg.lfg` |
| Project generator | XcodeGen (`project.yml`) |
| Dependencies | LFGCore (local), MarkdownUI |
