# Diagnosis — "a session is running but the widget does not get spawned" (2026-09-20, 20:26 HKT)

**The card IS spawned — and the Pro's server kills it about a second later, over and
over.** The running sessions are on the Air. The Pro is the only server that can
reach the phone, it counts only its own sessions, it has none, so it concludes the
fleet is empty and broadcasts `end`.

## Evidence

Pro, `~/.lfg/liveactivity.log` (UTC), server started 19:38 HKT on the channel code:

```
12:25:31.944 adopted                                   ← phone: "I created a card"
12:25:32.384 decide end  via=broadcast working=0 needsInput=0
12:25:33.270 broadcast end  channel=wa+dtLTn  200      ← card dismissed (hold is 0)
12:25:34.856 adopted                                   ← app recreates it
12:25:36.467 decide end … 12:25:36.737 broadcast end 200
12:25:58.785 adopted … 12:26:00.659 broadcast end 200
12:26:02.205 adopted … 12:26:03.284 broadcast end 200
```

Pro `/api/sessions`: **0 live sessions**. Air `/api/sessions`: 2 busy — `56c91326`
(Noto) and `bbf87dab` (this session, which migrated to the Air).

Air, its own `liveactivity.log` (the Air's server dates from 19 Sep 20:01, i.e. the
pre-channel code): it does count `working: 2`, but its token store holds only four
**sandbox** push-to-start tokens from 10 July. It tried 30 July-era update tokens,
got `410 ExpiredToken` on all, pruned them, and now writes `decide update` +
`no-tokens` every 2 s. The phone registers with its default host only, so the Air
has never been able to reach it.

## Mechanism

1. App (foreground) sees 2 working sessions across hosts → `Activity.request` on the
   broadcast channel → POST `/api/push/live-activity/started` to the default host.
2. Pro adopts the card (`{ startedAt }`, no content yet).
3. Next tick, `reduceFleetLiveActivity` on the Pro: a card exists, `total === 0`
   (its own host only), hold is 0 → `end`, broadcast, immediate dismissal.
4. App sees no card and 2 active → step 1 again.

This is the "suspended-app card reflects only the default host's sessions" gap,
promoted from cosmetic to fatal by two of this week's changes working exactly as
designed: the zero end-hold (09-19) and the broadcast channel (09-20), which makes
the server's `end` reach the card instantly and every time. Before, that `end` went
to a token that was usually dead.

## Options

**A. Stop the kill loop now (small, server-only).** The server must not end a card it
never populated. An adopted card has no `contentState`; while the server's own count
is zero, leave it alone — the app ends it itself through `FleetEndGate` when its
whole-fleet count is zero. The server still ends cards it filled itself. One branch
in the reducer, tests, restart the Pro. Does not make the card *correct* while the
phone sleeps; it stops the server destroying a correct one.

**B. Make the pushing server see the whole fleet (the real fix).** The default host's
watcher polls its peers' `/api/sessions` and reduces over the union. Needs a
server-side notion of peers (URL + credentials), which does not exist today — hosts
are client-side config. Until this exists, a card maintained by the server shows
only that server's sessions, and a Pro going 1 → 0 will still end a card that Air
sessions need.

**C. Hygiene.** Restart the Air onto current code, and stop non-default hosts from
running the Live Activity half of the watcher — it cannot reach the phone and is
writing two log lines every 2 s. `.env` is in the synced folder, so this needs a
per-host switch rather than `LFG_LIVE_ACTIVITIES=0`.

Recommendation: A today, B as the next piece of work, C alongside A.
