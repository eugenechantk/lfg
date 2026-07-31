# Feature: Offline composer — preserve draft + queue-and-auto-send

## Problem

When a session's owning host goes offline, `SessionDetailView` swaps the entire
`MessageComposer` out for a static `OfflineComposerNotice`. The user's typed
`draft` survives in `@State` but is invisible and uneditable, so a prompt typed
mid-reconnect feels lost. There is also no way to send while offline.

## Goal (decided with Eugene)

1. **Keep the composer visible and editable while the host is offline.** Show the
   offline state as a compact **banner above** the composer, not as a replacement.
2. **Queue on send, auto-send on reconnect.** Tapping Send while offline durably
   queues the message (shows a "Queued · will send when {host} is back" bubble)
   and fires it automatically the moment the host becomes reachable again.

## Key facts about existing infra (already verified — reuse, don't rebuild)

- `SessionStore.sendWithAttachments` already writes the message to the durable
  SQLite outbox via `enqueueOutboxForTransport(...)` **before** the network POST.
  `LFGStore.enqueueOutbox` inserts with `state = 'pending'`.
- `LFGStore.pendingOutbox()` returns rows whose state is NOT in
  `('delivered','failed')` — i.e. any `'pending'`/`'sent'` row. So a message that
  is enqueued but never POSTed stays `'pending'` and is durably held.
- `SessionStore.retryOutboxRow(_ row:)` performs the full send + reconcile for one
  outbox row (re-enqueue, POST via `BackgroundSender`, mark sent, refresh,
  reconcile). Reuse it for the reconnect replay.
- `SessionStore.replayPendingOutboxOnStart()` already replays the outbox on app
  launch — model the reconnect replay on it.
- A host transitions to reachable at TWO sites, both assigning
  `reachabilityByHost[hostId] = .ok`:
  - `linkStateChanged(_:)` (SSE link healthy) — SessionStore.swift ~line 803
  - `applyHostFetch(_:)` (poll succeeded) — SessionStore.swift ~line 1204
- `store.isOffline(sid)` is the per-session offline predicate (host is live-owner
  and unreachable).

## Changes

### 1. `PendingSend` model (SessionStore.swift ~line 72)

Add one field:

```swift
/// Held locally because the owning host was unreachable at send time. The
/// durable outbox row stays `pending`; the reconnect replay sends it. Distinct
/// from `failed` (a real send attempt that errored → red + Retry).
var queuedOffline: Bool = false
```

### 2. `sendWithAttachments` — skip the doomed POST when offline (SessionStore.swift ~line 1883)

Reorder so the outbox enqueue (durable save) happens first, then branch on
offline BEFORE attempting the network POST:

- Keep the existing `guard let hostId = routeHostId(...) , await enqueueOutboxForTransport(...) else { failed; return }`.
- Immediately after a successful enqueue, if `isOffline(id)` is true:
  - `mutatePending(id, pid) { $0.queuedOffline = true; $0.confirmed = false; $0.showSent = false }`
  - `return` — do NOT POST. The row is durably `pending`; reconnect replay sends it.
- Otherwise proceed to the existing POST path unchanged.

(Uploads still run before this point so attachment paths are baked into `full`
and the durable text — an offline user can still attach images; they upload on
replay is NOT required because `full` already contains the resolved paths... NOTE:
uploads DO require the host. See "Attachment caveat" below.)

### 3. Reconnect replay (SessionStore.swift)

Add:

```swift
/// clientIds currently being replayed, to avoid a double-send race between the
/// launch replay and a reachability-transition replay.
private var replayingOutbox: Set<String> = []

private func markReachable(_ hostId: String) {
    let wasReachable = reachabilityByHost[hostId] == .ok
    reachabilityByHost[hostId] = .ok
    if !wasReachable {
        Task { await self.replayPendingOutbox(forHost: hostId) }
    }
}

/// Replay this host's still-pending outbox rows now that it is reachable again.
private func replayPendingOutbox(forHost hostId: String) async {
    guard let store = localStore else { return }
    let rows = ((try? await store.pendingOutbox()) ?? []).filter { $0.hostId == hostId }
    for row in rows where !replayingOutbox.contains(row.clientId) {
        replayingOutbox.insert(row.clientId)
        // Clear the "queued offline" chrome on the existing bubble; retryOutboxRow
        // reconciles it to sent/confirmed from here.
        if let loc = pendingLocation(clientId: row.clientId) {
            mutatePending(loc.sid, loc.pid) { $0.queuedOffline = false }
        }
        await retryOutboxRow(row)
        replayingOutbox.remove(row.clientId)
    }
}
```

Replace the bare `reachabilityByHost[hostId] = .ok` assignment at BOTH transition
sites (`linkStateChanged` ~803 and `applyHostFetch` ~1204) with
`markReachable(hostId)`. Keep the surrounding `failuresByHost`/`unhealthySinceByHost`
lines as-is.

### 4. Bubble rendering — "queued offline" state

`PendingStripView` (Components.swift ~line 305) and `OptimisticUserBubble`
(~line 347): add a `queuedOffline` branch, rendered BEFORE the `failed` branch:

- Icon: `clock.arrow.circlepath` (or `wifi.slash`), tinted `.secondary`/`.orange`
  — NOT red.
