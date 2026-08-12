# Phantom sessions: an offline host resurrects every session it has ever had

Session 20260811-035041. Reported symptom, in Eugene's words:

> When the Air is offline, sometimes these sessions are shown as running, even
> though they are very old sessions and are not running. They only show up when
> the Air host is offline.

Two claims in there, and the second is the load-bearing one. Not "these sessions
*stay* Working" (that was
[the 2026-08-08 bug](diagnosis-duplicate-sid-and-offline-working-20260808.md),
already fixed in the working tree by the unreachable-retraction in
`rebuildSessions`) but "these sessions **only show up** when the Air is offline".
Sessions that are *absent* while the host is up and *appear* when it goes down
cannot be explained by a frozen last-good snapshot — the last good snapshot is by
definition the live list from moments before the outage. Something else is
supplying them.

## Ground truth

The reported condition holds right now:

```
$ tailscale status
100.75.162.40  eugenes-macbook-air  …  offline, last seen 1h ago, tx 13416 rx 0
```

## Mechanism

The phantom rows come out of the **GRDB store, which is append-only for
sessions**. Nothing in the app has ever deleted a row from that table:

```
$ grep -rn "DELETE FROM sessions\|deleteSessions\|removeSessions" --include="*.swift" ios/
(no matches)
```

`sessionListSQL` (`LFGStore.swift:435`) has no `LIMIT` and no age predicate, and
`upsertSessions` (:59) is insert-or-update only. So the table accumulates every
session the Air has ever reported, forever.

The two paths that read and write it disagree about what it means:

| | code | semantics |
| --- | --- | --- |
| write | `applyHostFetch` :1685 → `upsertSessions(fetchedSessions, …)` | **merge** — adds this fetch's rows to whatever is already there |
| write | `applyHostFetch` :1689 → `lastSessionsByHost[id] = fetchedSessions` | **replace** — the in-memory cache is exactly the live list |
| read | `hydrateFromStore` :644 → `lastSessionsByHost[id] = stored.map(...)` | seeds the *live-snapshot cache* from the *merged accumulation* |

Line 1689 and line 644 write the same variable. One is the host's live list; the
other is the union of every live list ever observed. `upsertSessions` is the only
production writer of that table (`grep` finds exactly one non-test call site), and
it is handed a complete snapshot every time — so the merge semantics were never
what the caller meant.

### Why it only fires when the Air is offline

`hydrateFromStore` is guarded:

```swift
guard lastSessionsByHost[host.id] == nil, let stored = byHost[host.id] else { continue }
```

It seeds *only* a host with no in-memory snapshot yet. So:

- **Air reachable.** The first `.ok` fetch overwrites the seed with the real live
  list (:1689, a replace). Whatever hydration invented is gone within one poll —
  which is why these sessions are invisible in normal use.
- **Air unreachable at cold launch.** No `.ok` fetch ever lands, nothing
  overwrites the seed, and `lastSessionsByHost[air]` stays equal to *every session
  the Air has ever had*. Those rows flow through `rebuildSessions` into `sessions`
  and onto the list.

That guard is also the "sometimes". If the app was already running when the Air
dropped, `lastSessionsByHost` holds a genuine recent snapshot and nothing is
resurrected. The bug needs a **cold launch during the outage** — the phone
relaunching the app while the Air is down, which is exactly the intermittency
reported.

### Why they read as "running"

`busy` is persisted verbatim (`sessionArguments` :520) and rehydrated verbatim
(`session(from:)` :716). A session that happened to be busy the last time it was
ever seen is restored as `busy: true`.

The unreachable-retraction added for the 2026-08-08 bug does eventually clear
this, but not immediately: it is gated on `isNotKnownDown`, and at cold launch the
host sits in its grace window (`connecting`, not yet `offline`) for the first
several seconds. During that window the frozen `busy: true` seeds `busy[sid]` and
the rows render in **Working**. Once the state machine promotes the Air to
`offline`, the next `rebuildSessions` retracts them.

So the retraction is doing its job on the *state*; the defect that survives is the
*existence* of the rows. Even fully retracted, the list still shows a pile of
long-dead sessions attributed to the Air, which is the substance of the complaint.

## Fix

Make the persistence match the semantics the single caller already has: a host
fetch is a **snapshot**, not a delta.

