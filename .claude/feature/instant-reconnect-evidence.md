# Instant reconnect — evidence

Feature doc: [instant-reconnect.md](instant-reconnect.md). Session 2026-08-01.

## SC1 — server sends its first byte on connect, not 10s later ✅ VERIFIED

Clean A/B on the same machine, both with a *caught-up* cursor (`since = head`, i.e.
nothing to replay — the "no sessions running" case):

| Build | Command | First **body** byte |
| ----- | ------- | ------------------- |
| pre-patch (`lfg serve` running since 02:16) | `GET :8766/api/events?since=28913` | **10.004s** — `b':'` (the 10s interval heartbeat) |
| patched (scratch server, isolated `LFG_DATA`) | `GET :8799/api/events?since=207` | **0.001s** — `b': hb 207\n\n'` |

Measured with `urllib` + `read(1)` — `curl`'s `time_starttransfer` measures the
response *header*, which SSE sends immediately in both builds, and reported a
misleading 1.5ms for the unpatched server. Reading one body byte is the honest
probe.

This is the delay that made the symptom session-dependent: with sessions running
there is replay to send, so the stream's first byte is immediate and the badge
flips at once. Idle → silence → the client can't distinguish an established
stream from a black-holed dial for 10s.

## SC6 — test suites ✅ VERIFIED

- `cd ios/LFGCore && swift test` → **165 tests, 0 failures** (was 164; added
  `testQuietRedialSitsBetweenOneHeartbeatAndTheStaleWatchdog`, updated the
  cold-probe cadence test for the new 5-tick default).
- `bun test` → **150 pass, 0 fail**.
- `flowdeck build` (iOS app, Debug, iPhone 17 Pro sim) → Build Completed with the
  final code, including the `syncLinks()`-first reordering.

## C4 — "Connecting…" tri-state ✅ OBSERVED LIVE

During the first timed run the status dot rendered **gray `(142,142,147)`** with
the app freshly foregrounded and no host result yet, then went **green
`(52,199,89)`**. Before this change that window rendered orange "Offline".

## SC2 / SC4 / SC5 — ❌ NOT VERIFIED (host unusable for timing)

The end-to-end latency numbers could not be trusted on this machine today:

| Symptom | Reading |
| ------- | ------- |
| Load average | **325 → 748** over the session |
| Booted simulators | **23** (parallel agent sessions; each iOS 26.3 runtime boots ~30 daemons) |
| Disk | **99% full**, 16Gi free on the data volume |
| Production `lfg serve` | `/api/sessions` took **25s** to answer over loopback |
| Scratch `lfg serve` | `/api/sessions` took **6.7s** over loopback |
| Simulator | screen captures degraded to 7s each, display went black and stopped updating |

One measurement did complete before the machine degraded (patched server, patched
client, background 35s → reopen): **gray at +2.05s, green at +10.37s**. That run
is *not* evidence for or against the fix — its host's `/api/sessions` was hanging
for 20s, so the REST probe path was dead, and the app was competing with 20+
simulators for CPU. It did, however, expose a real ordering bug that is now fixed:
`start()` used to `await` local-store hydration and the outbox replay *before*
dialing the links, putting seconds of disk and network work in front of the
fastest proof of life. `syncLinks()` now runs synchronously, first.

**To finish verification** (on an unloaded host): install the build, background
the app >25s, reopen, and sample the status dot —
`scratchpad/reconnect_probe.py` does exactly this and prints the timeline.
Expect green within ~1s. Then stop the host's `lfg serve` and confirm the badge
holds "Connecting…" for the burst (~15s) before turning orange "Offline" (SC4),
and restart it and confirm green returns within a few seconds without touching
the app (SC5).

## Host health note (independent of this change)

A host under load 700 with a 99%-full disk takes tens of seconds to answer
`/api/sessions`. From the phone that is indistinguishable from "the host is not
connected" — worth clearing 23 stale simulators and disk space regardless of
this fix.
