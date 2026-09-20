# Feature: fleet-aggregator-worker

Diagnosis: `.claude/diagnosis-live-activity-card-killed-by-default-host-20260920.md`.
Design discussion: `.claude/brainstorm/live-activity-shared-channel-multi-host-20260920.md`.
Tier: product.

## User Story

As the phone's user with sessions on more than one Mac, I want one fleet card that
shows every host's sessions and stays correct while the app is asleep and while any
one Mac is off, so I never have to open the app to learn the fleet's state.

Eugene, 2026-09-20: "can we have a small cloudflare worker that aggregates the server
sending, and that sends to the broadcast channel … And then the phone should send the
start token and refreshes with the workers, not to the hosts."

## Why a Worker

A Live Activity push REPLACES the card's whole content; iOS never merges two senders.
So with sessions on two hosts, no single host can publish a correct card, and a host
with zero of ITS sessions ends a card the other host needs (the 20:25 kill loop). The
merge must happen before the push, and exactly one party may push — especially
`start`, which is not idempotent. A Durable Object is that one party, and it stays up
when either Mac is asleep.

## User Flow

1. Each lfg host, every 2 s tick, PUTs only its own active rows to the Worker when
   they change, plus a 30 s heartbeat. It makes no Live Activity decision locally.
2. The Worker keeps one slice per host (90 s TTL), merges them, and decides
   start / update / end over the union with the same rules the server used.
3. `start` goes to the phone's push-to-start token (with `input-push-channel`);
   `update` / `end` go to the broadcast channel. Priority 10 for start, end, first
   fill and a new question; 5 for routine count changes.
4. The phone registers its push-to-start token **with the Worker**, keyed by device id
   so a rotation replaces rather than adds; fetches the channel id from the Worker;
   reports card start/end to the Worker. It learns the Worker's address and key once
   from any reachable host and caches them.
5. Builds that predate this still talk to their default host, which forwards
   start-token / started / ended to the Worker and hands out the Worker's channel.

## Success Criteria

- [x] SC1: the Worker can reach APNs — **Verify by:** `GET /v1/probe` returns
  `400 BadDeviceToken` (HTTP/2 + ES256 provider token accepted).
- [x] SC2: union, TTL, mid-move dedupe, ordering, start/update/end/veto, priorities —
  **Verify by:** `workers/fleet-aggregator/src/reduce.test.ts`.
- [x] SC3: Worker payloads equal the server's builders — **Verify by:** same file
  (imports `buildStart`/`buildUpdate`).
- [x] SC4: a host in slice mode publishes its slice and sends nothing to APNs
  itself; unchanged slices wait for the heartbeat; failures retry next tick —
  **Verify by:** `src/push/fleet-slice.test.ts`.
- [x] SC5: the app's Worker requests (token+deviceId, channel GET, started, ended,
  config parsing, https-only) — **Verify by:** `FleetAggregatorClientTests`.
- [x] SC6: suites green — `bun test src/push workers/fleet-aggregator`, `tsc`,
  LFGCore `swift test`.
- [ ] SC7: live, server half: both hosts' slices visible in `GET /v1/state`.
- [ ] SC8: live, end to end: with the app closed and sessions on the Air only, a card
  starts on the phone, updates as sessions finish, and ends at zero — **Verify by:**
  Worker trace (`decide` → `send start 200` → `broadcast update 200` → `broadcast end
  200`) plus Eugene's phone.

## Implementation

