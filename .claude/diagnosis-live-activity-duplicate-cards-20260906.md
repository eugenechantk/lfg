# Diagnosis — two identical fleet Live Activity cards (2026-09-06)

**Symptom.** Lock screen shows two lfg Live Activity cards with identical content ("3 Active",
same three rows, same timestamps). Screenshot taken ~12:46–12:50Z on the phone (TestFlight /
production APNs env).

## Verdict

**A race between the app's local `Activity.request` and the server's push-to-start.** Both
sides independently decide "there is no card and a session is active → make one", and
neither checks the other's work in the ~1–3 s it takes for the app's update-token
registration to reach the server through the tunnel. The device ends up with two activities
carrying the same `fleetId: "fleet"`. Nothing on either side ever collapses them.

Not the cause, but a standing contributor: there are two live **production** push-to-start
tokens in `~/.lfg/live-activity-tokens.json` (`40a3d317…` since 08-13, `4029f948…` since
08-24). They correlate with two production remote-push device tokens (`90dd1f19` created
08-13, `27481610` created 08-23, both still being seen this month) so they are almost
certainly two devices, not one device registered twice — the phone gets one push-to-start per
`start` decision, not two.

## Evidence (`~/.lfg/liveactivity.log`, UTC)

The instance behind the screenshot:

```
12:32:17.216  client-ended  hadActive:false      app foregrounded, synced with 0 active
12:32:18.709  decide start  rows=[a7536cc4]      server tick: current==null, a session is working
12:32:18.832  adopted                            app registered an UPDATE token → it had already
                                                  created a card itself via Activity.request
12:32:19.273  send start → 40a3d317 (prod) 200   push-to-start goes out anyway
12:32:19.489  send start → 4029f948 (prod) 200
12:32:20.093  send start → 80474501 (sbx)  200
12:32:20.266  send start → 80da96dc (sbx)  200
12:32:20.923  update token 40215da8 registered   the push-started activity's token; `supersede`
                                                  drops the app-created one's token
12:32:29+     update → 40215da8 only              server now updates only the newer card
```

`applyLiveActivityDecision` in `src/push/watcher.ts` computes the decision, traces `decide`,
then sends to every start token. It never re-reads `deps.active.current` between the decision
and the sends, so the `adopted` that landed at 18.832 — before the first send — did not stop
the blast. The `decide → adopted → send` ordering is visible in the log 48 times since the
log began, 12 of them on 09-05/09-06.

Why both cards look identical: `FleetActivityController.updateCurrentActivity` (iOS) loops
over **every** activity with `fleetId == "fleet"` and updates each one while the app is
alive, so on the phone's next foreground both cards are re-rendered with the same snapshot.
Only one of them (`40215da8`) is being updated by the server while the app is suspended; the
other freezes until the app wakes again.

## Why neither side catches it

- **Server.** `noteFleetActivityStarted` (adopt) only prevents a start on the *next* tick. A
  tick already past the reducer is committed. The `start` path also deliberately keeps
  "any accepted" semantics and re-sends starts freely on `client-ended`, which is why this
  fires many times a day rather than once.
- **Client.** `sync()` guards on `currentActivityExists` — "at least one" — and `Activity.request`
  is unconditional beyond that. When a push-to-start lands after the app already made a card
  (or the reverse), nothing ends the extra. `LiveActivityManager.track` happily registers a
  token for every activity it sees; `supersede` on the server then keeps only the last one,
  so the server's view is "one card" while the device has two.

## Fix (recommended, both halves)

1. **Client dedupe at the boundary** (the durable fix — ordering cannot be controlled across
   the tunnel). In `FleetActivityController`, whenever `Activity<LFGFleetAttributes>.activities`
   holds more than one `fleet` activity, end all but one (`dismissalPolicy: .immediate`) and
   re-POST the survivor's `pushToken` to `/api/push/live-activity/update-token` so the server's
   `supersede` keeps the right token. Run this in `sync()` and from `LiveActivityManager`'s
   `activityUpdates` stream (which is where a push-started duplicate first becomes visible
   while the app is backgrounded).
2. **Server: re-check before each start send.** In `applyLiveActivityDecision`, if
   `decision.action.event === "start"` and `deps.active.current` is non-null at send time
   (and again per token inside the loop), skip the send and trace `start-superseded`. Closes
   the in-flight window that produced this exact instance; the client dedupe covers the rest.

Optional hygiene: registration carries no device id (noted in `liveactivity-store.ts`), so
the two production push-to-start tokens cannot be told apart server-side. Not needed for this
bug; would matter if the second device ever stops opening the app and its token rots.

## Not the cause (checked)

- Two hosts each push-to-starting: token registration goes to the default host only
  (`LiveActivityManager.sendStartToken`), and the log is a single host's.
- Stale per-session activities from the old build: `endRetiredPerSessionActivities` runs on
  configure; the cards in the screenshot are the fleet card shape.
- Two push-to-start tokens for one device: token ages correlate with two distinct
  production device tokens that are both still being seen (09-03 and 09-06).
