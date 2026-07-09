# Diagnosis — Flakey connection to the MacBook Air host

**Date:** 2026-07-09
**Symptom:** iPhone (on the tailnet) has a very flakey connection to the lfg server on
`eugenes-macbook-air`, reached at the Tailscale IP `100.75.162.40:8766`.

---

## Verdict

**One cause: a fan-out barrier in the iOS client.** It stalls every foreground and every
notification tap by 15s whenever a configured host is offline. Full write-up and fix:
`.claude/feature/multihost-fanout-resilience.md`.

An earlier revision of this document blamed a Surfshark VPN route conflict. **That was wrong.**
The correction is kept below, in full, because the way it went wrong is instructive.

---

## The actual cause

- An offline Tailscale peer is a **black hole** — packets dropped, no RST, no connection refused.
  Measured against `macbook-pro-2` (`100.120.101.14:8766`, asleep):
  `http=000 connect=0.000000 total=15.004652`. It hangs for the entire timeout.
- `SessionStore.fetchSessionsAllHosts()` fanned out in a `withTaskGroup` and then awaited **all**
  hosts (`for await r in group { out.append(r) }`) before applying anything — a barrier.
- `ensureStream()`, which re-establishes the per-host SSE streams, was the **last line** of
  `refresh()`, so SSE reconnect was gated behind that barrier.
- `RootView` calls `await store.refresh()` on `scenePhase == .active`, and `resolveDeepLink`
  awaits `refresh()` before resolving a notification tap.

**Why it appeared only now.** The bug requires a *configured but offline* host. With a single
host (the Pro) there was never a dead entry, so the barrier never had anything to wait on. Adding
the Air as a second host left the Pro — which sleeps — as a permanent black hole in the client's
host list. The Air is merely the host being used; the sleeping **Pro** is what poisons the fan-out.
The same failure would appear on the Pro with the Air asleep.

Fixed and verified against the real offline peer. See the feature doc.

---

## Correction: Surfshark is NOT a cause

Surfshark (WireGuard, `utun9`) does own the default route:

```
$ netstat -rn -f inet | grep default
default   link#30   UCSg    utun9      <-- Surfshark, wins
default   192.168.0.1  UGScIg  en0
default   link#29   UCSIg   utun3      <-- Tailscale
```

That looks damning, and I wrote it up as a split-brain endpoint conflict. It is not, because
**Tailscale's network extension binds its outbound sockets to the physical interface** and so
bypasses the default route entirely.

Three checks settle it:

```
$ curl -s https://api.ipify.org                    # ordinary process, follows default route
89.117.42.116                                      # Surfshark exit

$ curl -s --interface en0 https://api.ipify.org    # forced out the physical NIC
124.217.189.159                                    # real WAN

$ tailscale status --json | .Self.Addrs
['124.217.189.159:10951', '124.217.189.159:41641', '10.14.0.2:41641', '192.168.0.13:41641']
                ^^^^^^^^^^^^^^^ Tailscale advertises the REAL WAN IP, not the Surfshark exit
```

And the data path is direct, never relayed:

```
$ tailscale ping iphone-13-pro
pong from iphone-13-pro (100.94.32.86) via 14.0.225.51:24190 in 301ms
                                       ^^^^^^^^^^^^^^^^^^^^ direct peer endpoint, not DERP(hkg)
```

The packets Tailscale actually moves come from a root system extension, not from `Tailscale.app`
and not from the CLI:

```
82221 root  /Library/SystemExtensions/…/io.tailscale.ipn.macsys.network-extension
```

**Where the false positive came from.** `tailscale netcheck` and `curl` are ordinary CLI
processes. They follow the default route, so they egress via Surfshark and report its exit IP
(`89.117.42.116`) and an inflated "nearest DERP" of 66.3ms. I took the CLI's view of the network
as the extension's view. The `10.14.0.2:41641` entry in `Self.Addrs` is just local-address
enumeration (same as the `192.168.0.13` LAN entry), not evidence of tunnelled egress.

**Conclusion: run Surfshark and Tailscale together. Nothing to configure.** Note for the future:
on this machine `tailscale netcheck` is *not* a valid measure of Tailscale's health — it reports
the Surfshark path, which the extension never uses.

---

## Sleep: latent, currently handled, not a cause

```
$ pmset -g | grep sleep
 sleep  1  (sleep prevented by coreaudiod, caffeinate, caffeinate, caffeinate, caffeinate)
```

System sleep is set to **1 minute**, and the thing preventing it is `caffeinate -i -s -w 82799`
where PID 82799 is **MacCommandCenter.app** — intentional, per Eugene. The Air has not slept since
`2026-07-08 14:48`, so sleep did not cause the reported symptom.

Two caveats, informational:

- `caffeinate -i -s` does not prevent **clamshell sleep on battery** (`pmset -g log` shows
  `Entering Sleep state due to 'Clamshell Sleep'`).
- If MacCommandCenter quits, `sleep 1` means the Air sleeps 60s after the last input.

Insurance that doesn't depend on another app: `sudo pmset -c sleep 0`.

---

## Ruled out, with evidence

- **lfg server / Bun event-loop saturation** — 20/20 requests returned 200; ~0.4ms on loopback,
  ~1.8ms on `100.75.162.40:8766`. No stalls.
- **Deploy gap (running code lagging source)** — `src/commands/serve.ts:192` defaults `HOST` to
  `127.0.0.1`, but `.env` sets `LFG_HOST=0.0.0.0` and **Bun auto-loads `.env`**, so the wildcard
  bind is intentional and survives restart. `ps eww` does not show it because the env is injected
  at runtime.
- **Surfshark route conflict** — see the correction above.
- **Host sleep** — machine awake for 25h+.

## Unrelated, real, not worth chasing

The path to the iPhone is genuinely slow and lossy: 3 of 4 `tailscale ping`s time out; successes
land at 214ms / 301ms / 1.885s. This is the phone end — cellular, plus iOS suspending the Tailscale
extension while the screen is off. It resolves when the app is actually in use.

## Loose end (cosmetic)

`scripts/serve-forever.sh:17-20` says lfg listens on loopback by default. `.env` overrides it to
`0.0.0.0`. Anyone "fixing" the bind to match the comment would silently break the raw-IP path the
iOS client uses. Either drop `LFG_HOST` from `.env` and rely on `tailscale serve`, or fix the comment.
