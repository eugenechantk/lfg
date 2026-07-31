# Live Activity Redesign — one activity for the whole fleet

**Date:** 2026-07-13
**Goal:** Replace the current per-session Live Activity (N sessions → N lock-screen
activities) with a **single** Live Activity that summarizes all running + needs-input
sessions across every host.

---

## The problem with today's design

`LFGSessionAttributes` is keyed by `sid` — one activity per session. The server
watcher (`src/push/watcher.ts` → `reduceLiveActivityTransition`) starts a fresh
activity every time any session goes `busy`. Run 4 agents → 4 separate lock-screen
cards stacked on top of each other. Noisy, redundant, and the actionable signal
("someone needs input") is buried in the pile.

## Does one activity still keep the host connection alive? — Yes.

Important correction: **Live Activities don't hold a socket open to the hosts.**
The liveness comes entirely from the server-side watcher (`startPushWatcher`),
which polls sessions every 2s and pushes `start`/`update`/`end` frames through
APNs — by design "independent of any connected client SSE stream … notify when
the app is closed" (watcher.ts header comment). The activity is a *render surface*
updated by remote push. So the count of activities is irrelevant to liveness.
Going N→1 changes nothing about keeping state fresh in the background/locked —
it's arguably cleaner: **one** push-to-start token and **one** update token
instead of one per session.

---

## Design references (Mobbin)

Pulled real Live Activity / Dynamic Island patterns and picked the ones that map
to our "aggregate of several items" need:

| Pattern | App | Takeaway for us |
| --- | --- | --- |
| Dense multi-column status (route + progress + dual timers) | [Flighty](https://mobbin.com/screens/e885508e-8728-426b-a1a2-7a4be1e4086e) | Information density in a small budget; tabular numbers |
| Compact DI = icon + count badge ("E3", "7") | [Flighty](https://mobbin.com/screens/cfd5bf7f-efe2-4a72-a8ba-84302dc5c331), [Yazio](https://mobbin.com/screens/cc5f51c4-c7cd-4280-8498-e538bf35e7c0) | A single count + colored badge is the right compact affordance |
| Multi-row list, each row = item + status ("Saving Media 2/4") | [GoPro Quik](https://mobbin.com/screens/d9d1710a-5585-42da-ae77-c4811a8ed7b0) | The row layout for stacking sessions inside ONE card |
| Row = avatar + title/subtitle + trailing check | [Hevy](https://mobbin.com/screens/184c2861-65d0-4764-a3d3-6808a961264e) | Clean single-row anatomy |
| Controls inside the activity (play/pause) | [FocusFlight](https://mobbin.com/screens/54d63fe8-f924-436c-9071-c63038dbefb6) | Future: could add a "reply/open" deep-link per needs-input row |
| Colored-dot task list | [Monarch](https://mobbin.com/screens/5d6cdbf5-f788-4e7c-b180-89c2583da209), [Lovi](https://mobbin.com/screens/8b2958cc-1a52-4fad-b5d1-25f13fb4d273) | Dot color = state; the visual language we already use in-app |

Mockup: `.claude/feature/live-activity-redesign-mockup.png`

---

## The redesign

**One activity: "lfg sessions".** Header = fleet summary, body = the most relevant
sessions (needs-input first), overflow collapses to "+N more".

### Lock screen (≤ ~160pt budget → header + 3 rows + overflow)
- **Header:** `lfg` mark · `"4 agents · 2 need you"` (accent amber when any session
  needs input, else blue) · `across pro + air` subtitle · relative "updated" on the right.
- **Rows (needs-input first, then longest-running working):** colored dot ·
  title · `host` meta · trailing = `needs input` pill (amber) or elapsed timer (working).
- **Overflow:** `+1 working — reelly ad pipeline` muted line when > 3 sessions.

### Dynamic Island
- **compactLeading:** status dot (amber if any needs-input, else blue).
- **compactTrailing:** count, e.g. `2 ▲` — amber ▲ badge means someone needs you.
- **minimal:** one dot, amber if any needs-input else blue.
- **expanded:** header (summary + longest-run timer) + top 2 rows.

### State → color (unchanged vocabulary, now aggregated)
- **needs input / blocked → amber** (actionable — drives the whole activity's accent).
- **working → blue**, with elapsed timer.
- **idle → gray** (and, per existing logic, a fully-idle fleet ends the activity).

---

## What changes in code

### Shared attributes (`ios/Shared/LFGSessionAttributes.swift`)
Rename/replace with a fleet model. Sketch:
```
struct LFGFleetAttributes: ActivityAttributes {
  struct Row: Codable, Hashable { var sid, title, host: String; var state: String; var since: Double }
  struct ContentState: Codable, Hashable {
    var working: Int          // counts
    var needsInput: Int
    var rows: [Row]           // top N, needs-input first, capped (~4)
    var updatedAt: Double
  }
  var fleetId: String         // static; e.g. "fleet" (one activity per install)
}
```
No `sid` in attributes anymore — the activity is the fleet, not a session.

### Widget (`ios/LFGWidgets/LFGSessionActivityWidget.swift`)
Rebuild the lock-screen + Dynamic Island views to render header + rows from
`ContentState` (per the mockup). Rows already have all they need.

### iOS manager (`ios/LFG/LiveActivityManager.swift`)
Today it registers one update token per activity `sid`. New model: **one** activity
→ **one** update token (drop the `sessionId` dimension on
`registerLiveActivityUpdateToken`). Push-to-start stays the same.

### Server watcher (`src/push/watcher.ts`)
Biggest change. Today `reduceLiveActivityTransition` runs per-session. New: after
observing all sessions in a tick, **aggregate** into one `ContentState` (counts +
sorted rows), diff against the last-sent aggregate, and push a single
`start` / `update` / `end`:
- **start** when the fleet goes from 0 → ≥1 active session (needs a push-to-start token).
- **update** when the aggregate content changes (counts, row set, or any row's state).
- **end** when the fleet is fully idle for two ticks (mirrors current per-session end).
The `active` map collapses from `Map<sid, …>` to a single fleet entry.

### Server payload builders (`src/push/liveactivity.ts`)
`LiveActivityContentState` becomes the aggregate shape (counts + rows). `buildStart/
buildUpdate/buildEnd` carry the fleet content-state. `attributes` becomes `{ fleetId }`.

### Tests
`liveactivity.test.ts` + `watcher.test.ts` cover the pure builders/reducer — update
them for the aggregate reducer (start on first-active, update on aggregate change,
end on all-idle, needs-input-first ordering, row cap + overflow count).

---

## Row cap & overflow (RESOLVED during live verification)

Empirically, the lock-screen Live Activity height budget (~160pt) only fits
**header + 2 rows + "+N more"** cleanly. header + 3 rows overflows the fixed frame
and the system **center-clips it, silently dropping the header** (the most
important element). So the shipped layout is:
- **Lock screen:** header + **2** rows (needs-input-first, so the actionable
  sessions stay visible) + "+N more". The header's `N agents · M need you` count
  already conveys the fleet total.
- **Dynamic Island expanded:** header (summary + longest-run) + **2** rows.
Verified on iPhone 16 Pro (iOS 26.3) for both the needs-input (amber) and
all-working (blue) states — see `.claude/feature/evidence-live-activity/`.

## Rollout note
`LFG_LIVE_ACTIVITIES=1` already gates the feature server-side, and the attributes
type string is checked (`LIVE_ACTIVITY_ATTRIBUTES_TYPE`). Renaming the ActivityAttributes
type is a clean break — old per-session activities from a prior build won't be updated
by the new server, but they age out. Ship the app + server together.