Add `LFGStore.replaceSessions(_:hostId:)` — in one transaction, upsert every row
in the snapshot, then delete that host's rows that the snapshot did not mention.
`applyHostFetch` calls it instead of `upsertSessions`. Hydration then seeds from a
table that mirrors each host's last *observed live list*, which is exactly the
thing `lastSessionsByHost` is documented to hold.

Notes on blast radius:

- **No cascades.** The v1 schema (:372) declares no foreign keys, so dropping a
  `sessions` row leaves `messages` and `readState` untouched. A session that
  disappears and returns keeps its cached transcript and its read mark. This is
  what we want, and it is why the delete can be narrow.
- **Closed sessions are unaffected.** They arrive over
  `GET /api/sessions/resumable` into `closedFirstPageByHost` and are never written
  to this table — the only writer is the `GET /api/sessions` live list.
- **Host migration is safe.** A synced `~/.claude/projects` means two hosts can
  report the same session id, and the row's `hostId` is overwritten by whichever
  fetch landed last (`LFGStoreTests:62-70` pins this). The delete is scoped
  `WHERE hostId = :hostId AND sessionId NOT IN (snapshot)`, so a row that has
  migrated to host B is not in host A's scope and cannot be deleted by A's fetch.
- **`upsertSessions` stays.** Its partial-enrich behaviour is pinned by
  `testPartialSessionUpdateDoesNotNullExistingColumns` and costs nothing to keep.

This does not attempt to shorten the grace-window flash of `busy: true`. With the
phantom rows gone the only sessions left to flash are the Air's genuinely-recent
ones, where "we last saw this working" is a defensible thing to show for a few
seconds before the host is confirmed down.

---

## Addendum — the server proves the rows are client-side

Added after Eugene pushed back on a mid-session over-correction of mine. I had
briefly doubted the diagnosis above on seeing a screenshot: the four phantom rows
were **not dimmed** and their host chips were **gray**, not orange, which means
the Air was not in `.offline` — so the unreachable-retraction could not have
fired, and I wondered whether the rows were instead coming from the Air's real
live list (`tailscale status` showed it reachable within the hour).

The server settles it. `/api/sessions` will not call a session busy unless its
transcript moved in the last twelve seconds:

```ts
// src/sessions.ts:622
const REST_BUSY_WINDOW_MS = 12_000;
…
const transcriptRecent =
  lastActivityAt != null && Date.now() - lastActivityAt < REST_BUSY_WINDOW_MS;
```

A row that reads `busy: true` with `lastActivityAt` a **week** old is therefore a
claim no live fetch can produce, on any host, reachable or not. The only source
that can produce it is the client's own SQLite, which is precisely the mechanism
above.

The undimmed gray rows are a second, independent thing rather than a
counter-example: the screenshot was taken inside the 30s grace window
(`HostLinkPolicy.bannerAfter`), where the Air sits in `.unknown`/`.degraded`.
`isNotKnownDown` is still true there, so the retraction correctly holds off — it
is debouncing a possible blip. Both observations are consistent with one cold
launch during an outage.

### Second fix: never rehydrate `busy`

The store fix stops the *accumulation*, but the direct cause of "shown as
running" is that `busy` survives a round-trip through disk at all.
`session(from:)` now forces `busy: false`.

`busy` is an assertion about what an agent is doing *right now*; a row read back
off disk is by definition not now. The server encodes exactly this with its
12-second window, and the client was contradicting it by persisting the flag
indefinitely. Nothing is lost — a session that really is running has `busy`
re-asserted by the host's next successful fetch, one poll later.

This is the guard the retraction structurally cannot be: the retraction waits for
a host to be *known* down, which by design takes 30s, and the phantoms are on
screen for that entire window. A rehydrated `busy` is never credible, so it never
needs to wait for a host verdict.

### Predicate mismatch (noted, not fixed)

`StatusBadge` paints the header chip from `hostState.isLive` (true only for
`.live`) while the row dim, the composer, and the retraction all read
`showsOfflineBanner` (true only for `.offline`/`.noNetworkSustained`). Those are
not complements: `.unknown`, `.connecting`, `.degraded` and `.noNetwork` all sit
between them, and in all four the header says "down" while everything else treats
the host as fine. That is what makes the screenshot look self-contradictory. It is
cosmetic next to the bug above and is left alone here; the honest fix is to make
the header chip tri-state like `ConnectionStatus` rather than binary.
