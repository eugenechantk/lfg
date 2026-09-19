# Diagnosis — the card still does not update while the phone is idle (2026-09-19, evening)

Eugene, after builds 202609191344 (end guard) and 202609192001 (dismiss at zero):
"The new fix still doesn't update the live activity widget when the phone is idle."

**Cause: the server can only update a card whose update token the phone has handed
it, and an idle phone hands over nothing.** When the server push-to-starts a card,
iOS is supposed to wake the app in the background so it can register the new card's
token. On this phone that registration happens only when the app is already
awake; when the phone is idle it never arrives, so the server's next updates go to
the previous card's dead token (APNs still says 200) and the visible card freezes.

## Evidence (`~/.lfg/liveactivity.log`, `~/.lfg/live-activity-tokens.json`)

For every server `start` today, did the phone register a token or react within 90 s?

| start (UTC) | population | reaction |
|---|---|---|
| 04:09:30 | bbf87dab | adopted +2 s (old build; then ended) |
| 04:12:02 | 41497ff4, bbf87dab | **nothing** |
| 04:16:48 | 79b6a3bd | adopted +8 s |
| 04:39:20 | 41497ff4 | **nothing** |
| 06:35:53 | 41497ff4, 79b6a3bd | **nothing** |
| 06:46:33 | 0f7b518d | **nothing** |
| 06:53:10 | 41497ff4 | **nothing** |
| 07:52:17 | 41497ff4 | adopted +3 s |
| 08:07:05 | 79b6a3bd | **nothing** |
| 11:25:24 | e35f3997 | adopted +1 s (Eugene using the app, 19:25 HKT) |
| 11:30:54 | e35f3997 | adopted +2 s |
| 11:35:04 | e35f3997 | **nothing** |
| 11:37:55 | e35f3997 | **nothing** |
| 12:05:52 | bbf87dab | **nothing** — last update-token registration 11:30:56, last push-to-start registration 11:55:44 |

9 of 14 starts got no token back. After 12:05:52 the server holds `current` for a
card it cannot address: every `update` it sends goes to token `4006a6e1`, minted
for the card that was ended at 12:03. The end guard is doing its job (no
`client-ended` after any of these), the veto is quiet, all sends are 200. The
phone simply never tells the server how to reach the new card.

Whether the app is not launched at all (Apple's doc promises a wake but gives no
guarantee; force-quit and power state are undocumented) or is launched and its
registration request through the Cloudflare tunnel fails inside the short
background window — the server cannot tell, and neither fix is under its control.

## What Apple provides for exactly this (iOS 18+): broadcast channels

From the ActivityKit and UserNotifications docs (fetched 2026-09-19):

- "For devices running iOS 18 and iPadOS or later, you can add `input-push-channel`
  with the appropriate channel ID to start a Live Activity and listen for updates on
  a channel. After you send this payload, you can send updates on the channel to
  update a Live Activity."
- App-started activities subscribe the same way: `Activity.request(…, pushType:
  .channel(channelId))`.
- Updates go to `POST /4/broadcasts/apps/<bundleId>` on `api.push.apple.com` with
  headers `apns-channel-id`, `apns-push-type: liveactivity`, `apns-priority`,
  `apns-expiration`, same JWT auth. Payload is the same `aps` shape we send today.
- Channels are created once: `POST /1/apps/<bundleId>/channels` on
  `api-manage-broadcast.push.apple.com:2196` with
  `{"message-storage-policy": 1, "push-type": "LiveActivity"}`; the id comes back in
  the `apns-channel-id` response header. Policy 1 stores the most recent message
  for up to 8 h, so a card that comes online late still gets the latest state.
  Sandbox and production channels are separate.
- Prerequisite: "Enable Broadcast Capability under Push Notifications" on the
  identifier in Certificates, IDs & Profiles — a developer-portal toggle, not an
  entitlement or profile change.

With a channel there is **no per-card token at all**: the server publishes the fleet
state to one channel per APNs environment, and every fleet card — push-started or
app-started, on every device Eugene owns — receives it, awake or not. The
background wake becomes irrelevant to updates. The push-to-start token is still
needed to *create* a card on an idle phone, but that token is registered at app
launch and is already reliable (all today's starts were accepted).

## Proposal

1. **Server: broadcast channel per env.** `src/push/liveactivity.ts` gains channel
   management (create once, persist the id under `~/.lfg/live-activity-channel-<env>.json`,
   read-back on boot to confirm it still exists) and a `sendLiveActivityBroadcast`
   that POSTs `update`/`end` to `/4/broadcasts/apps/<bundleId>` with
   `apns-channel-id`. `start` pushes carry `input-push-channel`. The watcher's
   `applyLiveActivityDecision` sends updates/ends to the channel instead of the
   token list. Token registration endpoints stay for one release as a fallback.
2. **Client: subscribe app-started cards to the channel.** The server exposes
   `GET /api/push/live-activity/channel` → `{ channelId }` per env; the app fetches
   it at launch (cached) and passes `pushType: .channel(id)` in
   `FleetActivityController.sync()`; if it has no channel yet it falls back to
   `.token` as today.
3. **Manual step, Eugene:** enable Broadcast Capability on `com.eugenechan.lfg` in
   the developer portal. One toggle; irreversible in the sense that disabling later
   deletes all channels.
4. **Priority 5 for routine count changes**, 10 only when `needsInput` rises — keeps
   us inside the hourly Live Activity budget (2,772 updates on 09-16 would have been
   throttled).

Effort: server ~half a day with tests (channel client, payload builders, watcher
send path); client ~an hour; one TestFlight. Verification: the trace log shows
`broadcast update … 200` and the phone's card changes with the phone untouched —
the first test that can actually be run without opening the app.

## Ruled out today

- Server not pushing: it pushes on every change, all 200.
- App ending the card (fixed this morning): no `client-ended` after any start.
- Veto blocking: no `start-vetoed` since 12:00 UTC.
- Wrong priority/topic/frequent-updates key: all correct.
