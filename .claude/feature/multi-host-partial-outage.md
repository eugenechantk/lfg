# Feature: Partial-outage resilience (one host down, another up)

**Status:** investigating → implementing
**Tier:** Product (shipping TestFlight client)
**Session:** 20260709-081049

## Problem (reported)

> Now that we have multiple hosts, there are situations where one host is connected
> and another is not. Because one of the hosts is disconnected, messages cannot be
> sent, some UI about host disconnected appears, and some disconnected behaviors
> affect my ability to start, continue and restart sessions with another host that
> is connected.

The fan-out (`refresh`, `reachabilityByHost`, aggregate `reachability`) is already
partial-outage aware. The **fallback path is not**: every "host-agnostic" operation
resolves to `AppSettings.defaultClient`, which picks the *marked default* host with
**no regard for whether it is reachable**.

## Root causes (from source read)

### RC1 — `defaultClient` ignores reachability
`ios/LFG/LFGApp.swift:71`
```swift
var defaultClient: LFGClient? {
    guard let h = hosts.first(where: { $0.isDefault }) ?? hosts.first else { return nil }
    return LFGClient(string: h.url)   // <- never asks if `h` is up
}
```
`HostStore.defaultHost(_:reachable:)` exists **and is reachability-aware**, but the
only caller is `NewSessionView`'s picker preselect. Everything else uses
`defaultClient`. So when the marked-default host is down:

| Path | File | Symptom |
| --- | --- | --- |
| `loadCreateMetadata()` → `store.client` | SessionStore.swift:134 | `repos`/`root`/`inbox` stay empty → **New Session has no directories → can't start** |
| `resolveDeepLink()` → `client` | SessionStore.swift:188 | Notification tap on a session on the *healthy* host can't resolve → blank detail |
| `create` / `attemptCreate` / `resume` with `on: nil` | SessionStore.swift:929, 979, 1033 | **Start / restart fires at the dead host** |
| `client(forSession:)` fallback | SessionStore.swift:147 | see RC2 |

### RC2 — closed/resumable sessions have no host in `hostBySession`
`hostBySession` is built **only** from live sessions (`MultiHost.mergeSessions`).
`MultiHost.reconcileResumable` deliberately drops host identity (transcripts are
synced → host-agnostic). So for every **closed** session
`host(forSession:) == nil` → `client(forSession:)` falls back to `defaultClient`
→ RC1 → **continue / restart a closed session fires at the dead host** even though
a healthy host could serve it.

### RC3 — a sustained-down host's sessions linger, indistinguishable from live
`lastSessionsByHost` (SessionStore.swift:124) caches each host's last good snapshot
so a *transient blip* doesn't drop its rows. It is only pruned when a host is
**removed from settings** — never when the host is sustained-unreachable. Result:
a host that has been down for hours still contributes rows that render as
Running/Idle. Tapping one opens a composer that silently fails on send.

This one is a **product decision, not purely a bug** — see "Open decision" below.

### RC4 — `ConnectionBanner` receives all hosts as "offline"
`SessionListView.swift:175` passes `settings.hosts.map(\.label)` — *every* host —
into `offlineHosts:`. Only reachable when the aggregate is down (so all really are
offline), making it latent, but it is wrong on its face and will misfire the moment
the banner's guard changes.

## Success criteria

Given **Host A = reachable**, **Host B = unreachable and marked default**:

- [ ] **SC1** New Session sheet lists directories (repos/root/inbox) sourced from A.
- [ ] **SC2** Creating a session with no explicit host picks **A**, and the session starts.
- [ ] **SC3** Sending a message to a live session owned by A succeeds.
- [ ] **SC4** Resuming/restarting a **closed** session succeeds (routes to A, not B).
- [ ] **SC5** No fleet-wide "all hosts unreachable" banner appears; per-host chips show A green / B orange.
- [ ] **SC6** Sessions owned by the sustained-down host B are visibly marked and their destructive/steering actions do not silently fail.
- [ ] **SC7** `swift test` in `LFGCore` passes, incl. new cases for reachability-aware default-host resolution.

Given **all hosts unreachable**: banner reads "All N hosts unreachable" and names them (regression guard for RC4).

## Decisions

**D1 — a sustained-down host's sessions: keep the rows, mark them offline, disable
their actions.** Rejected: hiding them (past diagnosis docs
`diagnosis-queued-leave-view-lost.md` show vanishing sessions read as data loss);
keeping them as-is (that is the reported bug). Reversible — the treatment is
confined to `SessionRow` + the detail composer gate.

