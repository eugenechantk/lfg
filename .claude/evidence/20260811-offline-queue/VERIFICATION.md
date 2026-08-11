# Verification — offline-queued message auto-send + actions menu

**Date:** 2026-08-11 · **Device:** iPhone 17 Pro sim `3AC870E7-10CF-46A8-97C8-0CC611E3213C`
**Host under test:** throwaway stub (`stub-host.ts`) on `127.0.0.1:8799`, per memory
`lfg-stub-host-offline-repro`. `/__received` is the in-memory record of everything POSTed to
`/send` — it, not the request log, is the authority.

---

## Part 1 — Baseline: the reported symptom does NOT reproduce on the happy path

Run against the **pre-fix** build.

| Round | Scenario | Result |
| --- | --- | --- |
| 1 | App foreground throughout. Host down → queue `PROBE-1` → navigate back to the list → host up at 18:12:48. | Delivered **18:13:24 (~36s)**, session never opened. |
| 2 | Queue `PROBE-2` → background app 90s → relaunch while host still down → host up 18:20:52, stay on list. | Delivered **18:21:05 (~13s)**. |

Screens: `03`–`08` (round 1), `09`–`11` (round 2).

So `setHostState`'s `!wasLive → isLive` edge → `replayPendingOutbox(forHost:)` works. The
"recovery never drains" theory is **disproved** — do not re-chase it.

## Part 2 — The real defect: `failed` is a black hole (A/B/A proof)

`LFGStore.pendingOutbox()` excludes `state='failed'` and was the **only** reader of the outbox,
so a row that burned on one bad attempt was invisible to every automatic path *and* was never
restored into `pendingSends` on relaunch — the message vanished from the UI entirely.

The test seeds a `failed` row directly into the app's SQLite, relaunches with the host down,
then brings the host up.

| Build | Seeded row | Outcome |
| --- | --- | --- |
| **A — fixed** | `BURNED-ROW-0001` | Re-armed `failed → pending` at launch; **delivered 18:37:25**, ~30s after the host returned. No user interaction, session never opened. |
| **B — backed out** (only the two `retryableOutbox()` call sites reverted to `pendingOutbox()`) | `BURNED-ROW-0002` | **Never delivered across 150s of polling.** Outbox state still `failed`, untouched. The single delivery seen in that window was a leftover background-`URLSession` POST of `BURNED-ROW-0001` from the previous run, not the seeded row. |
| **A′ — fix restored** | the *same* stranded `BURNED-ROW-0002` | Picked up and **delivered within 40s of launch**. |

The fix is load-bearing (satisfies memory `disconfirm-before-declaring-root-cause`).

## Part 3 — The actions menu

Screens `13`–`15`, on the fixed build with the host down.

- `13-v-queued.png` — the offline `Queued` capsule now carries the `ellipsis.circle`
  affordance, matching a server-queued row.
- `14-v-menu.png` — tapping it opens **Queued message** → *Try sending now* / *Edit* /
  *Remove*. Copy branches on `queuedOffline`: an offline message has no running turn to
  interrupt, so it reads "Try sending now" rather than "Send now (interrupt)".
- `15-v-after-trysend.png` — *Try sending now* against a still-down host moves the row to
  in-flight and, critically, does **not** paint the red "Not sent" terminal state. It stayed
  recoverable and `PROBE-3` auto-delivered at 18:34:10 once the host returned.

## Unit coverage

`LFGCoreTests.testRetryableOutboxIncludesFailedButNotDelivered` pins the query semantics
(`failed` in, `delivered` out, `pendingOutbox` unchanged). Full suite: **250 XCTest + 43
swift-testing, 0 failures**.

## Caveat — what the sim could not exercise

`BackgroundSender` uses a background `URLSession`, which *waits for connectivity* rather than
throwing when loopback has nothing listening. So on the simulator a replay against a down stub
is held by the system instead of failing, and `settleSendFailure`'s "host is still down → stay
queued, don't burn to `failed`" branch is not hit by these runs. It matters on a real device,
where a Tailscale peer that black-holes packets looks like a live network and the request
times out and throws — that is how a row reached `failed` in the field in the first place. That
branch is verified by reading, by the A/B/A result above (which proves what happens *after* a
row reaches `failed`), and by the store-level test — **not** by a live throw.
