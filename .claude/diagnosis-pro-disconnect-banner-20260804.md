# Why the iOS client "loses" the Pro — 2026-08-04

**Complaint:** the client often shows the disconnection banner in the session view
for the Pro host, though the Pro is never actually offline.

**Verdict:** the Pro is fine. The banner is the *shipped client* being unable to
recover quickly from a cold network path, and then latching that state for
minutes. **The fix is already written, unit-tested, and sitting uncommitted in
this working tree — it was never landed or shipped.**

---

## The banner you're seeing

`OfflineComposerNotice` (`ios/LFG/SessionDetailView.swift:531`) — *"<host> is
unreachable — messages will send when it's back."* It renders whenever
`reachabilityByHost[host] != .ok`.

## Measured on the Pro today (12:37–12:45 HKT)

| Layer | Probe | Result |
| ----- | ----- | ------ |
| Server event loop | `/api/ping` ×1s for 3 min | worst **11ms**, 0 stalls |
| Server REST | `/api/sessions` ×8 loopback | **0.4–207ms** (not the 25s of Aug 1) |
| Server SSE | 2 long-lived control clients (loopback + tailnet IP) | held **6+ min**, zero silent gaps, zero drops |
| Host load | `uptime` | load **6.05** — healthy |
| Disk | data volume | 83% (150Gi free) |
| Phone path | `tailscale ping ×10` | `direct 14.0.173.65:28170`, **44–126ms**, no loss |
| Reconnect rate | `[events] connect` per server run | **36 over 16.3h** (~2/hr) — normal, not a flap storm |

The server is not the problem, and the stream is not flapping every minute.

## Correction to the previous diagnosis: Surfshark is **not** the cause

The July memory named Surfshark owning the Pro's default route as the
highest-leverage fix. That is measurably wrong today:

- Public IP via the default route (Surfshark exit): **45.144.227.62**
- Tailscale's own discovered endpoints: **203.145.95.116**:56351/41641/45057 —
  the *real* HK ISP address, plus `192.168.0.192` (LAN)

Tailscale's STUN-discovered endpoint is the physical ISP address, **not** the
Surfshark exit. Tailscale already bypasses the VPN. Surfshark rotation does not
move the Pro's punched endpoint. **Don't spend time on Bypasser.**

## The actual mechanism

The phone reaches the Pro at `100.120.101.14:8766` over a **direct, NAT-punched
UDP path from cellular** (its endpoint is a public IP, not the Pro's LAN — so it
is not on the same Wi-Fi). That path goes cold whenever the phone suspends the
app, changes cell, or the carrier NAT binding lapses. Re-punching takes seconds.

That much is normal and unavoidable. What turns a few seconds of cold path into a
minutes-long banner is what the **shipped build (TestFlight 1.2.0 = HEAD)** does
on foreground:

```swift
// HEAD — ios/LFG/SessionStore.swift:1044
func enterForeground() {
    let alreadyRunning = pollTask != nil
    start()
    if alreadyRunning { Task { await refresh() } }
}
```

Three compounding gaps, all in the shipped build:

1. **Nothing kicks a backed-off link.** `resumeNow()` does not exist in HEAD at
   all (0 occurrences). A link that backed off while the path was cold can idle
   up to **30s** (`reconnectDelay` caps at 30) after you reopen the app.
2. **Nothing clears the failure counts.** `failuresByHost` survives foreground.
   Each REST probe has a **4s** timeout; **3** consecutive failures paint the
   banner, and at **4** the host goes *cold*.
3. **A cold host is re-probed every 10 minutes.** `coldProbeEveryNTicks = 10` in
   HEAD was written for the old *3s* poll ("retried every ~30s") and never
   re-derived when the loop became **60s**. 10 ticks × 60s = **10 minutes**
   before the reconcile even tries again.

So: background the app for >25s → links are torn down → reopen on a cold
cellular path → the first dial(s) fail → 3 failed 4s probes paint the banner →
the host latches cold → the REST path won't retry for 10 minutes. The Pro was up
the entire time.

## The fix already exists — uncommitted

`.claude/feature/instant-reconnect.md` (Aug 1) diagnosed the same root and the
changes are in the working tree, unshipped:

| Change | Status |
| ------ | ------ |
| S1 — server sends `: hb <head>` immediately on connect | **already deployed** (verified: first body byte in 0.001s vs 10.004s) |
| C1 — `enterForeground` kicks every link + clears `failuresByHost` | in tree, uncommitted |
| C2 — foreground reconnect burst (0/0.5/1/2/4/8s) instead of the 60s tick | in tree, uncommitted |
| C3 — recompute aggregate reachability per host result | in tree, uncommitted |
| C4 — tri-state "Connecting…" instead of orange "Offline" | in tree, uncommitted |
| C5 — cold cadence re-derived for the 60s poll (10 → 5 ticks) | in tree, uncommitted |
| `quietRedialAfter = 12s` — redial a link that *reads* healthy but is frozen | in tree, uncommitted |

Verified on Aug 1: `swift test` **165 pass / 0 fail**, `bun test` **150 pass / 0
fail**, iOS build succeeds. What was *not* verified was end-to-end timing
(SC2/SC4/SC5) — that machine was at load 748 with 23 booted simulators and 99%
disk, so no timing was trustworthy. That is why it never landed.

## Recommendation

1. **Land and ship it.** The shipped build has none of C1–C5; the work is done
   and unit-verified. The remaining gap is live timing verification, and the
   machine is healthy now (load 6, disk 83%, sub-ms API) — the conditions that
   blocked Aug 1 are gone.
2. **Re-verify SC2/SC4/SC5 in the simulator** before shipping, per the feature
   doc's own criteria.
3. **Skip the Surfshark work.** Measured wrong today.

## Residual, lower priority

- The server is getting **SIGTERM**'d and respawned by `serve-forever`
  (3× today: after 58601s, 400s, 2947s). Each is a ~1s blip and *not* the banner
  cause, but something is killing it — likely concurrent agent sessions
  restarting the server. Worth finding.
- `serve-forever` warns it is running **bun 1.2.15 while `.bun-version` pins
  1.3.14**.
- `/private/tmp/lfg-serve.log` has **no timestamps** and is 13MB, dominated by a
  repeated `[sessions] no confident session for cwd .../reelly` line. Timestamps
  would have made this diagnosis much faster.