**D2 — creating with no explicit host when the marked default is down: silently
fall back to the first reachable host**, surfacing the landing host in the existing
host pill. This is exactly the contract `HostStore.defaultHost(_:reachable:)`
already documents and tests, but which nothing called. Rejected: blocking the user
to pick a host, which adds a tap to every create during an outage for no
information they don't already have from the host chips.

**D3 — a LIVE session whose owning host is down keeps targeting that host.** Its
pane exists only on that machine; silently rerouting the send to a healthy host
would deliver the message to a different agent. A CLOSED session is host-agnostic
(synced transcript) and *does* reroute to a reachable host.

## Plan

1. Make `defaultClient` reachability-aware via `HostStore.defaultHost` (store owns
   health, so the *store* must resolve it — `AppSettings` has no health).
2. Route host-agnostic ops (`loadCreateMetadata`, `resolveDeepLink`, `create`,
   `resume`) through the reachable-default resolver.
3. `client(forSession:)` → for sessions with no owning host, or whose owning host
   is down **and** the session is closed (host-agnostic transcript), fall back to
   the reachable default.
4. RC3 treatment per decision above.
5. Fix RC4 to pass only actually-offline hosts.
6. Tests in `LFGCore` + live simulator verification with a real dead host.

## RC5 — a message that fails while every host is down is never resent

Reported after the first fix shipped (build 202607091653, which does NOT contain this).

When a send fails, `sendWithAttachments` marks the bubble `failed = true`
(`SessionStore.swift`) and stops. The only path back is the user tapping **Retry**
in `Components.swift`. Nothing watches for the host returning, so a message typed
during an outage sits there indefinitely.

**Fix:** detect a host transitioning `down → ok` in `performRefresh` and sweep the
failed bubbles routed to it.

**The hard part is not the trigger, it's not double-sending.** A send can reach the
server, be enqueued, be delivered to the agent, and *only then* have the host drop
before the HTTP response returns — leaving a `failed` bubble for a message that
actually landed. A naive resend posts it to the agent twice. Two guards, both
reusing machinery that already existed:

1. `reconcilePendingViaQueue` (runs each tick, now that the host is `.ok`) correlates
   each bubble against the server's outbound queue. A bubble the server still holds
   gets a `serverQueueID`, so `retryPending` retries the *queued item* server-side
   rather than posting a new message.
2. `ensureHistory` refetches the authoritative transcript and drops any bubble whose
   text now appears as a real user turn. Survivors of both layers genuinely never
   reached the agent.

Residual exposure: guard 2 matches on normalized text, so a turn the agent recorded
reformatted/wrapped could miss and be resent. That is the *existing* weakness of the
manual Retry button (see `correlatePending`'s comment), not a new one.

Two implementation traps found while writing it:
- The sweep **must not** be awaited from inside `performRefresh`. `retryPending` →
  `refresh()` → `await refreshTask` — which is the task currently running. Awaiting
  it from within itself deadlocks the store. The sweep is a separate `autoResendTask`.
- Recovery is `known-down → ok`, not `absent → ok`. At cold start `reachabilityByHost`
  is empty, so every host's first sighting looks like a recovery and the sweep would
  fire on every launch. `MultiHost.recoveredHosts` encodes this; a test pins it.

### SC (RC5)
- [ ] **SC8** With both hosts down, a sent message shows as failed; when a host returns it is resent automatically without a tap.
- [ ] **SC9** A message that actually landed before the host dropped is NOT resent (no duplicate user turn).
- [x] **SC10** Cold launch does not trigger the resend sweep. (`testRecoveredHostsTreatsFirstSightingAsNotARecovery`)

## Evidence

- `swift test` (LFGCore): **87 pass / 0 fail**, incl. 5 new `recoveredHosts` cases and
  7 `routeHost`/`isOffline` cases. `flowdeck build`: green.
- **SC1–SC9 are UNVERIFIED in a running app.** `flowdeck ui` needs a real
  `xcode-select` (see memory `flowdeck-ui-needs-real-xcode-select`); `DEVELOPER_DIR`
  covers build/test/deploy but not idb. No app-target test bundle exists, so the
  store's HTTP seam can't be driven headlessly either.
- Build `202607091653` shipped RC1–RC4 unverified at Eugene's instruction. RC5 is not
  in any build yet.
