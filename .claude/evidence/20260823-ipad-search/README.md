# iPadOS session search — evidence, 2026-08-23

Device: iPad Pro 11-inch (M5), iPadOS 26.3, sim `cc-328742d3-ipad`
(2C455021-6A0E-449E-83B8-1AA6D6D93F81). iPhone control: iPhone 17 Pro,
sim `cc-328742d3` (1523D90E-AE2D-4DE1-B8CC-B8E4422597FA).

## Symptom (before)

Sidebar bottom bar showed the `+` alone — no search field anywhere on screen.
Accessibility tree contained `newSessionBar` and no search element at all.

## Root cause, proved by experiment

Temporarily removed `.toolbar(.hidden, for: .navigationBar)` from
`SessionListView` and rebuilt: the *same* `.searchable` immediately rendered a
"Search sessions" field at the TOP of the sidebar, in the navigation bar.

So on iPadOS `.searchable(placement: .toolbar)` resolves into the sidebar
column's navigation bar; `DefaultToolbarItem(kind: .search, placement:
.bottomBar)` is a no-op there. With the nav bar hidden the field had nowhere to
go. The `+` kept rendering because it is an ordinary `.bottomBar` toolbar item,
which made the bar look intact.

## Fix

`bottomSearchChrome` takes the system iOS 26 path only when
`userInterfaceIdiom != .pad`; iPad uses the hand-built `BottomSearchBar`
(formerly `LegacyBottomSearchBar`), now Liquid-Glass styled on 26. Keyed on
idiom rather than size class so an iPad in Slide Over cannot lose search again.

## After

- `after-ipad11-search-filtered.png` — search field at the bottom of the
  sidebar; typing "paywall" filtered Working/Unread/Closed across both hosts,
  clear button present.
- `after-iphone-unchanged.png` — iPhone still on Apple's system bottom search
  toolbar. Discriminating check: the iPhone accessibility tree contains neither
  `sessionSearchField` nor `newSessionBar` (system chrome), while the iPad tree
  contains both — so iPhone is provably still on the system path.

## Verified

- iPad 11" portrait, side-by-side split (detail centred in the region right of
  the sidebar) — field renders, typing filters live.
- iPad 13" (M5) — field renders in the same place.
- iPhone 17 Pro / iOS 26.3 — unchanged.

## NOT verified

- Landscape orientation: FlowDeck has no device-orientation command and the
  login session is headless (Simulator.app has no windows), so rotation was
  unavailable. Layout is column-scoped, and side-by-side was covered in
  portrait, so this is width, not a separate code path.
- Keyboard avoidance with the software keyboard up: not reproducible headless
  (memory `sim-keyboard-needs-simulator-app`). The same `safeAreaInset`
  component already ships on iPhone below iOS 26.
- Pre-iOS-26 rendering: unchanged by construction — `glassOrRaised`'s fallback
  branch is exactly the previous `.background(fallback, in: shape)`.
