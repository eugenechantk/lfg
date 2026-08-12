# RTT-adaptive connection timeouts

**Tier:** product (shipping TestFlight client)
**Motivation:** `.claude/diagnosis-cellular-vs-wifi-20260811.md` — on cellular the
phone reaches the host over a **DERP relay** (~140ms+ RTT, TCP-tunnelled with
head-of-line blocking) instead of the direct LAN path it gets on Wi-Fi. Every
connection timeout in the client is sized against a ~5ms LAN, so on the relay path
they fire on a link that is slow but perfectly alive.

## The three LAN-shaped constants

| Constant | Value | What firing early costs on a relay |
| --- | --- | --- |
| `HostProbePolicy.pollTimeout` | 4s | The reconcile counts a live host as failed, feeding the offline clock |
| `HostLinkPolicy.staleTimeout` | 20s | A slow-but-alive SSE stream is dropped and re-dialled over the relay |
| `LFGClient.keepalivePing(timeout:)` | 5s | **The feedback trap:** the ping is the only RTT source, so it starves the estimator exactly when the path is slow |

## Design

RTT is already measured (`keepalivePing` returns it; `HostLink.lastRTT` stores the
last sample) and the code already knows what it means — `LFGClient:619` says *"a
direct Tailscale path is single-digit ms on LAN and tens of ms on a punched
cellular path, while a relayed one lands in the hundreds."* Nothing consumes it.

`PathQuality` (new, in `LFGCore`, pure) turns that sample stream into a timeout
multiplier:

- Keeps the last **5** RTT samples and takes their **median** — with a 10s
  keepalive that is a ~50s window, responsive without letting one stalled ping
  triple every timeout.
- `scale(max:) = clamp(medianRTT / 50ms, 1.0, max)`. **Floored at 1.0**, so a
  timeout can only ever get *longer* than today's value, never shorter. This is
  what makes the change safe: the Wi-Fi/LAN case is bit-for-bit unchanged.
- No samples yet → scale 1.0. Cold start behaves exactly as today.

Each constant gets its own cap, because the cost of waiting too long differs:

| Constant | Cap | Range | Why this cap |
| --- | --- | --- | --- |
| `pollTimeout` | 3× | 4–12s | Poll interval is 60s and `LFGClient`'s user-initiated timeout is 15s; 12s fits under both |
| `staleTimeout` | 2× | 20–40s | 40s ≈ four missed 10s heartbeats. Detection stays bounded — 60s of dead air is worse than a redial |
| keepalive ping | 2× | 5–10s | Capped at `keepaliveInterval` so successive pings never overlap |

`quietRedialAfter` (12s) is **deliberately left alone.** Scaling it up is the one
change where the risk points the other way: a redial is cursor-resumable and
therefore cheap, while sitting on a dead socket shows the user stale data. Being
eager is the correct bias there.

## Success criteria

- **SC1** No samples → every derived timeout equals today's constant exactly.
- **SC2** LAN RTT (≤50ms) → every derived timeout equals today's constant exactly.
- **SC3** Relay RTT (150ms) → `pollTimeout` 12s, `staleTimeout` 40s, ping 10s.
- **SC4** One outlier sample among four good ones does not move the estimate
  (median, not mean).
- **SC5** The poll timeout is **per host** — a relayed host must not lengthen a
  LAN host's probe on the same tick.
- **SC6** A grade change (`local`→`relayed`) is logged to `ConnectionLog` once per
  transition, not once per sample.
- **SC7** `swift test` green; app builds; the live connection log on device shows
  the grade and the scaled timeouts in use.

## Verification — 2026-08-11

`swift test`: **249 XCTest + 43 swift-testing, 0 failures.** 13 new tests in
`PathQualityTests`.

Live, against the **real transport**, not a mock: a latency-injecting Bun reverse
proxy (`.claude/evidence/20260811-rtt-adaptive-timeouts/slowproxy.ts`) in front of
the real `lfg serve`, making a 1ms loopback host behave like a ~310ms relay. App
built and run on the session simulator, host config seeded via the plist +
`killall cfprefsd` recipe, launched through the `lfg://` scheme so the reinstall
would not wipe the seed. Full log:
`.claude/evidence/20260811-rtt-adaptive-timeouts/connection-log.txt`.

```
17:57:16 STR dial since=112232 grade=unknown (no samples) stale=20s   ← SC1 cold start: LAN constant
17:57:26 KAL path unknown -> relayed (grade=relayed rtt=313ms); poll=12s stale=40s   ← SC3
17:58:09 STR dial since=112491 grade=relayed rtt=308ms stale=40s      ← SC3 on an actual dial
17:59:22 KAL path relayed -> direct (grade=direct rtt=8ms); poll=4s stale=20s        ← SC2
```

- **SC1** ✅ first dial, no samples → `stale=20s`, the untouched constant.
- **SC2** ✅ dropping the injected latency to 1ms swung the median back and
  restored `poll=4s stale=20s` exactly. Not a one-way latch.
- **SC3** ✅ 310ms → `poll=12s stale=40s`, and the redial carried `stale=40s`.
- **SC4** ✅ unit (`medianRejectsOutlier`): one 8s ping among four 5ms ones does
  not move the estimate; the mean would have been 1.6s.
- **SC5** ⚠️ **verified by construction, not by test.** `fetchSessionsStreaming`
  now takes `(Host) -> TimeInterval` and evaluates it per host into `pairs`, so
  the task group cannot share one number. It lives in the app target, so there is
  no `swift test` covering it — the diff is the evidence.
- **SC6** ✅ 3 transitions logged across ~40 samples and ~10 minutes — once per
  change, not once per sample.
- **SC7** ✅ build clean; log lines above are from the running app.

## Out of scope

Getting off the relay (Surfshark Bypasser, UDP 41641 port-forward) — that is the
actual fix and it lives on the router and VPN, not in this repo. This work only
stops the client from mistaking a slow path for a broken one.
