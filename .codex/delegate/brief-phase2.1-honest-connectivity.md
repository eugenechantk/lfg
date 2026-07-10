# Delegation Brief: phase2.1 — honest connectivity pill + coalesced catch-up

**Goal:** two link-layer hardening fixes found on day one of the Phase 2 device soak:
(A) the "Connected" pill must not lie when the phone is off-network, and (B) reconnect
catch-up must not strobe session statuses while replaying missed events.

**Repo:** git worktree of `lfg`. Work ONLY in `ios/` (`LFG/` app target + `LFGCore` where
noted). Swift 6 strict concurrency. Build: `cd ios && xcodegen generate` if you touch
project.yml (you should not need to). Do NOT touch `src/`, `SessionListView.swift`, or the
Closed-section/resumable code — other agents own those areas.

## Context (read first)

- `ios/LFG/HostLink.swift` — per-host link actor. `isHealthy` counts `.connecting` as
  healthy while `unhealthySince == nil`. Link objects are TORN DOWN on backgrounding
  (`SessionStore.stop()`) and rebuilt on foreground — all their health history dies with them.
- `ios/LFG/SessionStore.swift` — `linkStateChanged(_:)` maps link health → `reachabilityByHost`
  → aggregate `reachability`; `isConnected` drives the pill. `ingest(_:hostId:)` applies each
  `LiveEvent` immediately. Read the comment on `linkStateChanged` — the banner-recheck Task
  pattern there is load-bearing, keep it.
- `ios/LFGCore/Sources/LFGCore/HostEvents.swift` — `HostLinkPolicy` (bannerAfter = 30s, etc.).
- `ios/CLAUDE.md` — traps; especially "Live delivery is HostLink" and Swift 6 notes.

## Bug A — the pill lies when off-network

Two mechanisms, fix both:

1. **The 30s sustained-failure clock resets on every foreground.** It lives on the link
   object (`unhealthySince`); links are rebuilt per foreground, so a <30s glance always
   reads "Connected" even with zero connectivity. **Fix: move the clock to the store.**
   `SessionStore` keeps `unhealthySinceByHost: [String: Date]` (keyed by host id, i.e. url),
   surviving link teardown/rebuild (in-memory is enough — a cold launch starts honest anyway
   because `reachability` starts nil):
   - Healthy EVIDENCE = link state `.catchingUp` or `.live` (bytes actually received):
     clear the entry, set `.ok`.
   - `.connecting` is NOT evidence in either direction: leave both the entry and the
     current reachability value untouched (a fresh link dialing must not reset the clock
     OR flip an `.ok` host to unreachable).
   - Link unhealthy (`.backoff`, or `.connecting` with the link's own `unhealthySince` set):
     set the entry if absent (use the link's `unhealthySince` if earlier than now). Then the
     existing sustained/grace/recheck logic runs off the STORE's date, not the link's.
   - On foreground rebuild while an old entry says the host has been unhealthy ≥ bannerAfter:
     the pill shows Offline immediately (this is the regression the fix exists for).
2. **Definitive no-network should not wait 30s.** Add an `NWPathMonitor` (Network framework)
   owned by the store (start in `start()`, cancel in deinit/stop): when the path becomes
   unsatisfied → immediately set every configured host's reachability to
   `.hostUnreachable("No network connection")` and stamp `unhealthySinceByHost` for all
   hosts (so a quick path flap still counts toward sustained). When the path becomes
   satisfied → do NOT force `.ok` (that's evidence-based); just nudge every link to retry
   now (add a `retryNow()` to HostLink that cancels a pending backoff sleep and redials —
   keep it simple: cancel + restart the run task is acceptable if losing nothing).
   Path callbacks arrive off-main — hop to @MainActor with the parsed status only.

## Bug B — catch-up strobes statuses

During cursor replay (`link.state == .catchingUp`) every missed event applies live and the
UI animates each intermediate busy/unread flip.

**Fix: buffer-and-flush.** In `SessionStore.ingest`, when the event's host link is
`.catchingUp`, append the event to a per-host buffer instead of applying. Flush = apply all
buffered events IN ORDER synchronously in one MainActor turn (no awaits between applies) —
SwiftUI then renders once, showing only final states. Flush triggers (all of them):
- the link leaves `.catchingUp` for ANY state (`.live` via first heartbeat, `.backoff`,
  teardown/stop) — this is critical: the link's cursor has already advanced past buffered
  events, so dropping the buffer on failure would violate Phase 1's zero-loss gate;
- host removed from settings (flush before dropping state);
- buffer exceeds 2000 events → flush the whole buffer immediately (memory bound; a giant
  replay renders in a few chunks instead of one, still no per-event strobing).
Note `unknown-sid throttled refresh` behavior inside apply/ingest must still work after a
flush (do not re-order events).

## What NOT to change

- `HostLinkPolicy` values; the banner-recheck Task pattern; reconnect/backoff behavior
  (other than the added `retryNow`); anything in the events wire protocol or cursors.
- No new dependencies. Network.framework is system.

## Verification (run what you can; the delegator runs the live gates)

1. `cd ios/LFGCore && swift test` green (add pure tests only if you extract pure logic —
   fine to keep this app-target-only).
2. Build for simulator:
   `cd ios && flowdeck build --workspace LFG.xcodeproj --scheme LFG --simulator D69C6DC8-241A-4DAA-A148-8A969CA25A55`
   (if flowdeck is unavailable in your sandbox, say so).
3. Reason through and state in your report: the exact sequence of store reachability values
   for (a) cold launch offline, (b) foreground glance offline after healthy background,
   (c) 45s black-holed host with network up, (d) network flap of 3s.

## Definition of done
- [ ] Store-owned sustained-failure clock; foreground rebuild cannot reset it.
- [ ] NWPathMonitor: unsatisfied path → immediate honest Offline; satisfied → links redial.
- [ ] Catch-up events buffered; single synchronous flush on ANY exit from catchingUp;
      zero-loss preserved (no dropped buffer on failure paths).
- [ ] Build green; existing tests green; no changes outside the named files.

**Report back:** files changed, the four reachability sequences from step 3, build/test
output, anything you had to deviate on.