- `workers/fleet-aggregator/` — `reduce.ts` (pure), `apns.ts` (WebCrypto ES256 +
  fetch), `index.ts` (Durable Object `FleetAggregator`, bearer-authenticated routes:
  `PUT /v1/hosts/:id/slice`, `POST /v1/start-token`, `GET /v1/channel`,
  `POST /v1/started`, `POST /v1/ended`, `GET /v1/state`, `GET /v1/probe`).
  Deployed at `https://lfg-fleet-aggregator.me-0e2.workers.dev`. Secrets: `AGG_SECRET`,
  `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `CHANNEL_PRODUCTION`.
- `src/push/fleet-slice.ts` — `aggregatorConfig`, `FleetSlicePublisher`,
  `aggregatorRequest`. `watcher.ts`: `collectFleetRows` extracted and shared;
  `TickDeps.slice`; slice mode when `LFG_FLEET_AGGREGATOR_URL` +
  `LFG_FLEET_AGGREGATOR_SECRET` are set (both in the synced `.env`).
- `serve.ts` — forwards legacy registrations; `/channel` answers from the Worker;
  new `GET /api/push/live-activity/aggregator`.
- iOS — `FleetAggregatorClient` / `FleetAggregatorConfig` (LFGCore);
  `LiveActivityManager` resolves the aggregator from any host and routes token,
  channel, started, ended through it with host fallback.

## Decision Log

- **The host-side mode is called "slice mode"** (renamed 2026-09-20 at Eugene's request). A host in this
  mode publishes only its own slice and aggregates nothing; "aggregator" names the Worker alone.

- **The Worker decides AND sends.** The probe proved Workers reach APNs over HTTP/2,
  so there is no need for "Worker decides, a host sends".
- **Self-contained reducer in the Worker**, not an import of `watcher.ts` (which pulls
  in node:http2/fs). Payload equality with the server's builders is pinned by test.
- **One shared bearer** for hosts and phone, handed to the phone by a host it is
  already authenticated to (Cloudflare Access), cached in UserDefaults. No secret in
  the binary; rotation is a `.env` + `wrangler secret put` change.
- **Channel id is Worker config** (`CHANNEL_PRODUCTION`), the one the Pro created on
  2026-09-20. Channels are permanent; nothing recreates it.
- **Token per device id** fixes "one start → three cards" (three rotated tokens of one
  phone all answering 200).
- **Slice TTL 90 s / heartbeat 30 s.** A vanished host's rows leave the card after
  three missed beats; a DO alarm re-evaluates so the card can end with no request.
- **Legacy reducer kept** for deployments without the two env vars.

## Verification Evidence

| SC | Command / action | Observed |
|---|---|---|
| SC1 | `curl -H "authorization: Bearer …" …/v1/probe` (2026-09-20 21:0x HKT) | `{"ok":false,"status":400,"reason":"BadDeviceToken"}`; unauthenticated → 401 |
| SC2, SC3 | `bun test workers/fleet-aggregator` | 17 pass |
| SC4 | `bun test src/push/fleet-slice.test.ts` | 9 pass. The tick-level test first FAILED and exposed a real bug: `runPushTick` returned early when a host had no alert devices, so it would never have published. Fixed. |
| SC5 | `swift test --filter FleetAggregatorClient` | 6 pass |
| SC6 | `bun test src/push workers/fleet-aggregator` → 152 pass; `bunx tsc --noEmit` clean; LFGCore 567 tests, 0 failures | |
| SC7 (Air half) | Air restarted 21:07 HKT, log (as it read at the time): `fleet Live Activity: aggregator mode → …workers.dev`; `GET /v1/state` | Air slice present with 3 working rows; Worker decided `start`, then `no-tokens` — it has no push-to-start token yet |
| SC7 (Pro half) | not done | **The Pro is unreachable on every route** (Cloudflare ssh "websocket: bad handshake", LAN times out). Its old process, when it wakes, still runs the legacy reducer and WILL broadcast `end` against the app's card until it is restarted into slice mode. |
| TestFlight | archived on the Air from a worktree at `c703a27` inside the GUI tmux server; `verify_testflight_build build_number:202609202115` | uploaded 21:22 HKT; DoD PASS 21:25 (VALID, train 1.3.0 highest, IN_BETA_TESTING). Also the app-target compile check for the iOS change. Logs in `.claude/feature/evidence/testflight-20260920-aggregator/`. |
| SC8 | not run | needs the phone to install 202609202115 and launch once (its token then reaches the Worker), and the Pro restarted into slice mode |

## Bugs

- Fixed: slice-mode early return with zero alert devices (see SC4).
