# Diagnosis — multiple fleet Live Activity cards on the phone (2026-09-18)

Eugene: "why do I have 5 live activity widgets? Seems like we are spawning a new one
for every new session that is running."

**Short answer:** not one per session — one per *start push*. The phone tells the
server "my card ended", the server forgets the card and push-to-starts a fresh one,
and nothing ever ends the cards the phone already has. That loop has been running
15–57 times a day since at least 2026-09-07. It correlates with session activity
because a start push only fires when the server counts ≥1 working session.

## Evidence (`~/.lfg/liveactivity.log`, Pro; the Air has no log — it never pushes)

Per-day decisions:

| day | start | update | end | client-ended | adopted |
|---|---|---|---|---|---|
| 09-14 | 15 | 39 | 9 | 27 | 21 |
| 09-15 | 15 | 71 | 6 | 63 | 45 |
| 09-16 | 42 | 2772 | 443 | 82 | 22 |
| 09-17 | 57 | 147 | 12 | 102 | 31 |
| 09-18 (to 15:45Z) | 13 | 28 | 1 | 27 | 12 |

The cycle, verbatim from today (UTC):

```
15:19:37 client-ended hadActive=true
15:19:54 decide start tokens=3 working=1 rows=[1b55623c:working]
15:19:54 send start 40a3d317 production 200
15:19:55 send start 4029f948 production 200
15:19:56 adopted
15:19:56 send start 40aaea70 production 200
15:23:31 decide update tokens=1 → 404cee4c        ← the NEW card's token
15:25:16 client-ended hadActive=true
15:25:31 decide start tokens=3 …                  ← another new card
15:36:31 client-ended … 15:36:47 decide start …   ← another
15:41:17 client-ended … 15:41:32 decide start …   ← another (update token now 40ed156f)
```

Each cycle's update token is different (`4098eb77` → `404cee4c` → `40ed156f`):
each start created a *new* activity on the phone, and only the newest one is
addressable by the server afterwards. The older cards sit there with stale content
until ActivityKit expires them (hours). Five cards = five cycles inside the expiry
window.

Three production `pushToStart` tokens are in the store (`live-activity-tokens.json`),
with no device identity recorded. After each start only ONE of them re-registers
(its `updatedAt` bumps ~1 s after the send), and it is a different one each cycle —
consistent with one phone whose push-to-start token rotates, not three devices. APNs
returns 200 for all three, so if iOS honours a start on a rotated token this
multiplies cards per cycle; unproven either way.

## Mechanism

1. **Phone ends and reports.** `FleetActivityController.sync()` (`ios/LFG/FleetActivityController.swift`)
   ends the card the moment its own `activeTotal == 0` and POSTs
   `/api/push/live-activity/ended`. No debounce, no "is the count trustworthy" check.
2. **Server forgets and restarts.** `noteFleetActivityEnded` nulls `fleetActive.current`
   (`src/push/watcher.ts`); the next tick's `reduceFleetLiveActivity` takes the
   `!active` branch and sends `start` — there is a 60 s debounce on *ending* the
   server's card (`FLEET_END_DEBOUNCE_S`) but none on *restarting* after a client end.
3. **Phone never dedupes.** A push-started card arrives; `LiveActivityManager.track`
   only registers its token. `sync()` updates/ends *all* fleet activities, but only
   when it runs — and it ends them only at `activeTotal == 0`, at which point it is
   already in step 1 again.

Why the phone's count reaches zero while the server's is ≥1 (the two ladders are
shared — `SessionDisplayState.resolve` ↔ `sessionDisplayState` — so it is the inputs
that differ):

- **Hidden directories.** The phone counts `store.filteredSessions` (muted dirs
  removed); the server reducer counts every live session. The sessions in today's
  start rows were `~/dev/inbox`, `~/dev/personal/Noto`, a Noto worktree, and this lfg
  session. If `~/dev/inbox` is muted on the phone, the phone sees 0 while the server
  sees 1 → it ends the card, the server restarts it, repeat every tick the phone
  syncs. This is the best fit for the `hadActive:false` double reports at 15:13:37 /
  15:13:46 (the phone ended twice in 10 s against a server that had nothing).
- **Unreachable-host retraction.** `rebuildSessions` blanks `busy` for sessions on
  known-down hosts (`MultiHost.unreachableLiveSessionIds`), so a Pro blip reads as
  "0 working" on the phone and triggers the same end → restart.
- **Cold launch / store rebuild** with an empty session list momentarily.

None of this is new code: the churn predates every commit since 09-10 that touched
these files.

## Recommended fix (not applied — Eugene asked "why", not "fix")

Ordered by leverage; 1 alone stops the visible symptom.

1. **Client dedupe (iOS).** In `LiveActivityManager.track`/`activityUpdates`, when more
   than one `LFGFleetAttributes` activity exists, end all but the most recently
   started one. One fleet card is the invariant; enforce it at the boundary where
   cards appear ([[enforce-at-the-boundary]]).
2. **Client end debounce (iOS).** `sync()` should require `activeTotal == 0` to be
   *sustained* (60 s, mirroring the server's `FLEET_END_DEBOUNCE_S`) and should not
   end while any host is known-down — the count is unknown then, not zero. Memory
   [[live-activity-end-is-not-free]] already says "never end eagerly"; the client
   still does.
3. **Server: don't restart on the client's word alone.** After `client-ended`, only
   push-to-start again if the server's count is nonzero *and* stays nonzero for the
   debounce window; and apply the same hidden-dir filter the phone uses (the server
   already has `hidden-dirs.ts` for the list — the fleet reducer does not use it).
4. **Server: one push-to-start token per device.** The store keeps the newest 3 per
   env with no device id; register tokens with a stable device id so a rotation
   *replaces* rather than *adds*. Until then every start goes to three tokens that
   are probably one phone.

Verification plan when fixing: on-device only (a sim cannot receive APNs). Watch
`liveactivity.log` for `client-ended` → `decide start` pairs to stop, and count
`Activity<LFGFleetAttributes>.activities` on launch (log it) to confirm it is 1.

## Side note — simulator Live Activities today

`LFG_LA_MOCK` never fired on the house iPhone 17 Pro sim: (a) the `widgets` simslim
category (`liveactivitiesd`, `chronod`) was disabled — re-slimmed with
`--except web,store,widgets`; (b) even after that, and after flipping Settings ▸ lfg ▸
Allow Live Activities on, `ActivityAuthorizationInfo().areActivitiesEnabled` still
read `0` on the next `flowdeck run` (which reinstalls the app). Unresolved; logged in
the improvement log. The mock's diagnostics now go through `NSLog` because FlowDeck's
log capture only shows the bundle-id OSLog subsystem and this file's logger is under
`dev.omg.lfg`.
