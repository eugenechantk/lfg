# Live Activity — per-session widgets (Claude Design artboard 4a, screen 28)

**Design source:** `claude.ai/design/p/3e135dff-613d-4bd6-914d-c2a3f617ad5c` → `LFG iOS Baseline.dc.html`, artboard `4a`, screen `28-live-activity-per-session`
**Local copy:** `ios/design/claude-design-20260731/` (entry HTML, `StatusBar.dc.html`, `support.js`)
**Rendered ground truth:** `ios/design/claude-design-20260731/4a-live-activity-ground-truth.jpg`
**Serve it:** `cd ios/design/claude-design-20260731 && python3 -m http.server 8791` → `http://localhost:8791/LFG%20iOS%20Baseline.dc.html`

> The entry HTML is truncated at the API's 256 KiB cap — artboard `5a`'s tail is cut.
> Artboard `4a` (this work) is complete and self-contained.

## Scope decisions (confirmed with Eugene, 2026-07-31)

1. **Canonical variant: screen 28 — one Live Activity per session.** Screen 27's
   aggregate fleet card is *not* being built. The existing single fleet activity
   is replaced.
2. **Directory only; the rest degrades.** `· lfg` / `· inbox` comes from
   `Session.cwd` basename (already on the wire). The diff-stat footer
   (`+142 −38 · 6 Files`) and the working subtitle (`Running xcodegen`) have **no
   server-side source** and are shipped as *optional, currently-nil* fields — the
   views degrade gracefully and light up for free if the watcher ever populates them.

---

## 1. Design tokens

Design is authored at 390 px = iPhone 16e 390 pt, dark mode. CSS px → pt 1:1.

### Colors

| Token | Value | Use |
| --- | --- | --- |
| `cardBackground` | `rgba(20,18,16,0.72)` | Activity card fill (behind it: `.activityBackgroundTint`) |
| `labelPrimary` | `#FFFFFF` | Title |
| `labelSecondary` | `rgba(235,235,245,0.70)` | "Finished" status label |
| `labelTertiary` | `rgba(235,235,245,0.60)` | Footer-left subtitle |
| `labelQuaternary` | `rgba(235,235,245,0.45)` | `· <dir>` separator text |
| `labelHost` | `rgba(235,235,245,0.40)` | Trailing host name |
| `stateWorking` | `#30D158` | "Working" label (systemGreen) |
| `stateNeedsInput` | `#FF9F0A` | "Needs input" label (systemOrange) |
| `glyphAppFill` | `#FFFFFF` | App glyph tile fill (working / finished) |
| `glyphAppDot` | `#0A84FF` | App glyph inner dot (systemBlue) |
| `glyphAlertTile` | `#3A2A22` | Needs-input glyph tile fill |
| `glyphAlertStroke` | `#F0733F` | Needs-input asterisk stroke |
| `pillReply` | `rgba(10,132,255,0.90)` | Reply pill fill |
| `pillReview` | `rgba(120,120,128,0.36)` | Review pill fill |
| `diffAdded` | `#30D158` | `+142` (only if diff data ever exists) |
| `diffRemoved` | `#FF453A` | `−38` (only if diff data ever exists) |

### Type ramp

| Role | Size / line-height / weight / tracking | SwiftUI |
| --- | --- | --- |
| Card title | 17 / 22 / semibold / −0.1 | `.system(size:17, weight:.semibold)` + `.lineSpacing(5)` + `.kerning(-0.1)` |
| Status label | 14 / regular | `.system(size:14, weight:.regular)` |
| `· <dir>` | 14 / regular | `.system(size:14, weight:.regular)` |
| Host (trailing) | 13 / regular | `.footnote` (13pt — the one semantic style that matches exactly) |
| Footer subtitle | 14 / regular | `.system(size:14, weight:.regular)` |
| Footer elapsed | 14 / regular | `.system(size:14, weight:.regular)`, `.monospacedDigit()` |
| Pill label | 14 / medium | `.system(size:14, weight:.medium)` |

