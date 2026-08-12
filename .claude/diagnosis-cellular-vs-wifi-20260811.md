# Why the host connection is iffy on 5G but solid on Wi-Fi — 2026-08-11

Measured on `Eugenes-MacBook-Pro`, 2026-08-11 ~09:12 UTC / 17:12 HKT.

## Short answer

It is cellular vs Wi-Fi, but **not because cellular is a worse radio**. It's because
the two cases take completely different network *paths* to the host:

| | Path | Cost |
| --- | --- | --- |
| Home Wi-Fi | Phone `192.168.0.x` ↔ Mac `192.168.0.192`, **direct on the LAN** | ~1ms, no NAT, never breaks |
| 5G | **DERP relay in Hong Kong** (Tailscale's fallback) | ~140ms+ RTT, TCP-tunnelled, dies on every carrier IP change |

On Wi-Fi, Tailscale never has to traverse anything — both ends are on the same
subnet. On 5G it must NAT-punch a direct UDP path, that punch is currently
failing, and everything falls back to the relay.

## Evidence

```
$ tailscale status
100.94.32.86   iphone-13-pro   iOS   active; relay "hkg", tx 124695684 rx 2571668
                                     ^^^^^^^^^^^^^^  CurAddr = ""  → NO direct path
```

Every peer is on a relay. `CurAddr` is empty for all of them — including the Air,
which sits on the same LAN. The Mac has **no direct path to anything**.

```
$ tailscale netcheck
* UDP: true
* IPv4: yes, 45.144.227.29:51944        ← Surfshark exit
* MappingVariesByDestIP: false          ← friendly (cone) NAT — punching SHOULD work
* PortMapping:                          ← empty: router offers no UPnP/NAT-PMP/PCP
* Nearest DERP: Hong Kong (71.1ms)      ← 71ms to a relay in your own city
```

```
$ tailscale status --json | .Self.Addrs
["203.145.95.116:33540", "203.145.95.116:41641", "203.145.95.116:56560",
 "10.14.0.2:41641", "192.168.0.192:41641"]
```

```
$ route -n get default   → interface: utun4  (Surfshark WireGuard, mtu 1380)
$ curl ifconfig --interface en0  → 203.145.95.116   (real ISP)
$ curl ifconfig (default route)  → 45.144.227.29    (Surfshark)
```

## RETRACTED — the Surfshark theory below is WRONG (disproved same day)

Two non-destructive tests killed it:

```
$ tailscale status | grep air
100.75.162.40  eugenes-macbook-air  active; direct 192.168.0.75:41641   ← LAN punch works

$ ssh hostinger 'tailscale ping 100.120.101.14'
pong from eugenes-macbook-pro via 203.145.95.116:41641 in 64ms          ← WAN punch works
```

The Hostinger VPS is on the public internet with no LAN to the Pro, and it reaches
the Pro **directly on the real ISP address**, with Surfshark running the whole
time. Inbound WAN UDP to `203.145.95.116:41641` therefore arrives, the Mac's
replies validate, and the address asymmetry theorised below does not prevent a
punch. **Do not configure Surfshark Bypasser or a router port-forward on the
strength of this document** — both were aimed at a blocker that isn't there.

The retraction in memory `lfg-pro-host-sleep-disconnects` stands after all. What
was wrong was my reasoning from `netcheck`'s STUN address: a mismatch between the
discovered address and the advertised endpoints is *suggestive* of broken
punching, but it is not evidence of it, and I treated it as such without running
the check that would disconfirm it.

**Still open:** the `relay "hkg"` reading for the iPhone is real, but it was taken
at an unknown moment — the phone may have been idle, or on Wi-Fi. A later
measurement caught the phone on Wi-Fi and **direct** via `192.168.0.148:41641`.
The phone-on-5G path has **not** been measured. That is the one observation the
whole question turns on, and everything below it should be read as unconfirmed
until it exists.

## SUPERSEDED: the Surfshark theory

Tailscale **advertises** `203.145.95.116:41641` (real ISP) to peers, but the Mac's
default route is Surfshark, and `netcheck`'s own STUN probe comes back as
`45.144.227.29`. The phone is being told to punch to an address the Mac does not
reliably send from. A hole punch only validates when the packet the peer receives
arrives *from* the address it punched *to* — so the direct path never forms and
Tailscale falls back to DERP.

Supporting signals: UDP works, the NAT is endpoint-independent (`cone`), and yet
there is not one direct path on the whole tailnet — even to a machine on the same
Wi-Fi. That points at something local to the Mac, not at the carrier.

**This supersedes the 2026-08-04 retraction of the Surfshark theory.** That
measurement showed Tailscale's discovered endpoint as the real ISP IP, i.e.
bypassing the VPN. Today's `netcheck` shows the VPN IP. Something changed —
re-test rather than trusting either memory.

## Why a relay path *feels* iffy specifically

1. **DERP is TCP/HTTPS, not UDP.** One lost packet on the cell link head-of-line
   blocks the whole tunnel — the SSE stream and every REST call behind it stall
   together. On a direct UDP path, loss costs you one packet.
2. **~140ms round trip minimum**, before any cellular jitter. Every REST probe,
   every send, every heartbeat pays it.
3. **Carrier IP changes tear it down.** 5G↔LTE handover, tower change, or an idle
   NAT binding expiring invalidates the relay session; the client has to redial.
   On Wi-Fi none of this happens.
4. **iOS suspension.** On cellular the NAT mapping evaporates within ~30–60s of the
   app suspending, so returning to foreground means re-establishing the relay.
   On the LAN path there's nothing to re-establish.

## The client is already hardened for this — that's not the gap

`HostLinkPolicy` already carries a 10s keepalive whose stated purpose is keeping
the carrier-NAT binding warm; `HostState` already debounces `NWPathMonitor`'s
transient unsatisfied paths (the comment on `.noNetwork` calls out 5G↔LTE handover
by name); `resumeNow` already kicks a backoff on foreground and path change;
`LFGClient` uses `URLSession.shared` so connections pool. The app layer has been
fixed twice already. The remaining variable is the transport.

## Fixes, in order

### 1. Measure the phone on 5G — everything else waits on this

**Both fixes originally listed here are withdrawn** (see the retraction above): the
Mac is already punchable from the WAN, so neither Bypasser nor a port-forward
addresses anything.

The missing measurement: Wi-Fi **off** on the phone, lfg open and streaming, then
`tailscale status` on the Pro. Two outcomes, two different next steps:

- **`relay "hkg"`** → the Mac punches fine and the VPS proves it, so the blocker is
  the phone side: carrier CGNAT that is symmetric, or a carrier that drops
  outbound UDP to high ports. Little of that is configurable — §2 becomes the
  remedy rather than a consolation.
- **`direct <addr>:41641`** → the 5G path is healthy and "iffy" is not a path
  problem at all. Look instead at iOS suspending the app and the NAT binding
  lapsing on resume — a client-recovery question, and the same shape as the
  2026-08-04 banner bug.

Take the reading while the app is actively streaming. An idle iOS peer does not
hold a direct path open, and `tailscale ping` to a suspended phone times out
entirely — which is very likely what the original `relay "hkg"` line was.

### 2. Make the relay path tolerable (app-side, worth doing regardless)

- **`HostProbePolicy.pollTimeout` is 4s.** That is sized for a LAN. On a 140ms
  relay under loss it will time out routinely, each timeout costs a 4s hang on the
  reconcile tick, and the failures feed the offline clock. It only latches the
  banner if the SSE stream is *also* struggling — which on a relay is exactly when
  it happens. Make it adaptive (e.g. `max(4, 3 × median RTT)`).
- **`staleTimeout` 20s / `quietRedialAfter` 12s** are likewise tuned against a
  ~5ms LAN. On a jittery relay a missed heartbeat is normal, and redialing churns
  a slow-but-alive stream. Scale both off measured RTT.
- **Surface direct-vs-relay in the connection log.** `ConnectionLog` already
  records `NWPath` interfaces; RTT >100ms to a tailnet host is a reliable relay
  tell. Right now "iffy" is anecdotal — this makes it measurable.

## Not the cause (checked, don't re-chase)

- **Server flapping.** 5 `[events] connect` in the current run (started
  Aug 11 14:45 HKT) — scoped to one `[serve-forever] starting`, per the standing
  rule about grepping the whole log.
- **App-layer path handling.** See above; already debounced and already kicked.
