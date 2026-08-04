# Instant reconnect on app open

**Problem (reported):** "When no sessions are running, usually when I open the app
again the host is not connected. Only after a while will the host be shown as
connected again. I want the reconnection to be almost instant."

The "when no sessions are running" qualifier is the tell — it points straight at
the live-stream path, which is the only reachability signal that behaves
differently depending on whether the host's journal is producing events.

## Root cause — three delays that compound

### 1. An idle events stream sends no bytes for up to 10s (server)

`GET /api/events?since=<cursor>` (`src/commands/serve.ts:1541`) writes the replay
backlog on connect and then starts a **10s** heartbeat interval. When the client's
cursor is already at head — i.e. **no sessions are running, nothing to replay** —
the response body is empty until the first heartbeat fires, up to 10s later.

`HostLink` only leaves `.connecting` when an element arrives
(`ios/LFG/HostLink.swift:157-176`); `SessionStore.linkStateChanged` only marks a
host reachable from `.catchingUp`/`.live`. So on an idle host the link — and the
"Connected" badge — is blind for up to 10s after the socket is already fine.

With sessions running, replayed events arrive on connect and the badge flips
immediately. Exactly the reported asymmetry.

### 2. The REST reconcile that could confirm sooner runs every 60s

`SessionStore.start()`'s poll loop sleeps **60s** between `refresh()` calls
(`SessionStore.swift:355`). It probes `/api/sessions` per host and marks `.ok` on
success — a fast, independent reachability signal. But if the probe issued at
foreground fails once (very likely: after suspension the phone's Tailscale path is
cold and needs a re-punch), the next one is a full minute away.

Worse: after `HostProbePolicy.failureThreshold` (4) consecutive failures a host
goes "cold" and is probed only every `coldProbeEveryNTicks` (10) ticks. That
constant was written for the old **3s** poll ("cold hosts are retried every ~30s",
`HostHealth.swift:32`) and was never updated when the loop became 60s — so a cold
host is now re-probed every **10 minutes**.

### 3. A link can be sitting in a 30s backoff at foreground time

`HostLinkPolicy.reconnectDelay` caps at 30s. Nothing kicks the links on
foreground, so a link that backed off while the host was briefly unreachable can
idle for up to 30s after the user opens the app.

### 4 (cosmetic, but it *is* the complaint). Unknown state renders as "Offline"

`StatusBadge` / the list header render `store.isConnected ? "Connected" : "Offline"`
(`SessionListView.swift:739`, `:983`). `reachability == nil` means *unknown* —
cold launch, nothing probed yet — and paints an alarming orange "Offline" during
the first seconds of every launch, before anything has actually failed.

## Fixes

| # | Where | Change |
| - | ----- | ------ |
| S1 | `src/commands/serve.ts` | Send `: hb <head>` **immediately** on connect, before starting the 10s interval. The link goes `.live` within one RTT instead of ≤10s. |
| C1 | `SessionStore.enterForeground` | `retryNow()` every link so a remaining backoff is skipped, and clear `failuresByHost` so no host is cold-skipped by the next probe. |
| C2 | `SessionStore` | Foreground/launch **reconnect burst**: force a refresh at 0s, 0.5s, 1s, 2s, 4s, 8s until every configured host answers, instead of waiting for the 60s tick. |
| C3 | `SessionStore.applyHostFetch` | Recompute the aggregate `reachability` as each host's result lands, so one healthy host flips the badge without waiting for a dead host's 4s timeout. |
| C4 | `SessionStore` + `SessionListView` | Tri-state `connectionStatus` (`connected` / `connecting` / `offline`). Unknown or mid-burst renders a neutral "Connecting…" instead of orange "Offline"; the full-width banner also holds off while a burst is in flight. |
| C5 | `HostHealth.swift` | Re-derive the cold-probe cadence for the 60s poll (10 ticks = 10 min → 5 ticks = 5 min) and document the coupling so it can't silently rot again. |

Non-goals: the physical Tailscale re-punch latency after suspension. Once these
are fixed the remaining delay is the network's, not the app's.

## Success criteria

1. **SC1** — A patched server's `/api/events` emits `: hb <head>` as its first
   body bytes on a caught-up (idle) connect, within ~1 RTT. *(curl/py probe)*
2. **SC2** — With an idle host, foregrounding the app shows "Connected" in
   ≲1s (was: up to 10s, and up to 60s if the first probe missed). *(sim, timed)*
3. **SC3** — Cold launch never shows "Offline" before anything has failed: the
   badge reads "Connecting…" until a probe result exists. *(sim screenshot)*
4. **SC4** — A genuinely down host still reaches "Offline" (burst exhausts, then
   the badge and banner tell the truth). *(sim, server stopped)*
5. **SC5** — A host that comes back while the app is foregrounded is shown
   connected within a few seconds without any user action. *(sim, server restart)*
6. **SC6** — `swift test` in `ios/LFGCore` and `bun test` stay green.

## Evidence

Filled in during verification — see `.claude/feature/instant-reconnect-evidence.md`.