> **Use the explicit point sizes, not semantic styles.** `.subheadline` is **15 pt**,
> not 14 — mapping the 14 pt labels to it puts 14 pt and 15 pt text side by side in the
> same header row. Only `.footnote` (13 pt) happens to match a design value exactly.

### Metrics

| Token | Value |
| --- | --- |
| Card corner radius | 24 |
| Card padding | top 12, leading/trailing 15, bottom 13 |
| Card-to-card gap (system-owned) | 10 |
| Header row spacing | 7 |
| Glyph tile | 16 × 16, corner radius 4 |
| Glyph inner dot | 9 × 9, corner radius 2.5 |
| Header → title | 5 |
| Title → footer | 8 |
| Pill padding | vertical 6, horizontal 14 |
| Pill corner radius | 15 |
| Title line clamp | 2 |

**Height budget:** 12 + 16 + 5 + 44 + 8 + 28 + 13 ≈ **126 pt**, inside the
~160 pt lock-screen ceiling (memory `live-activity-lockscreen-height-budget`).
Do not add a fourth row — an overheight card center-clips and silently drops the header.

---

## 2. Component breakdown

Layered atoms → controls → content → screen. Every component carries its source
JSX/HTML reference, HIG reference, and native target.

### Atoms

| Component | Source (`4a` section, screen 28) | Apple HIG | Native target |
| --- | --- | --- | --- |
| `SessionStateGlyph` | header `<div style="width:16px;height:16px;border-radius:4px…">` — three variants | — (rule 2: isolated function) | **New** `LFGWidgets/SessionActivityViews.swift`. Working/Finished: white `RoundedRectangle(4)` + `#0A84FF` `RoundedRectangle(2.5)` 9×9. Needs input: `#3A2A22` tile + 8-point asterisk stroked `#F0733F` (`Image(systemName:"asterisk")` is the closest SF Symbol; if weight/size can't match, draw the 4 crossing strokes in a `Path`). |
| `StatusLabel` | `<div style="font-size:14px;color:#30D158">Working</div>` etc. | [Color](https://developer.apple.com/design/human-interface-guidelines/color) | **New** view. Maps state → (text, color): working→("Working", `stateWorking`), blocked→("Needs input", `stateNeedsInput`), finished→("Finished", `labelSecondary`). |
| `DirectoryTag` | `<div style="font-size:14px;color:rgba(235,235,245,0.45)">· lfg</div>` | — (rule 3) | **New** view. `"· " + dir`; hidden when `dir` is empty. |
| `ActionPill` | `<div style="padding:6px 14px;border-radius:15px;background:…">Reply</div>` | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | **New** view wrapping `Link(destination:)` → `lfg://session/<sid>`. Two fills: `.reply` (`pillReply`) and `.review` (`pillReview`). |
| `ElapsedTimeText` | `<div style="…flex:none">1m</div>` | — (rule 2) | **Reuse** the existing `ElapsedTimeText` + `compactElapsed(since:at:)` from `LFGSessionActivityWidget.swift` — move both into `SessionActivityViews.swift`. |

### Content

| Component | Source | Apple HIG | Native target |
| --- | --- | --- | --- |
| `SessionActivityHeader` | first `<div style="display:flex;align-items:center;gap:7px">` | — (rule 3) | **New**. `HStack(spacing:7)`: `SessionStateGlyph`, `StatusLabel`, `DirectoryTag`, `Spacer()`, host `Text` (`.footnote`, `labelHost`, `lineLimit(1)`, `.truncationMode(.tail)`). |
| `SessionActivityTitle` | `-webkit-line-clamp:2` title div | [Typography](https://developer.apple.com/design/human-interface-guidelines/typography) | **New**. `.system(size:17, weight:.semibold)`, `.lineLimit(2)`, `.lineSpacing(5)`, `.kerning(-0.1)`, `.multilineTextAlignment(.leading)`, `.fixedSize(horizontal:false, vertical:true)`. |
| `SessionActivityFooter` | third row `<div style="margin-top:8px;display:flex…">` | — (rule 3) | **New**. `HStack`: subtitle `Text` (`.subheadline`, `labelTertiary`, `lineLimit(1)`, `.truncationMode(.tail)`), `Spacer()`, then trailing = `ActionPill` **or** `ElapsedTimeText`. See degrade rules below. |
| `SessionActivityCard` | the whole `border-radius:24` card | [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) | **New**. `VStack(alignment:.leading, spacing:0)` with the metrics above. **No explicit background/corner radius** — the system supplies the container; set `.activityBackgroundTint(Color(red:20/255, green:18/255, blue:16/255).opacity(0.72))`. |

### Screen / widget

| Component | Native target |
| --- | --- |
| Lock-screen presentation | `LFGSessionActivityWidget` rewritten against `LFGSessionAttributes` (below), rendering one `SessionActivityCard`. |
| Dynamic Island | Not in the design. Derive from the card: **expanded** leading = `SessionStateGlyph` + `StatusLabel`, trailing = `ElapsedTimeText`, bottom = title (2 lines) + footer; **compact leading** = glyph, **compact trailing** = elapsed (or `ActionPill`-less orange dot when blocked); **minimal** = glyph. `.keylineTint` = state color. |

### Footer degrade rules (the "directory only" decision, made explicit)

| State | Footer left | Footer right |
| --- | --- | --- |
| `working` | `subtitle` if non-nil, else **omitted** | `ElapsedTimeText(since:)` |
| `blocked` | `subtitle` if non-nil, else **`"Waiting on your reply"`** (static — matches the design exactly, costs nothing) | `ActionPill(.reply)` → `lfg://session/<sid>` |
| `finished` | `diffSummary` if the optional diff fields are non-nil (`+A −R · N Files`), else **omitted** | `ActionPill(.review)` → `lfg://session/<sid>` |

---

## 3. Data model changes

### `LFGCore/Sources/LFGCore/LFGSessionAttributes.swift` (new)

Mirrors the house lenient-decoding convention (every field optional with a default
and a custom `init(from:)`) — see `LFGCore/Sources/LFGCore/Models.swift`.

```
public struct LFGSessionAttributes: ActivityAttributes-shaped Codable/Hashable/Sendable {
    // Immutable attributes — set at push-to-start, never updated.
    public let sessionId: String

    public struct ContentState {
        public var state: String      // "working" | "blocked" | "finished"
        public var title: String
        public var dir: String        // cwd basename, "" when unknown
        public var host: String
        public var since: Double      // epoch seconds, for elapsed
        public var updatedAt: Double

        // Optional — no server source today; views degrade when nil.
        public var subtitle: String?
        public var added: Int?
        public var removed: Int?
        public var files: Int?
    }
}
```

`ActivityAttributes` conformance stays in the app/widget targets (ActivityKit is
unavailable to the SwiftPM package on some platforms) — follow exactly how
`LFGFleetAttributes` is currently split between `LFGCore/` and `ios/Shared/`.

### Server: `src/push/liveactivity.ts`

- `LIVE_ACTIVITY_ATTRIBUTES_TYPE` → `"LFGSessionAttributes"`.
- New `LiveActivitySessionState` type matching `ContentState` above; the
  `contentState()` sanitizer must **omit** `subtitle`/`added`/`removed`/`files`
  when undefined (don't emit `null` — the Swift decoder treats absent and null
  alike, but the payload has a 4 KB ceiling).
- `buildStart` takes `attributes: { sessionId }` instead of `{ fleetId }`.

### Server: `src/push/watcher.ts`

Replace `reduceFleetLiveActivity` with `reduceSessionLiveActivities`, keyed per session:

- **Selection & cap.** Consider sessions where `busy || promptPresent`, plus
  sessions that transitioned busy→idle this tick (→ `finished`). Sort
  `blocked` (0) → `working` (1) → `finished` (2), then by `since` ascending,
  then `sid`. **Cap at `MAX_CONCURRENT_LIVE_ACTIVITIES` = 5.** Log what was
  dropped — no silent truncation.

  > The 5 is **measured, not guessed**. Seeding activities one at a time on an
  > iPhone 17 Pro simulator (`LFG_LA_MOCK=stress8`), requests 1–5 succeed and the
  > 6th throws `targetMaximumExceeded`. Over the limit there is no graceful
  > degradation — the extra `Activity.request` calls simply fail — which is why
  > the server truncates rather than letting the client discover the ceiling.
  > Because the ordering puts `blocked` first, the five that survive are always
  > the most urgent.
- **Per-session decisions.** `active` becomes `Map<sessionId, LiveActivityActive>`.
  - not active + selected → `start` (to the device-level push-to-start tokens,
    with `attributes: { sessionId }`)
  - active + selected + content changed → `update` (to
    `listActivityUpdateTokens(sessionId)` only)
  - active + session finished → `end` with `dismissal-date = now + 480` (8 min,
    so the Finished card with its Review pill lingers, then self-dismisses)
  - active + session gone entirely → `end` immediately
- `FLEET_ACTIVITY_KEY` and `listFleetUpdateTokens` are retired.

### Server: `src/commands/serve.ts`

`POST /api/push/live-activity/update-token` accepts an optional `sessionId` in the
body and forwards it to `upsertLiveActivityToken` (the store already models it).
Absent `sessionId` keeps today's behavior so an older client doesn't 400.

### Client: `LFG/LiveActivityManager.swift`

- Watch `Activity<LFGSessionAttributes>` instead of `Activity<LFGFleetAttributes>`.
- `track(_:)` must pass `activity.attributes.sessionId` when registering the
  update token, so the server can target that one activity.
- `LFGClient.registerLiveActivityUpdateToken(_:env:)` gains a `sessionId:` parameter.
- `startMockFleetActivityIfRequested` → `startMockSessionActivitiesIfRequested`:
  under `LFG_LA_MOCK=1` request **three** activities reproducing screen 28 exactly
  (working/blocked/finished, the same strings as the design) so the widget can be
  verified in the simulator without a server.

---

## 4. Build order

1. `LFGSessionAttributes` (LFGCore + Shared) + unit tests for lenient decoding
   and the `finished` state. → `cd ios/LFGCore && swift test`
2. `SessionActivityViews.swift` atoms + `SessionActivityCard`.
3. `LFGSessionActivityWidget` rewrite (lock screen + Dynamic Island) and the
   `LFG_LA_MOCK` three-activity seed.
4. Verify in the simulator against the rendered design (screen 28).
5. Server: `liveactivity.ts`, `watcher.ts`, `serve.ts` + `bun test`.
6. Client registration wiring (`LiveActivityManager`, `LFGClient`).

Steps 1–4 are independently verifiable without touching the server, so the widget
can be proven visually before the push path changes.

## 5. Verification

- `cd ios/LFGCore && swift test` — model decoding, state mapping, elapsed formatting.
- `bun test src/push/` — the new per-session reducer: selection, cap-at-3
  ordering, start/update/end transitions, dismissal date.
- **Visual:** FlowDeck, `LFG_LA_MOCK=1`, **iPhone 17 Pro** simulator, lock screen —
  three cards matching screen 28. (The artboard's "iPhone 16e 390×844" is a canvas
  convention, not a deployment target; the house rule is to verify on iPhone 17 Pro
  regardless — see `ios/CLAUDE.md`.) Compare against
  `ios/design/claude-design-20260731/4a-live-activity-ground-truth.jpg`.
  Per repo memory `verify-ui-by-tapping`, a green unit suite is **not** verified.
- Accessibility identifiers for the verifier: `la.card.<state>`, `la.pill.reply`,
  `la.pill.review`, `la.glyph.<state>`, `la.title`, `la.footer`.
