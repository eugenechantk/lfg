# Diagnosis — iOS client drops on cellular, never on Wi-Fi (2026-08-06)

**Reported:** on the same Wi-Fi as the host, the client never drops — including
across leaving and re-entering the app. On 5G it drops often, reconnects for a
while, then drops again, and re-entering the app is the worst trigger.

**Status:** code-level analysis only. No cellular telemetry was captured (the
phone was on Wi-Fi throughout — `direct 192.168.0.226:41641`). Three defects
below are real from reading the code and are all **structurally inert on LAN**,
which is exactly the asymmetry reported. Which one dominates is unconfirmed.

Not a repeat of [[lfg-pro-host-sleep-disconnects]]: `resumeNow`,
`quietRedialAfter`, the 10s keepalive and the 30s grace window are all present in
HEAD, and the server-side reconnect rate is quiet (4 `[events] connect` in the
42 min since the 08:47:59 restart, all on Wi-Fi).

---

## Why Wi-Fi is structurally different, not just "better"

On Wi-Fi at home the phone reaches the Pro over a Tailscale **direct LAN** path.
No NAT punch, no idle mapping to expire, no relay, and — decisive for what
follows — **`NWPathMonitor` never reports an unsatisfied path**. On cellular the
path is a NAT-punched public endpoint (or DERP), the carrier NAT mapping expires
on idle, and the path status genuinely flaps on 5G↔LTE handover and VPN
re-attach.

Every defect below is a handler for a condition that only occurs off-LAN. That
is why the same binary is flawless at home.

---

## Defect A — `networkLost` paints the banner instantly, with zero debounce

`SessionStore.networkPathChanged` (`ios/LFG/SessionStore.swift:1012`) →
`markNoNetwork` → `HostSignal.networkLost` → `HostState.noNetwork`, whose
`showsOfflineBanner` is `true` **immediately**.

Every *other* failure route is debounced 30s (`HostLinkPolicy.bannerAfter`, via
`degraded` → `settle` → `offline`). The path-monitor route bypasses that entirely:
one transient `path.status != .satisfied` = instant "disconnected".

Worse than cosmetic: `isReachable` (`SessionStore.swift:337-339`) is also derived
from `showsOfflineBanner`, so a momentary path blip **blocks send routing** too.

On cellular with a VPN interface present, transient unsatisfied paths are
routine. On LAN Wi-Fi they essentially never happen. This is the single best
explanation for *"drops often, reconnects for a bit, drops again."*

**Fix:** treat `networkLost` like any other failure — start the grace clock
(`degraded`) rather than jumping to a bannering state. Keep `.noNetwork` as the
*reason* carried into the eventual `offline`, so the user still gets the right
remedy text, but only after it has persisted.

## Defect B — a cellular path change deliberately does *not* redial the stream

On `networkRestored` the store calls `link.retryNow()` (`SessionStore.swift:1022`),
which early-returns for `.catchingUp`/`.live`:

> `HostLink.retryNow` — *"Bytes are flowing. Do not churn a healthy stream just
> because the system path changed."*

That reasoning holds on LAN and is wrong on cellular. After an interface change
the local endpoint has moved, so a socket that still *reads* `.live` is already
dead — it just hasn't noticed. The link then burns the 18s URLSession idle
timeout / 20s stale watchdog before reconnecting.

`resumeNow()` is the function that already handles precisely this case (redials a
link quiet for > `quietRedialAfter` = 12s), and it is wired **only** to
foregrounding — not to path restoration.

Net effect: ~20s of dead air per cellular path change, and path changes are
frequent while out and about. Matches the "reconnects for a bit before it drops
again" cadence.

**Fix:** call `resumeNow()` on `networkRestored`, not `retryNow()`. The
freshness check inside it already avoids churning a genuinely-live stream.

## Defect C — foregrounding never re-evaluates the network path

`enterForeground()` (`SessionStore.swift:1169`) does `start()` + clear
`failuresByHost` + `resumeNow()` per link. It does **not** re-check
`networkPathSatisfied` or clear a latched `.noNetwork`.

If the path went unsatisfied while the app was backgrounded — the normal case on
cellular, where iOS tears the path down for a suspended process — the host state
is latched `.noNetwork` and the banner is up from the first frame after
foregrounding until bytes actually arrive. On Wi-Fi the path stayed satisfied the
whole time, so nothing latches and re-entry is clean.

This is the "especially when I leave the app and come back" half of the report.

**Fix:** on foreground, drop a latched `.noNetwork` to `.connecting` and let the
links' bytes promote it, rather than showing "offline" for a condition measured
before the suspension.

## Contributing — `URLSession.shared` can't wait for connectivity

`LFGClient` uses `URLSession.shared` (`LFGClient.swift:38`), on which
`waitsForConnectivity` is not settable. A dial launched inside a brief path gap
fails immediately instead of waiting it out — which then feeds the failure
counters. A private `URLSessionConfiguration` with `waitsForConnectivity = true`
for the REST/probe path would absorb sub-second gaps that currently cost a
failure each.

---

## The meta-problem: this is the third blind investigation of this symptom

`.claude/diagnosis-macbook-air-flakey-connection.md`,
`.claude/diagnosis-connection-instability-20260804.md`,
`.claude/diagnosis-pro-disconnect-banner-20260804.md` — and one wrong-and-retracted
Surfshark theory in memory. Each round reasons from a verbally-reported symptom
plus server logs, because **the client emits no connection timeline**. There is no
diagnostics surface in `SettingsView`.

Highest-leverage change independent of A/B/C: a rolling in-app connection log —
every `HostSignal`, `HostState` transition, `NWPath` status change (with
`isExpensive`/`isConstrained`/interface type), link state change, and RTT sample,
timestamped, viewable and shareable from Settings. Then a single 5G repro answers
in one screenshot what three sessions of code-reading could not.

---

## Recommended order

1. Connection timeline in Settings (makes everything after it verifiable).
2. Defects A + B + C — small, independently defensible, no behavioural risk on LAN.
3. Ship one TestFlight build with all four; reproduce on 5G; read the timeline.

Step 3 is the only step that can close this out. Compare the **build number**,
never `MARKETING_VERSION` — see [[lfg-pro-host-sleep-disconnects]].