- Trailing text/label: "Queued" (strip) / a caption "Will send when reachable"
  (bubble). No Retry button.
- Not tappable (skip the remove/edit/send-now sheet — there is no server queue id
  yet). Guard the existing `.onTapGesture { if !item.failed ... }` to also exclude
  `item.queuedOffline`.

### 5. Composer / banner (SessionDetailView.swift ~line 70)

Replace the `if store.isOffline(sid) { OfflineComposerNotice } else { MessageComposer }`
swap with: **always** render `MessageComposer`, and when `store.isOffline(sid)`,
render a compact banner ABOVE it in the same `VStack`.

- The composer's `onSend` stays exactly as-is (`store.dispatchSend(...)`); offline
  is handled inside the store (step 2), so the view doesn't branch on send.
- Restyle `OfflineComposerNotice` into a slim one/two-line banner (keep the
  `wifi.exclamationmark` orange icon). Copy: **"{host} is unreachable — messages
  will send when it's back."** Keep it visually subordinate to the composer.

## Attachments while offline — REVISED (v2, supersedes the disable-offline path)

**Decision (Eugene):** do NOT drop or disable attachments while offline. The image
bytes already live in the client (`ComposerAttachment.data`, PNG); only the
`client.upload` step needs the host. So persist the bytes durably (exactly like
the queued text) and **defer the upload to reconnect-replay**. A queued image must
survive app kill just like queued text.

### Durable attachment blobs (sidecar to the outbox, keyed by clientId)

- Store dir: `applicationSupportDirectory/outbox-attachments/<clientId>/<index>.png`
  (same container as `lfg-store.sqlite`). Survives app kill.
- The outbox `text` row still holds the typed text only at queue time (attachment
  host-paths are unknown until upload). No schema change — attachments are sidecar
  files.

### 1. Queue attachments at offline send time (`sendWithAttachments`, offline branch)

Replace "skip upload / drop attachments" with: write each `att.data` to
`outbox-attachments/<clientId>/<i>.png`, enqueue the outbox text as today, mark the
bubble `queuedOffline`. `displayText` already shows "📎 Attachment" when text is
empty — keep that.

### 2. Deferred upload on replay (`retryOutboxRow` — used by BOTH launch replay and reconnect replay)

At the top of a row's replay, before the POST:

```
if attachment files exist for row.clientId:
    for each file (ordered): path = try await client.upload(row.sessionId, data: fileBytes, contentType: "image/png")
    full = ([row.text] + paths).filter { !$0.isEmpty }.joined(separator: "\n")
    await enqueueOutboxForTransport(clientId: row.clientId, ..., text: full)   // bake paths into the row (ON CONFLICT overwrites; state → pending)
    delete the outbox-attachments/<clientId>/ dir                              // upload happens exactly once
    sendText = full
else:
    sendText = row.text
```

Then POST `sendText` (was `row.text`). On any upload failure, leave the files in
place and mark the bubble `failed`/keep queued so the next reachable replay retries
— do NOT delete the dir on failure. Baking `full` into the row after a successful
upload makes a later POST-retry send text-with-paths without re-uploading.

Also: update `mutatePending(eff, row.clientId)` / matchText so the reconcile matches
the full text (with paths), consistent with the online path which sets
`matchText = full`.

### 3. Retry-cap / cancel cleanup

- When a row is abandoned as failed past `outboxRetryCapMs` (in
  `replayPendingOutboxOnStart`), also delete its `outbox-attachments/<clientId>/` dir.
- `removeQueued` / `deleteOutbox(clientId)`: delete the attachment dir too, so
  cancelling a queued image cleans up its bytes.

### 4. Remove the offline-disable UI (revert the v1 caveat handling)

- `MessageComposer`: drop the `attachmentUnavailableReason` gating — attachments
  are allowed offline; `canSend` no longer special-cases offline attachments; remove
  the "Attachments can't be sent while offline." note (or stop passing the reason).
- `SessionDetailView`: stop passing `attachmentUnavailableReason` (always nil / remove).

### Verification addendum

- Offline: attach an image + type text, tap Send → shows a "Queued" bubble (with the
  attachment), composer clears, send is NOT disabled.
- Kill + relaunch the app while still offline → the queued image+text persists.
- Bring the host back → the image uploads and the message (text + image path) lands
  in the transcript automatically; the agent receives the image.
- Attachment-only (no text) offline send also queues and lands on reconnect.

## Verification (product tier)

1. `cd ios/LFGCore && swift test` — green (model/parse changes).
2. Live simulator (FlowDeck):
   - Point client at a reachable local `lfg serve`, open a session.
   - Type a draft; make the host unreachable (stop serve / bad host). Confirm:
     composer stays visible + editable, draft intact, offline banner appears.
   - Tap Send → bubble shows "Queued", NOT red/failed. Draft clears.
   - Bring the host back → within one poll/link-heal the queued bubble auto-sends
     and reconciles to a real user turn; agent receives it.
   - Screenshot each state as evidence.
3. Regression: normal online send still shows the instant blue bubble; a genuine
   send failure (host up, server 500) still shows red + Retry (failed ≠ queued).
