# lfg — Multi-Host-First Rearchitecture Proposal

**Status:** proposal, v2 (planning only — nothing implemented)
**Date:** 2026-07-09
**Worktree:** `multihost-rearchitecture`
**Inputs:** full server + client architecture audits (two independent code reviews), 8 diagnosis docs, this session's live network debugging, the original `multi-host.md` design doc.
**v2:** connection stability and background persistence promoted to first-class sections (§4, §5).
**v3:** audio-based "Stay Connected" mode removed (Eugene: no audio involvement). Background design is Strategy A only, upgraded: background-URLSession outbox sends + Live Activities (push-to-start) as the live surface for running sessions.
**v4:** phases reordered per Eugene — connectivity first. Track A purely connectivity; Track B reliability/offline.
**v5:** the "transport hardening on current architecture" bridge phase dissolved into the journal phase (Eugene: implementation is hours, not weeks — the bridge was the plan's only throwaway work). Phase 0 marked landed (commits `3b8887e`, `9fc4ec0`, live-verified on the Pro). Track A = 0 ✅, 1 (connectivity core), 2 (background). Track B = 3–7.

---

## 0. The one-paragraph version

lfg has one durable substrate (transcript files) and builds everything else — liveness, delivery, sends, unread — as *ephemeral, per-connection, in-memory derivations* of it. That was tolerable with one host and an always-foreground client. Multi-host was added as a client-side fan-out **without revisiting the core** (explicit in `multi-host.md`: *"client-side fan-out … backend nearly unchanged"*). Every symptom — phantom disconnects, missed messages, blank app offline, stuck sends — is downstream of that, and each has been patched where it surfaced: the audit counts **~35 patches** (17 client, 18 server). The fix is structural: **make connections cheap to lose and instant to resume (§4), make background continuity real within iOS's rules (§5), and make the durable substrate complete — a journal with cursors per host, a persistent store with an outbox on the phone (§6–7)** — and let the workarounds fall out.

---

## 1. Symptoms → root causes

| Symptom | Root cause (verified) |
|---|---|
| "Hosts disconnect when I close the app" | iOS suspends the process and freezes its sockets — no app can hold a background socket (§5 for what *can* be done). The actual bug was recovery cost: foreground reconnect took 15–18s (fan-out barrier awaiting a black-holed offline peer before `ensureStream()`; measured `total=15.004652s` against the sleeping Pro). |
| "Disconnects even while I'm on the app" | Three causes, §4 taxonomy: **self-inflicted stream teardowns** (biggest, entirely fixable), genuine cellular path flaps (measured endpoint churn; reducible), and **misreporting** (transient blips shown as "host unreachable" when the host was never down). |
| "New messages for idle sessions not picked up" | (a) server `lastActivityAt` = transcript file mtime, and Syncthing rewrites mtimes hourly (measured +3600.000s, content identical) — the signal is corrupted at the source; (b) sessions outside the SSE 24-id window get **zero** live events; (c) backfill replays only the last 40 messages — longer gaps silently lost; (d) client read-state compares device clock vs host clock and never clears `focusedID`, permanently exempting the last-viewed session from unread. |
| "Sends get stuck / lost" | Server send queue is **in-memory** — restart silently drops undelivered messages. Delivery confirmed by tmux screen-scrape (5 diagnosis docs of patches); client papers over it with 3 layered fuzzy-text reconcilers. |
| Blank app when hosts are down | Client persists nothing but read-stamps + settings. |

Multi-host hazards found but not yet felt: **double-resume divergence** (host B lists host A's *live* sessions as resumable; sending to one auto-resumes a competing fork) and **host identity corruption** (`data/host-id.sync-conflict-*` files prove per-host state is being synced between machines).

---

## 2. What exists today (map)

```
TODAY — per host                              iOS client
┌──────────────────────────────┐             ┌─────────────────────────────────┐
│ tmux panes  (execution)      │             │ SessionStore (one 1,100-line    │
│   ↑ send-keys + scrape       │             │  @Observable doing 3 jobs)      │
│ sendq (IN-MEMORY, lost on    │◄── POST ────│  · 3s poll ×2 hosts (barrier!)  │
│   restart; scrape-confirmed) │             │  · SSE ×2 hosts, 24-id cap,     │
│ ~/.claude/projects (SYNCED)  │             │    40-msg backfill, seen-sets   │
│   ↑ tail per SSE connection  │             │  · merge / dedupe / first-wins  │
│ SSE: fire-and-forget,        │─── SSE ────►│  · reconcile-by-text ×3 layers  │
│   per-connection delta maps, │             │  · lastGood caches, debounces   │
│   NO journal, NO cursors     │             │  · NOTHING PERSISTED            │
│ APNs alert-only watcher      │─── push ───►│  (alert wakes user, not state)  │
└──────────────────────────────┘             └─────────────────────────────────┘
```

The audits' distilled verdict: *the server assumes it is the sole authority over every session it can see, while the synced file layer makes the other host's sessions readable and resumable but not controllable. Readable-but-not-live, resumable-but-owned-elsewhere — that mismatch is the core tension.* Full workaround census (35 items) in §9's deletion list and the audit appendices.

---

## 3. The target model

Three planes, today conflated:

1. **Data plane — durable, global.** A *session* is a conversation (id, title, cwd, transcript, last message), identical on every host — Syncthing already replicates it. The phone becomes a third replica.
2. **Execution plane — ephemeral, host-bound.** A *pane* runs a session on exactly one host. `busy`, `prompt`, and the send queue are pane properties.
3. **Delivery plane — currently missing.** How state reaches the phone and intents reach panes. Today fire-and-forget; target **journaled, cursored, resumable, idempotent**.

Principles: **P1** sessions global, hosts are executors · **P2** UI renders only from the local store · **P3** event delivery is resumable, never lossy (journal + cursors) · **P4** every mutation idempotent (client ids + outbox) · **P5** connectivity is a state machine, not a failure counter · **P6** connections are cheap to lose and instant to resume — and never torn down by our own code · **P7** background continuity is push-driven — cursor-warm store, system-completed sends, live lock-screen state; no repurposed background modes · **P8** per-machine state never lives in a synced path.

---

## 4. The connection layer — making flakiness rare, cheap, and honestly reported

This section addresses: *"flaky connection to hosts I know are up and on the tailnet."* The flakiness has three distinct sources with three distinct fixes. Ordered by impact:

### 4.1 Self-inflicted teardowns — the app kills its own healthy connections

Found in the audit; each is a real disconnect that no network caused:

| # | Teardown | Trigger | Fix |
|---|---|---|---|
| 1 | `ensureStream` **cancels and rebuilds a host's entire SSE stream whenever the top-24 id set changes membership** (`SessionStore.swift` — `streamTasks[host.id]?.cancel()` on key change) | Opening a session outside the window, any session starting/closing/resuming, activity pushing one out of the top 24 | Journal stream subscribes to *everything on the host* — there is no id set, so there is nothing to rebuild. The stream survives all session lifecycle. |
| 2 | After a clean close or stall, re-establishment **waits for the next poll tick** (reset `streamedIDs` → hope `refresh()` runs `ensureStream` soon), historically behind the 15s black-hole barrier | Any stream death | `HostLink` owns its own reconnect loop: immediate retry with `since=cursor`, then backoff. Independent of any poll. |
| 3 | `reconnect()` **wipes all state and restarts everything** when the host list changes | Editing anything in Settings hosts | Store-backed state survives; only the affected `HostLink` restarts. |
| 4 | The 35s stale watchdog is the *only* death detector; a silent stall means up to 35s of stale UI before recovery even begins | Path flap, NAT rebind | §4.2 keepalives cut detection to ≤20s; §4.3 cursor resume makes recovery one cheap round-trip. |
| 5 | 15s GETs against a black-holed peer + failure-count debounce | Offline *other* host | Fixed this week (streaming fan-out + `HostHealth`, uncommitted) — lands first, in Phase 0. |

**These are the majority of the "disconnecting while I'm on the app" events.** They cost nothing to trigger (a session finishing re-ranks the list → teardown) and today's recovery is expensive (backfill replay, delta-map reset, poll-gated timing). Eliminating them is not "mitigation" — the connection genuinely stops dropping.

### 4.2 Genuine path flaps — reduce their frequency, then their cost

Measured this session: the phone's NAT endpoint churned (`:35429 → :24190 → :13037 →` new public IP), the path flapped direct↔DERP, and per-peer counters reset (endpoint rebuilds) — all while both hosts were up and the phone had internet. Cellular NAT does this; no client code can prevent it entirely. What measurably reduces it:

- **Application-level keepalive, both directions.** Server SSE heartbeat drops 15s → **10s**; client sends a tiny ping (`HEAD /api/ping`) every **10s** per live host. Two effects: (a) **carrier NAT and the Tailscale peer path stay warm** — idle UDP mappings on cellular expire in as little as ~30s, and an SSE connection that only heartbeats every 15s generates too little underlay traffic to reliably hold the mapping; steady 10s traffic prevents the expiry that *causes* re-punch flaps; (b) death detection in ≤20s instead of 35s, in both directions. Cost while foregrounded: negligible (a few bytes/sec).
- **Give the Air a stable inbound endpoint.** Direct-path recovery after a phone-side rebind is near-instant when the *host's* endpoint is stable and directly reachable. Enable NAT-PMP/UPnP on the home router (or forward `udp/41641` to the Air), then verify `tailscale netcheck` shows a working PortMapping and `tailscale status` shows the phone `direct`. Ten minutes of router config; materially less DERP time and faster re-punch. (DERP itself is an acceptable floor — 66ms from HK — the pain is the *transition gaps*, which stable endpoints shrink.)
- **RTT visibility.** The keepalive doubles as an RTT sample per host; the UI can show path quality (e.g. a subtle "slow link" state) instead of a binary connected/offline.
- **On home Wi-Fi** the phone uses the Air's LAN endpoint — zero NAT churn. Worth knowing, not a fix.
- **Considered and rejected:** Multipath TCP (`URLSession.multipathServiceType`) — inside the tunnel there is only one path (the tailnet), and beneath it Tailscale already handles interface migration itself; MPTCP adds nothing here. HTTP/3/QUIC — Bun has no server-side H3; the win would be marginal over cursor-resume anyway.

### 4.3 Make any remaining drop invisible

With the journal (§6): reconnect = one request (`/api/events?since=cursor`) that returns exactly what was missed. No 40-message backfill, no state re-derivation, no re-ranking dance. A 10-second flap costs one round-trip and renders as *nothing* — the transcript just keeps flowing. This is the difference between "the connection is flaky" and "the path flapped and you never knew."

### 4.4 Report connectivity honestly

Today a transient blip on one host shows "host unreachable" for a machine that never went down — flakiness *perceived* is partly flakiness *misreported*. `HostLink`'s state machine renders directly: `catchingUp` (reconnected, syncing — show nothing or a subtle spinner) is not `unreachable` (sustained failure ≥30s — show the banner, name the host). The failure-count debounce dies with it.

**Acceptance targets for this section** (testable — collectively they are the Phase 1 gate):
- Zero stream rebuilds caused by session lifecycle events (open/close/create/transfer).
- Detection of a dead path ≤20s; recovery after path restored ≤3s; zero lost events across the gap.
- Airplane-mode toggle mid-stream: transcript resumes seamlessly, no banner unless >30s.
- A sleeping *other* host causes no visible effect on the healthy host's experience (Phase 0 covers most; verified end-to-end here).

---

## 5. Background persistence — the full option space, honestly

This addresses: *"the client is connected all the time when sessions are running, even in background."*

The platform truth first: **iOS freezes an ordinary app's sockets within seconds of backgrounding, and nothing in the public SDK changes that for a normal app.** Every app that "feels connected in the background" (Slack, WhatsApp) is doing push-driven state sync, not holding sockets. Socket-continuity hacks exist but each repurposes a background mode with unacceptable strings attached (see the rejected list below — including background audio, ruled out by Eugene). The design therefore commits to doing push-driven continuity *exceptionally well*:

### Strategy A — Information continuity (the design)

The *state* stays fresh even though no socket exists:

1. **`content-available` background pushes** on journal-worthy events, carrying `{hostId, seq}`. iOS wakes the app ~30s in the background; the app sees exactly how far behind its cursor is and pulls the delta into the store. Budgeted by iOS, generous for an actively-used app.
2. **Alert pushes** (existing, already carry a session snapshot) for needs-input / finished.
3. **`beginBackgroundTask` grace on backgrounding** — buys ~30s of continued live streaming, which cleanly covers the extremely common "flip to Safari and back" case with genuinely zero disconnect.
4. **`BGAppRefreshTask`** — opportunistic periodic sync as belt-and-braces.
5. **Live Activities** (recommended, its own phase): a lock-screen/Dynamic Island card per *running* session — status, current tool line, needs-input/finished — updated by APNs Live-Activity pushes with no app process at all. For "sessions are still running and I want to glance," this is better than a connection: it's on your lock screen.

Net effect: opening the app finds it current or makes it current in <1s (cursor delta), and the lock screen tracks running sessions continuously.

### Rejected: socket-continuity hacks (owner decision + platform reality)

Every mechanism that keeps a suspended app's sockets alive is a repurposed background *mode*, and each fails a requirement:

- **Background audio keep-alive** — works, but **rejected by Eugene: no audio involvement.** Off the table.
- **PushKit/VoIP** — guaranteed instant wake, but must present a CallKit call. No.
- **Significant-location-change** — battery, privacy prompt, jitter. No.
- **Silent-push-as-heartbeat** — iOS throttles it into uselessness as a transport. No.

So the design commits fully to Strategy A, upgraded in two places to close most of the gap sockets would have covered:

1. **Outbox sends ride a background `URLSession`.** Uploads handed to a background session are executed by the *system daemon*, not the app — they complete even if the app is suspended or killed mid-send. "Type, hit send, pocket the phone" becomes reliable without any live socket. (Delivery confirmation then arrives as a push / next cursor sync.)
2. **Live Activities carry the "watching a running session" job**, with **push-to-start** (iOS 17.2+): the *server* starts a Live Activity when a session begins running — the app doesn't even need to be open — and updates it via APNs (status, current tool line, needs-input, finished) with the frequent-updates entitlement. Your lock screen *is* the connection while the app is backgrounded.

### What §5 deliberately does not promise

A suspended iOS app receives no socket data — no compliant design changes that. The honest offer: **instant lossless resume (cursor), a push-warm store (content-available), system-completed sends (background URLSession), and live lock-screen state for running sessions (Live Activities).** In practice that reads as "always connected"; the only thing it isn't is a literal open socket.

---

## 6. Server changes

### 6.1 The journal

`~/.lfg/journal.db` (bun:sqlite — built-in, synchronous, microseconds):

```
events(seq INTEGER PRIMARY KEY AUTOINCREMENT, ts, sessionId, type, payload)
-- type ∈ msg | busy | prompt | queue | session-opened | session-closed | session-renamed
```

- **One server-global pump** replaces per-connection pumps (today: 700ms transcript tail + 1000ms pane poll *per session per connection*, private delta maps discarded on disconnect — CPU scales with connections × sessions and all delta state is ephemeral). The pump tails all local panes once and journals *changes*. Deletes: per-connection `offset/lastSig/lastBusy/lastQ`, 40-message backfill, `init`-busy sentinel, the 24-id cap, the `ids=` protocol itself.
- **`GET /api/events?since=<seq>`** (SSE): replay after `seq`, then live. Heartbeat every 10s carrying head seq (doubles as §4.2 keepalive + gap detector).
- **A host journals only sessions it executes** (has a pane/registry entry) plus its own lifecycle actions — cross-host double-delivery impossible by construction.
- **Retention + resync:** transcripts remain the message source of truth; the journal is a bounded delivery buffer (14 days). Cursor older than retention → `resync` event → client snapshot-fetches and resets to head (same path bootstraps a fresh install).

### 6.2 Durable, idempotent sends

- sendq: `Map` → same SQLite db. **Restart no longer drops in-flight messages.**
- `POST /send` takes a client-generated `clientId`; duplicates return existing state (safe retries).
- The delivery loop already confirms sends by watching the transcript; it now journals `queue {clientId, delivered, userTurnId}` — naming the confirmed turn. That one field lets the client swap optimistic bubble → real message *by identity*, deleting the entire reconcile-by-text stack.
- The re-drive-on-idle net (orphan grace, redelivery cap) stays — the tmux boundary remains scrape-based and that logic is sound.

### 6.3 State correctness at the source

- `lastActivityAt` (and `busy`'s freshness window) from the **last message's `ts`**, mtime as fallback — the `previewLast` result is already computed on the adjacent line. Immunizes unread/sorting/busy/push against Syncthing's hourly mtime rewrites.
- `Session.last.id` becomes the read-state anchor (message identity, no clocks).

### 6.4 Session leases (single-execution enforcement)

`~/.claude/projects/<proj>/<sessionId>.lease.json` — `{hostId, pid, acquiredAt, heartbeatAt}`, heartbeat ~30s while the pane lives, synced by Syncthing like everything beside it.

- `listResumable` excludes sessions with a fresh foreign lease (heartbeat <90s).
- `resume`/`fork`/auto-resume-on-send: fresh foreign lease → `409 {liveOn: hostId}`; the client routes to the right host instead of forking the conversation.
- Stale lease → takeover allowed. Sync latency leaves a small race window: the failure mode changes from *silent divergence* to *rare, detectable conflict* — the right trade for two coordinator-less hosts. Transfer becomes lease release/acquire, replacing the client's 8×400ms + 10×700ms retry loops.

### 6.5 Push

- Alert pushes unchanged (per-host watcher + snapshot payload). The 6.3 fix removes their spurious triggers too.
- Add `content-available` pushes `{hostId, seq}` (§5-A1) and, in its phase, Live Activity start/update pushes (§5-A5; server tracks per-activity tokens alongside `push-devices`).
- No cross-host dedupe needed: each host pushes only what it executes.

### 6.6 Per-machine state out of synced paths

`PATHS.data`: `<repo>/data` → `~/.lfg/` (old path read as migration fallback). Ends the `host-id`/`managed-sessions` sync-corruption class. `~/.claude/.stignore` already excludes `/sessions` (pid files) — verify on both machines. **`/projects` must stay synced** (transfer, resume, leases, read-anywhere all ride on it); the earlier suggestion to stop syncing it is rejected — §6.3 is what makes syncing safe.

---

## 7. Client changes

The 1,100-line `SessionStore` (three jobs in one `@Observable`) becomes three small parts:

### 7.1 `LFGStore` — persistence

GRDB/SQLite: `hosts`, `sessions` (global by id, `runningOnHostId?`, last-message preview), `messages` (bounded per session, ~200; full history stays paged), `outbox`, `cursors`, `readState` (sessionId → lastSeenMessageId). UI reads **only** the store (ValueObservation → SwiftUI). Cold launch with both hosts down: full list + recent transcripts render instantly — **requirement #3 satisfied structurally**. All ingestion is upsert-by-id → idempotent → replays/resyncs/multi-source dedupe for free; `seen`-sets die.

### 7.2 `HostLink` — one actor per host, a real state machine

`disconnected → connecting → catchingUp(since:) → live → backoff(n)` — owns its socket, cursor, keepalive (§4.2), watchdog (≤20s), and its own immediate-then-backoff reconnect loop (§4.1-2). This week's `HostHealth` policy becomes the `backoff` parameters. The banner renders link state (§4.4).

### 7.3 `Outbox` — sends that survive anything

Send = insert row (clientId, …) → bubble renders from the row → worker POSTs with `clientId` → journal's `delivered {clientId, userTurnId}` deletes the row as the real message lands. Kill the app mid-send: row persists, worker retries, server dedupes. Routing keeps existing owner/healthy logic, now lease-checked server-side.

### 7.4 Read-state, fixed

Identity-based (`lastSeenMessageId`), no clock comparison (kills the skew hole), `focusedID` cleared on detail dismiss (kills the sticky-suppression hole — likely your main "idle messages missed" cause).

### 7.5 Single-host residue swept

Create-metadata / users / usage / deep-link resolution go through the health-aware host directory instead of "the default client" (the partial-outage findings); `hostId` finally dedupes a host reached via two URLs; closed-session media resolves via any healthy host (synced files make that correct).

---

## 8. What stays (and what this does NOT fix)

- **tmux screen-scraping** — the only way to drive a TUI agent; re-drive/overlay/selector heuristics remain load-bearing. The journal changes delivery *observability*, not mechanics.
- **Syncthing as the data plane** — now a design citizen (leases) instead of an unacknowledged dependency corrupting mtimes.
- **Client-side fan-out** — the original decision was right (symmetric hosts, no primary); what changes is what the client fans out *to*.
- **Cellular physics** — the path will still occasionally flap; §4 makes flaps rarer (keepalives, stable endpoint) and invisible (cursor resume), not impossible.
- **Bun single event loop** — mitigated (one pump instead of N×M), not removed.

## 9. What gets deleted

**Server:** per-connection pumps + delta maps · 40-backfill · init sentinel · 24-cap + `ids=` protocol · `lastGood` list cache · queue loss-on-restart. **Client:** 3s poll loop · stream-rebuild-on-membership-change · `seen` sets · REST-busy seeding · `lastSessionsByHost` + `closedCache`/`resumeTick%4` · reconcile-by-text + `correlatePending` + poll safety-net + view-layer duplicate filter · failure-count debounce · `focusedSnapshot`/`deepLinkSession` carry-forwards · clock-skew read-state. **≈25 of the 35 catalogued workarounds** lose their reason to exist; the survivors are the legitimately-hard tmux boundary.

---

## 10. Migration — connectivity first, in two tracks

Ordered by Eugene's priority: **Track A (phases 0–2) is exclusively connectivity** — every phase in it makes the connection stabler, recover faster, or survive backgrounding better. The storage/reliability rework (Track B) comes after, and nothing in Track A depends on it: the events stream feeds the *existing* in-memory state, and cursors persist in UserDefaults until the store exists.

### Track A — Connectivity (§4 + §5)

*(v5: the former "Phase 1 — transport hardening on the current architecture" is dissolved into Phase 1 below. It existed only as a fast-relief bridge under the assumption that the journal would take weeks; with agentic implementation measured in hours, the bridge work — a reconnect loop against the old SSE endpoint — would be the plan's only throwaway code. Its surviving items (keepalives, watchdog, banner honesty, background grace, scoped restarts) were always destined for `HostLink` and are now built there directly, once. What implementation speed does NOT compress: **soak time** — the symptom is "flaky over days of real cellular use," so the merged build still needs days of live usage to be called verified.)*

| Phase | What | Connectivity payoff | Gate |
|---|---|---|---|
| **0** — ✅ **landed 2026-07-10** (commits `3b8887e`, `9fc4ec0`) | In-flight fixes: fan-out streaming + `HostHealth` back-off, partial-outage routing, read-state identity, server `lastActivityAt`→`last.ts`, `data/`→`~/.lfg/` (+ live host-id corruption caught and corrected on the Pro). Open remnants: Air server restart (self-heals identity on restart), router NAT-PMP/`udp/41641` port-forward, TestFlight build to the phone. | 15s black-hole stalls gone; mtime-corrupted unread/busy gone; host identity permanently de-conflicted | ✅ live-verified on the Pro: 27/27 sessions `lastActivityAt == last.ts`, hostId stable, writes land in `~/.lfg`, tailnet 200 |
| **1** — *the connectivity core (one build)* | **Server:** event journal + one global pump + `GET /api/events?since=` with 10s heartbeats carrying head seq (additive; old endpoints untouched) + tiny `/api/ping`. **Client:** `HostLink` actor per host — state machine (`disconnected → connecting → catchingUp → live → backoff`), consumes the events stream, per-host cursor in UserDefaults, 10s keepalive ping (NAT warmth + RTT), ≤20s stale watchdog, immediate-then-backoff reconnect owned by the link (never the poll), Settings edits restart only the affected link, `beginBackgroundTask` grace on backgrounding, banner from sustained link-state ≥30s. Deletes the `ids=` protocol (no teardowns on session lifecycle), the 24-id window, the 40-message backfill; the 3s poll shrinks to a slow (60s) reconcile | **All of §4 in one shot:** self-inflicted disconnects structurally gone; flaps rarer (warm NAT); real drops detected ≤20s, recovered in one lossless round-trip; connectivity honestly reported | The full §4 acceptance list: zero stream rebuilds across lifecycle events; kill server mid-stream → zero message loss; airplane-toggle → recovery ≤3s, no banner under 30s; sleeping other host → no visible effect. **Then days of live soak on the phone before Track B starts** |
| **2** — *background continuity* | `content-available` pushes `{hostId, seq}` → delta sync on wake; `BGAppRefreshTask`; sends handed to a **background URLSession** (system completes them after suspension; minimal persisted pending-list now, full outbox in Track B); **Live Activities**: push-to-start + APNs updates for running sessions | The backgrounded phone stays current, sends complete themselves, and running sessions are live on the lock screen — requirement #1's background half, no audio, no hacks | send + immediately background → delivered exactly once; lock phone during a run → Live Activity tracks it; unlock → current without a spinner |

**After Track A, both connectivity requirements are met.** What remains below is reliability plumbing and offline capability — valuable, but nothing in it changes how connected the app feels.

### Track B — Reliability & offline

| Phase | What | You get | Gate |
|---|---|---|---|
| **3** | Server: durable sendq (SQLite) + `clientId` idempotency + journaled `delivered {clientId, userTurnId}` acks | Server restart no longer drops in-flight sends; the ack that makes optimistic UI exact | `bun test` dedupe/replay; restart-with-queued-sends test |
| **4** | Client: `LFGStore` (GRDB) — sessions/messages/read-state/cursors move in; UI renders from store | **Offline list + transcripts (req #3)**; blank-app-on-relaunch gone | airplane-mode cold launch shows full list + recent transcripts |
| **5** | Outbox on the store, driven by Phase 3 acks; delete the reconcile-by-text stack (3 client mechanisms + view filter) | Sends survive app kill; optimistic bubbles hand off by identity, not fuzzy text | kill app mid-send → delivered exactly once, bubble resolves |
| **6** | Leases: resumable exclusion, 409-routing, transfer-via-lease | Double-resume divergence closed; robust transfer | forced double-resume → clean 409 |
| **7** | Cleanup: delete legacy endpoints/loops + single-host residue sweep (default-client fallbacks, `hostId` dedupe, closed-session media routing) | The ~25-workaround deletion actually lands | full regression pass on TestFlight after soak |

Phases 3 and 4 are parallelizable. Nothing legacy is deleted until its replacement has soaked on TestFlight — the soak between Track A and Track B is the plan's one non-compressible interval.

## 11. Open decisions (recommendations first)

1. **Persistence: GRDB** (recommended — proven SQLite, ValueObservation fits SwiftUI, background-sync-friendly) vs SwiftData (native but @MainActor-heavy, opaque migrations) vs hand-rolled.
2. **Leases via synced files** (recommended — rides existing substrate, hosts stay independent) vs host↔host API vs client-only.
3. ~~Stay Connected mode~~ — **resolved: not building it.** Eugene ruled out audio involvement; no other compliant socket-continuity mechanism exists. Strategy A (upgraded with background-URLSession sends + Live Activities) is the background design.
4. **Live Activities: in scope, Phase 2** (recommended, now load-bearing — with sockets off the table it is the only continuously-live surface for a running session while the app is backgrounded; push-to-start + frequent-updates entitlement) vs defer.
5. **Read-anywhere** (healthy host serves a down host's synced transcripts read-only): defer (recommended) — store upserts make it nearly free later; not needed for the three requirements.
6. **Journal retention: 14 days** (recommended).

---

## Appendix: requirement traceability

| Requirement | Mechanism |
|---|---|
| 1. Connected all the time, incl. background, while sessions run | §4: no self-inflicted teardowns + keepalives + stable endpoint + ≤20s detection + one-round-trip lossless resume. §5: content-available delta sync + bg-task grace + background-URLSession sends + **Live Activities as the live surface for running sessions**. Honest bound: a suspended app holds no sockets — platform rule; audio-based workaround rejected by owner. |
| 2. Messages picked up reliably | Server→client: journal + cursors (no 40-cap/24-window/lost transitions) + message-ts activity (Syncthing-proof) + identity read-state (no clocks, no sticky focus). Client→server: persisted outbox + idempotent clientId + ack naming the confirmed turn + re-drive net + leases. |
| 3. List + transcripts offline | The phone is a replica; UI reads only the local store. |
