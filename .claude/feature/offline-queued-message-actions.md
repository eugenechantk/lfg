# Offline-queued messages: reliable auto-send + a more-actions menu

**Tier:** product (shipping TestFlight app)
**Reported:** 2026-08-11 — "The queued message when the host is offline does not send
automatically when the host is back online; only when I open that session and wait for a
while." Plus: "There should also be a more action button just like queued messages when the
session is running so that I can send the message or remove the message."

---

## What the repro proved (and disproved)

Live repro on iPhone 17 Pro sim against a throwaway stub host on `127.0.0.1:8799`
(evidence in `.claude/evidence/20260811-offline-queue/`).

| Round | Scenario | Result |
| --- | --- | --- |
| 1 | App foreground throughout. Host down → queue message → back to list → host up. | **Delivered in ~36s**, never opened the session. |
| 2 | Queue → background app → relaunch while host still down → host up, stay on list. | **Delivered in ~13s.** |

So the happy path already works: `setHostState`'s `!wasLive → isLive` edge fires
`replayPendingOutbox(forHost:)`, and that drains the row. The naive theory ("recovery never
triggers a drain") is **disproved** — don't re-chase it.

What the repro did *not* cover is the branch where an attempt has already **failed**, and that
branch is a proven dead end in the code.

## The actual defect: `failed` is terminal, and it's reachable by accident

`LFGStore.pendingOutbox()` (`ios/LFGCore/Sources/LFGCore/LFGStore.swift:275`):

```sql
WHERE state IS NULL OR state NOT IN ('delivered', 'failed')
```

It is the **only** reader of the outbox. Both replay paths
(`replayPendingOutboxOnStart`, `replayPendingOutbox(forHost:)`) go through it. So the moment a
row is marked `failed`, three things become true at once:

1. The host-recovery drain can never see it again.
2. After an app relaunch it is never restored into `pendingSends` either — so the bubble
   *disappears* and the message is silently lost.
3. The only remaining path is `scheduleResendAfterRecovery` → `resendFailedSends`, which needs
   `HostStateMachine.recoveredHosts(before:after:)` to observe a down→live flip **within a
   single `performRefresh` tick**. `healthBefore` is snapshotted at the top of that function,
   and the `HostLink` flips the host live asynchronously (≤30s backoff) — almost always
   *between* 60s poll ticks. By the next tick `healthBefore` already reads `.live`, so
   `recovered` is empty and the sweep never runs.

And `retryOutboxRow`'s `catch` marks `failed` on **any** transport error, including "the host
is still down" — which is not a message failure at all. Attachments get an escape hatch
(`SessionStore.swift:1018-1026` puts them back to `queuedOffline`); a text-only message does
not.

A row therefore burns to `failed` on any replay attempt that races a still-cold path — e.g. the
foreground drain firing before the tailnet path is warm, which the Pro host does routinely
(memory `lfg-pro-host-sleep-disconnects`). After that the message is stuck until the user
manually taps Retry — and there is no Retry to tap on a "Queued" row, which is request #2.

## Success criteria

1. A queued-offline message whose replay attempt fails **against a host that is still down**
   stays `Queued`, not `failed` — the reconnect drain still owns it.
2. A row that *did* end up `failed` is picked up again by the host-recovery drain and by the
   next app launch (subject to the existing 24h cap), instead of being terminal.
3. A `failed` row still restores its bubble after relaunch, so a message can never vanish.
4. Tapping an offline-`Queued` row in the pending strip opens a more-actions dialog with
   **Try sending now**, **Edit**, **Remove** — mirroring the running-session queued menu.
5. `Send now` on an offline row attempts delivery immediately rather than silently doing
   nothing (today `sendQueuedNow` early-returns without a `serverQueueID`).
6. `swift test` green; live sim verification of 1 and 4.

## Changes

**`LFGCore/LFGStore.swift`** — add `retryableOutbox()`: same query minus the `'failed'`
exclusion. `pendingOutbox()` stays (narrower semantics, existing tests).

**`LFG/SessionStore.swift`**
- Both replay paths read `retryableOutbox()`; `replayPendingOutbox(forHost:)` gains the 24h cap
  the on-start path already has.
- `appendPendingFromOutbox` restores a `failed` row as a failed bubble; the drain clears the
  flag before re-attempting.
- New `settleSendFailure(...)`: a transport error against a host that is *not currently
  reachable* leaves the row queued-offline; anything else marks it `failed` as today.
  Used by `retryOutboxRow` and `retryPending`.
- `sendQueuedNow` falls back to an immediate `retryPending` when there is no `serverQueueID`.

**`LFG/Components.swift`** — `PendingStripView` shows the `ellipsis.circle` affordance on
offline rows and makes them tappable.

**`LFG/SessionDetailView.swift`** — the confirmation dialog branches on `queuedOffline` for
copy ("Try sending now" vs "Send now (interrupt)").
