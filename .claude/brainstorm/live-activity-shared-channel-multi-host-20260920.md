# Brainstorm — one fleet card, several hosts, one shared broadcast channel (2026-09-20)

Eugene: "The phone must need to talk to all the hosts because different hosts are
running different sessions. Can't the two hosts share the same broadcast channel to
update the live activity widget?"

## Can they share a channel? Yes.

A broadcast channel is addressed by `apns-channel-id` + bundle id, authenticated with
the team's APNs key. Both Macs already hold the same key (`~/.lfg/AuthKey_…p8`) and the
same APNs settings, so either can `POST /4/broadcasts/apps/com.eugenechan.lfg` with the
Pro's channel id and the card will take it. Nothing in Apple's model ties a channel to
one sender.

## Why sharing alone makes it worse

A Live Activity push **replaces the card's whole content state**; iOS does not merge.
If each host publishes its own view:

- the card flips between "Pro's sessions" and "Air's sessions", last writer wins;
- whichever host reaches zero first broadcasts `end` and dismisses the card for both —
  today's kill loop, now from two directions.

So a shared channel is necessary but not sufficient. **Whoever publishes must publish
the whole fleet.** That is the missing piece either way.

## Design

1. **One channel per APNs environment, shared by every host.** The default host creates
   it (already does). The app, which knows every host, hands the channel id to the
   others (`POST /api/push/live-activity/channel/adopt`), so no server-to-server secret
   exchange is needed for this part.
2. **The phone registers its push-to-start token with every host**, not only the
   default one. Any host must be able to start a card — today the Pro was offline for
   hours and nothing could. (Registering with all hosts was removed because each host
   then started its own card; rule 4 is what makes it safe again.)
3. **Each host's watcher reduces over the whole fleet**: its own sessions plus each
   peer's `GET /api/sessions`, polled every few seconds. A peer that stops answering
   contributes nothing (its sessions cannot be progressing visibly anyway) after a
   short grace.
4. **Exactly one publisher at a time.** Deterministic, no election protocol: among the
   hosts a watcher can currently reach (itself included), the one with the smallest
   host id publishes; the rest compute but stay silent. When the Pro drops off, the
   Air sees it gone on the next poll and takes over within seconds; when it returns,
   the Air goes quiet again. Both publishing for a moment during a handover is
   harmless because they publish the same union and the payload `timestamp` orders them.
5. **`end` only from the publisher, only when the union is empty.**
6. **The app keeps doing what it does** when awake (it already sees every host), and
   stops reporting started/ended to a single "default" host — it reports to all, or
   the reports go away entirely once servers see the whole fleet.

## What it needs that does not exist

- **Server-side peer config.** Hosts are client-side config today. Simplest: the app
  tells each host its peers when it registers (`{ id, url }`), persisted in
  `~/.lfg/peers.json`. Server-to-server reachability: LAN address first (the mosh
  script already pins them), Cloudflare hostname with an Access service token as the
  fallback. This is the real work; everything else is small.
- Peer session rows need `busy`/`prompt` as the REST snapshot already exposes them.

## Rejected

- **One card per host** (each host owns its own card and channel). No peer awareness
  needed, but it is two cards, the island shows only one of them, and its count would
  be per host rather than for the fleet.
- **Merging on the device.** iOS replaces state per push; a widget cannot combine two
  publishers' payloads.

## Stopgap until then

The small server guard from today's diagnosis (never end a card the server did not
fill) stops the Pro killing the app's card. It does not make the card correct while
the phone sleeps.

## Follow-up (same day): "can't each host just publish its own sessions?"

**Start token.** One *current* push-to-start token per app install, not tied to any
server — the same token can be given to every host. It is long-lived but not
permanent: iOS rotates it (three different ones in our store over two days) and the
app re-sends it at launch. A start push is NOT idempotent: every one creates a new
card, which is why only one party may send it.

**Self-reconciling widget: not possible.** A Live Activity is not running code. The
widget extension is a renderer that is handed exactly one thing — the latest content
state — and each push REPLACES that state. It is never shown two payloads, cannot
write state back, and has no supported way to persist a slice between renders. So
"Pro publishes Pro's rows, Air publishes Air's rows, the card shows both" cannot
happen on the device; the merge has to occur before the push.

**Where the merge can live:**

A. *A merge point in the middle (fits Eugene's model).* Each host publishes only its
   own slice — to a small aggregator, not to Apple. A Cloudflare Worker with a
   Durable Object keeps one slice per host with a heartbeat TTL (a dead host's slice
   expires after ~90 s), merges them, and is the single publisher to the channel and
   the single sender of start/end. Hosts need no knowledge of each other, no peer
   config, no leader rule; either Mac can be offline. Cost: a new deployed component
   and the APNs key stored as a Worker secret.
B. *Hosts poll each other* (the earlier design). No new infrastructure, but needs
   server-side peer config, Mac-to-Mac reachability, and the single-publisher rule.
C. *One card per host.* Each host owns its card and channel. Zero coordination, but
   two cards and a per-host count in the island.

Leaning A: it is the only one where "each host just publishes its own sessions" is
literally true, and the only one that keeps working when the default host is down.
