# Delegation Brief: Liquid Glass chrome + per-host status header (iOS)

## Goal

Three visual changes to the iOS client, all in `ios/LFG/`:

1. Buttons in the session list and the new-session view adopt Liquid Glass.
2. The bottom "Plan, ask, build…" bar of the session list adopts Liquid Glass.
3. The header host status shows a status dot **per host**, at a smaller font, with a
   `·` divider between hosts.

## Hard constraint: availability gating

The app's deployment target is **iOS 17.2** (confirmed from the uploaded builds'
`minOsVersion`). Every Liquid Glass API is iOS 26+. So **every** glass call must be behind
`#available(iOS 26, *)` with a fallback that preserves today's appearance — the existing
`Tokens.raised` fill in the same shape, NOT `.ultraThinMaterial` (that would change the
look on older OS versions rather than leave it alone).

Put the gate in one reusable place (a small `View` extension / `ViewModifier` such as
`glassOrRaised(in:)`) instead of repeating `if #available` at every call site.

## Current state

- `headerButton(_:size:weight:background:action:)` — `SessionListView.swift:615`. Renders
  the search / filter / gear circles as `.background(Tokens.raised, in: Circle())`.
- `NewSessionBar` — `SessionListView.swift:760`. The bottom bar: plus button, "Plan, ask,
  build…" label, mic button, wrapped in `.background(Tokens.raised, in: Capsule())`,
  presented via `.safeAreaInset(edge: .bottom)`.
- `statusHeadline` / `statusSubtitle` / `statusTint` — `SessionListView.swift:683-712`.
  Multi-host currently builds one string ("<names> online · <names> offline") with a single
  shared dot, which truncates to "Eugenes-MacBook-Pro, Air…" at the current large title size.
- `NewSessionView.swift` — the agent / model / directory chips and its bottom composer.
- `MessageComposer.swift:126` already uses `.glassEffect(.regular, in: .rect(...))` — follow
  that precedent, and gate it too if it isn't already.

## Spec

### 1 + 2 — Glass chrome

Apply glass to the **controls**, not to the list background or system-owned surfaces:

- The three header circles (search, filter, gear). They sit adjacent, so wrap the cluster in
  a `GlassEffectContainer` so they blend/merge correctly rather than three isolated effects.
- The bottom `NewSessionBar` capsule.
- Buttons and chips in `NewSessionView` (agent, model, directory pickers, and its send
  control).
- Interactive elements get `.regular.interactive()`; non-interactive surfaces get `.regular`.
- Apply the glass modifier **last** in the chain, after frame/padding/content modifiers.

Prefer the system style where the control is a plain button — `.buttonStyle(.glass)` — over
hand-applying `.glassEffect` to a button label, per Apple's guidance. Use `.glassEffect`
for the custom capsule/circle surfaces that aren't plain buttons.

Do **not** add glass to: list rows, section headers, the navigation bar itself, or any
system sheet/toolbar. Those are system-owned or content, and glass there fights the system.

For the bottom bar specifically: if switching `.safeAreaInset(edge: .bottom)` to
`.safeAreaBar(edge: .bottom)` keeps the current layout, prefer it — it lets the system
maintain legibility where content scrolls under the bar. If it changes layout or spacing
noticeably, keep `safeAreaInset` and say so in your report.

### 3 — Per-host status header

Replace the single-dot, comma-joined string with a per-host rendering:

- For **each** configured host: a small filled circle tinted by *that host's* reachability
  (`store.reachabilityByHost[host.id] == .ok` → green, otherwise orange), immediately
  followed by that host's label.
- Separate consecutive hosts with a `·` divider that is visually distinct from the dots
  (dimmer/secondary, and not the same size as a status circle — the point is that a reader
  can tell "status dot" from "separator" at a glance).
- **Reduce the font size** relative to today's headline so two or three hosts fit without
  truncating. Keep it legible and consistent with the app's type scale (`Tokens`).
- Single-host behavior should stay recognisable: its own dot plus the existing
  "Connected · N running" style text.
- Long host names still need graceful truncation when there are many hosts — truncate the
  *names*, never drop a host's status dot.

Today's `statusTint` (one shared colour, orange if any host is down) becomes redundant for
multi-host once each host has its own dot; remove or repurpose it rather than leaving a
misleading second signal. Note the current behavior is actively confusing: with the Pro
online and the Air offline, the shared dot still renders green.

## Constraints

- Only `ios/LFG/` (plus `ios/LFGCore/` if you add a testable pure helper). Do not touch
  `src/`, `web/`, or `desktop/`.
- Do not restart the lfg server, kill tmux sessions, or `git push`.
- **Do not run or launch the app, and do not start a `flowdeck ui simulator` session** — a
  simulator is in use for verification. Build only.
- Respect accessibility: glass must degrade correctly under Reduce Transparency; don't
  encode host status in colour alone where a shape/label already exists.

## Verification

1. `cd ios/LFGCore && swift test` — green (164 currently pass).
2. `cd ios && flowdeck build -w LFG.xcodeproj -s LFG -S "0F95D0E2-5B76-40BF-8EC1-FD605E4CB71D"`
   — must succeed. If your sandbox blocks the flowdeck state lock, say so explicitly rather
   than reporting an unverified build.
3. If you extract a pure helper for the host-status model (e.g. building the ordered
   [dot, label, divider] sequence), unit-test it in `LFGCoreTests`. If the change is only
   reachable from the app target, say so rather than inventing a test.

Claude will verify appearance by screenshotting the running app on a simulator with two
hosts configured (one online, one offline) — the exact state the header must handle.

## Definition of done

- [ ] All glass calls gated on iOS 26 with a `Tokens.raised` fallback, via one shared helper
- [ ] Header button cluster, bottom bar, and new-session view controls use Liquid Glass
- [ ] Header shows one status dot per host, smaller font, `·` dividers, no truncation at 2 hosts
- [ ] No glass applied to list rows or system-owned surfaces
- [ ] `swift test` green; app builds

## Report back

Files changed, verification output, whether `safeAreaBar` worked for the bottom bar, how you
gated availability, and anything you could not verify without running the app.
