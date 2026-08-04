# One aggregate Live Activity (frame 27)

Replaces the per-session Live Activity stack (`7464fd8`, frame 28) with a single
fleet card, per design frame `27-live-activity-lock-screen`.

## Scope

**In:** one Live Activity showing **working** + **needs-input** sessions, updating
itself as session state changes (app-driven while alive, APNs while suspended).

**Out:** unread sessions. Unread is derived from *idle* sessions
(`SessionStore.group` returns `.unread` only after the working/needsInput/blocked
checks fail), so it is by definition not active — Eugene's call, and it also
removes the only piece of state the server cannot compute (read state is
per-device `UserDefaults`, never uploaded).

## Design spec — frame 27, measured

Card: `rgba(20,18,16,0.72)`, radius 26, padding `13 / 16 / 14`.

| Element | Spec |
| --- | --- |
| Count | 20px, weight 600, tracking −0.2 |
| "Active" | 15px, `rgba(235,235,245,0.7)` |
| Counter dot | 6px circle; green `#30D158` working, orange `#FF9F0A` needs-input |
| Counter value | 13px, `rgba(235,235,245,0.6)`; gap 4 within pair, 9 between pairs |
| Row block | `margin-top: 9`, inter-row gap 7 |
| Row dot | 7px, state color |
| Row title | 15px, single line, tail-truncated |
| Row elapsed | 15px, `rgba(235,235,245,0.6)` |
| Overflow | "N More", 15px, `rgba(235,235,245,0.45)`, `margin-left: 16` |

Header order is green-then-orange; **row** order is needs-input first (the
actionable ones survive truncation).

These hexes already exist in `Theme.statusColor` (`.working` `0x30D158`,
`.needsInput` `0xFF9F0A`) and in `SessionActivityViews`' `Color` extension — reuse,
don't redeclare.

### Height risk

Memory `live-activity-lockscreen-height-budget`: the lock screen is a **fixed
~160pt frame**; overheight content is *center-clipped*, which silently drops the
header. The previous fleet card hit this with `header + 3 rows + overflow` and was
capped at 2 rows.

Frame 27's rows are leaner (no host pill, no divider). Measured from the design:
`13 + 24 + 9 + (3×18 + 2×7) + 7 + 18 + 14 ≈ 153pt` — fits, but with ~7pt of margin.

**Decision: build 3 rows per the design, then settle it by screenshot.** If the
header clips on device, drop to 2 rows and let the third fold into "N More". This
is not decidable from source — lock-screen Live Activity text is not in the
accessibility tree, so only a screenshot can catch it.

## Wire type — `LFGFleetAttributes.ContentState`

```
working:   Int
needsInput: Int
rows:      [Row]   // max 3, needs-input first
more:      Int     // active sessions beyond `rows`
updatedAt: Double

Row: sid, title, state ("working" | "needsInput"), since
```

Changes from the retired version: **add** `more`; **drop** `hosts` and `Row.host`
(frame 27 renders neither). Lenient decoding throughout, per repo convention.

`state` is renamed `blocked` → `needsInput`. The old wire string was `blocked`,
which collides with `SessionStore.Group.blocked` (= *paused*, a different thing,
and a different colour — yellow `0xFFD60A`). No compatibility cost: the fleet
activity is currently dead code, and `FleetActivityController` ends any lingering
one on launch.

## Work

| # | Change | Where |
| --- | --- | --- |
| 1 | Wire type: add `more`, drop `hosts`/`Row.host`, rename state | `Shared/` + `LFGCore/…/LFGFleetAttributes.swift` |
| 2 | Snapshot: emit `more`, drop host inputs, rename state | `LFGCore/…/FleetActivitySnapshot.swift` + tests |
| 3 | Card + Dynamic Island at design tokens | `LFGWidgets/FleetActivityViews.swift` (new) |
| 4 | Widget declares `LFGFleetAttributes` | `LFGWidgets/LFGSessionActivityWidget.swift` |
| 5 | Revive app-driven controller (start/update/end) | `LFG/FleetActivityController.swift` |
| 6 | Track `Activity<LFGFleetAttributes>` tokens | `LFG/LiveActivityManager.swift` |
| 7 | Fleet reduce; delete per-session path + the 5-activity cap | `src/push/watcher.ts`, `liveactivity.ts` |
| 8 | Retire per-session type + views | `LFGSessionAttributes.swift`, `SessionActivityViews.swift` |

Steps 5+7 are the "updates itself" requirement: the controller re-arms a
`withObservationTracking` loop over `SessionStore` for instant updates while the
app runs; the watcher pushes over APNs while it is suspended. Both now compute
identical state, so there is no fidelity seam between them.

Deleting the cap is a real win: one activity can never hit
`targetMaximumExceeded`, so the server stops truncating and logging dropped
session ids.

## Verification — done

Automated: `swift test` 182/182, `bun test` 192/192, `tsc --noEmit` clean,
`flowdeck build` succeeded.

Live on **iPhone 17 Pro** (`ios/design/verify-20260804/`):

| Check | Evidence | Result |
| --- | --- | --- |
| Renders frame 27 (3 rows + "N More", header survives the ~160pt frame) | `lock-clean.png` | pass |
| Matches the rendered design side by side | `compare-design-vs-app.png` vs `design-frame27.png` | pass |
| No card when nothing is active | `live-real-1.png` | pass |
| **Starts** from real `SessionStore` state (1 Active) | `live-real-working2.png` | pass |
| **Updates itself in place** as state changes (1 → 2 Active, per-row timers) | `live-real-updated.png` | pass |
| Dynamic Island compact (accent dot + count) | `island-crop.png` | pass |

The start/update runs were driven by **real sessions on the live host**, not the
mock — the mock (`LFG_LA_MOCK`) was only used for the frame-27 comparison, since
seeding 5 sessions with a needs-input row on demand isn't practical.

### Not verified

- **Needs-input (orange) rows with real data.** Verified via the mock only; forcing
  a genuine pending prompt on demand wasn't practical. The row state comes from the
  same `prompts` map the session list already renders, and the reduce path is
  unit-tested both sides.
- **The APNs push path end to end.** The simulator cannot receive real APNs pushes,
  so `watcher.ts` → device is covered by unit tests only. Consequence, observed and
  expected: while the phone is locked the app is suspended, so the card does not
  update until either an APNs push arrives or the app is foregrounded.

### Height-budget note

Memory `live-activity-lockscreen-height-budget` said to cap at 2 rows. That was a
measurement of the *old* row (host pill + divider + larger type), not a general
rule. Frame 27's lean row measures ~153pt for `header + 3 rows + "N More"` against
the ~160pt frame, and the screenshot confirms the header survives. Memory updated.
