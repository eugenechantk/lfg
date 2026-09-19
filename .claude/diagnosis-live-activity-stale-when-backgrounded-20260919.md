# Diagnosis — fleet card stale (or absent) while the app is backgrounded (2026-09-19)

Eugene: "the live activity widget sometimes does not get updated as sessions get
done. I have to open the app to check. That's probably because the app is not
foregrounded anymore and can't update the live widget status. Hence we need
server to help."

**The server already helps, and its pushes arrive. The app kills the card the server
just started, within seconds, from a background wake with an empty session store.**
Same family as `diagnosis-live-activity-background-updates.md` (2026-08-06) and
`diagnosis-live-activity-duplicate-cards-20260918.md`; this is the precise trigger.

## Evidence (`~/.lfg/liveactivity.log`, Pro, after the 08:56 restart)

Every start is followed by the phone registering the new card's token ("adopted")
and then reporting "ended" 1–5 s later:

```
03:47:03 decide start   working=1 rows=[56c91326]
03:47:04 client-ended   hadActive=false population=[56c91326]   ← before the send even completed
03:47:08 client-ended   hadActive=true  population=[56c91326]
03:49:08 decide start   working=1 rows=[56c91326]
03:49:11 adopted                                                 ← app woke, registered the update token
03:49:11 client-ended   hadActive=true  population=[56c91326]
03:49:13 client-ended   hadActive=true  population=[56c91326]
04:09:30 decide start   working=1 rows=[bbf87dab]
04:09:32 adopted
04:09:36 client-ended   hadActive=true  population=[bbf87dab]
```

32 `client-ended` in the first hour after restart, all against populations of size
one; then 266 `start-vetoed` lines as the server (correctly, per this morning's
change) refuses to restart for the same population. All APNs sends are 200; no
`no-tokens`, `partial` or `none-accepted` events. Delivery is not the problem.

## Mechanism

1. Server counts a working session, has no card → APNs **push-to-start**. The card
   appears on the Lock Screen. ActivityKit **launches the app in the background**.
2. `LFGApp` → `FleetActivityController.configure()` → `syncNow()` **immediately at
   launch**. `SessionStore.sessions` is `[]` at init; hydration from GRDB and the
   first REST fetch are async and have not run yet.
3. `sync()`: a fleet card exists, `activeTotal == 0` → `endCurrentActivity` +
   `reportActivityEnded`. Card gone ~2 s after it appeared.
4. Before today: server nulls its memory and push-starts again → duplicate cards,
   the visible ones stale (only the newest token is addressable). After today's
   veto: server refuses → **no card at all** until the app is opened in the
   foreground, creates one itself, and registers a token ("adopted"). That card
   then updates fine from the server — until the next background wake kills it.

So "I have to open the app" is literally true: the app is the only thing that can
put a card back, because the app is what keeps removing it.

Not the cause (checked): APNs priority is 10 with `apns-push-type: liveactivity`;
`NSSupportsLiveActivitiesFrequentUpdates` is set; tokens are per-env and
superseded on registration; the Air never pushes.

## Fix (client; the server cannot know the phone's store state)

**`FleetActivityController.sync()` must not end a card on a count it cannot vouch
for.** Ending is the one irreversible move (the token dies; resurrection needs a
push-to-start and a background wake — the exact chain that misfires). Gate it:

1. **Store freshness.** End only after the store has completed at least one live
   sessions fetch since launch. Until then, treat the count as *unknown*: update the
   card if content differs (rows from GRDB are fine to show), never end it.
2. **Host reachability.** Do not end while any host is connecting, known-down, or
   inside its grace window — the count is unknown then, not zero.
3. **Debounce.** Zero must hold for 60 s (mirror the server's
   `FLEET_END_DEBOUNCE_S`) before ending. A blip at a turn boundary is not "done".
4. **Report only real ends.** `reportActivityEnded` fires only from that gated path.

Keep the server veto — it is doing exactly what it should — but make the trace
line fire once per population, not every tick (266 lines in an hour).

Expected effect: the push-started card survives its own arrival, the server keeps
addressing it (one token, adopted on registration), sessions finishing show up as
`update` pushes while the phone is in a pocket, and an all-idle fleet ends the
card once, 60 s after the last session stops. This also removes what remains of
the duplicate-card loop at its source, so the 09-18 dedupe becomes a backstop.

## Order-of-operations note

This morning shipped fix 1 (client dedupe) and fix 2 (server veto) from the 09-18
diagnosis but not fix 4 (client end debounce). The veto amplifies the client's
eager end: with the restart loop closed, an eager end now means *no* card instead
of a duplicate one. Fix 4 should have shipped alongside 2. Logged in the
improvement log.
