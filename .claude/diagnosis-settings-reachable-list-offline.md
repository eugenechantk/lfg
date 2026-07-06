# Diagnosis — Settings says "Reachable" but the list still says "Offline"

## Symptom
Intermittently, the Settings host probe shows **Reachable** (green) while the
session list header shows **Offline** (orange) at the same time.

## The two states are different things

| Surface | Source | Nature |
| --- | --- | --- |
| Settings "Reachable" | `LFGClient(string: draft).ping()` on a button tap (`SettingsView.swift:75`) | **Live, on-demand** request against `api/sessions`, right now |
| List "Offline" | `store.isConnected` = `store.reachability == .ok` (`SessionListView.swift:205,284`) | **Latched** result of the *last completed poll* |

Both hit the **same** endpoint (`GET api/sessions`, `ping()` at `LFGClient.swift:110`
vs `sessions()` at `:124`), the **same** `URLSession.shared`, and — when the
Settings field equals the saved host — the **same** URL. So the divergence is not
URL, endpoint, or auth. It's **timing/state**: the list reflects a stale snapshot,
the probe reflects live truth.

## Root cause: a single failed poll latches "Offline" with zero tolerance

`SessionStore.refresh()` (`:159–202`) runs every 3s. On *any* thrown error it
immediately overwrites `reachability` with a non-`.ok` value:

```
} catch let LFGError.notReachable(u) { reachability = .hostUnreachable(u) }
} catch let LFGError.http(status, _) { reachability = .badResponse("HTTP \(status)") }
} catch { reachability = .badResponse(...) }
```

One transient failure flips the whole UI to "Offline" until the *next* successful
poll. Transients are expected here, not rare:

- **The Bun server is single-event-loop and documented to stall HTTP 20s+** when a
  PTY/terminal websocket saturates it (root `.claude/CLAUDE.md`). The poll `GET`
  timeout is **15s** (`LFGClient.swift:65`) — shorter than a known stall — so the
  poll throws `notReachable` and latches Offline. Seconds later the stall clears
  and a fresh Settings ping succeeds → "Reachable".
- Tailnet reroute, a GC pause, or an app-just-foregrounded blip does the same.

Because the list value is latched (not "currently retrying"), it *stays* Offline
for the whole gap until a clean poll lands — long enough for the user to open
Settings, tap Test, and see the contradiction.

`reachability == nil` (cold start / after a host change, since `.task(id:)` only
calls `start()`) is also rendered as "Offline" until the first poll returns — a
second, smaller contributor.

## Why this is "sometimes"
It requires a poll to fail while the host is genuinely up — a transient. The
probe, being fresh, samples a different (good) instant. Same host, two different
moments in time, two different answers.

## Recommended fix (debounce the offline transition)
Don't let one blip flip the UI. In `SessionStore`:

1. Track `consecutiveFailures`. On a successful poll reset it to 0 and set `.ok`.
2. On a failed poll, increment; only surface the non-`.ok` `reachability` once it
   crosses a small threshold (e.g. **2–3 failures ≈ 6–9s**). Below threshold, keep
   the last-good state (optionally expose a subtle "Reconnecting…" rather than a
   hard "Offline").
3. Consider one silent retry inside `refresh()` and/or raising the poll `GET`
   timeout above the documented ~20s server stall.

This keeps a real outage visible within ~10s while making the transient
Reachable-vs-Offline contradiction disappear.

## Files
- `ios/LFG/SessionStore.swift` — `refresh()` (`:159`), `isConnected` (`:129`)
- `ios/LFG/SessionListView.swift` — `statusSubtitle` (`:204`), `StatusBadge` (`:276`)
- `ios/LFG/SettingsView.swift` — probe (`:75`), `HostProbeRow` (`:177`)
- `ios/LFGCore/Sources/LFGCore/LFGClient.swift` — `ping()` (`:108`), `sessions()` (`:123`), 15s timeout (`:65`)
