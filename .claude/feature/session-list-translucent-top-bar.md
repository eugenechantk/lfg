# Feature: session-list-translucent-top-bar

## User Story

As Eugene, scrolling the session list, I want the top bar (host status + filter / terminal /
settings buttons) to be translucent like the session view's top bar, so rows pass visibly under
it instead of being cut off by an opaque slab.

## User Flow

1. Open the app → session list.
2. Scroll the list up. Rows slide under the header, blurred and dimmed by the same glass ramp
   the session view uses; the status line and the glass buttons float on it.
3. At rest (scrolled to top) the first row sits fully below the header, as today.

## Success Criteria

- [x] SC1: List rows scroll underneath the header and are visible (blurred/dimmed) through it — **Verify by:** sim screenshot of the list scrolled mid-way on iPhone 17 Pro; row content visible in the header band, vs. the old build where the band is solid `Tokens.screen`.
- [x] SC2: At rest the first row is not obscured by the header — **Verify by:** sim screenshot at scroll-top; first row fully below header.
- [x] SC3: The fade is the same treatment as the session view (one shared implementation, not a copy) and the session view is visually unchanged — **Verify by:** code review (single `TopChromeFade` used by both) + session view screenshot.
- [x] SC4: Header buttons still respond (the fade does not eat touches) — **Verify by:** tap settings button in sim, settings sheet opens.
- [x] SC5: iPad sidebar renders the header correctly (adaptive chrome rule) — **Verify by:** iPad sim screenshot.
- [x] SC6: Builds for the iOS 18 deployment target (pre-26 fallback compiles; uses `.bar` material) — **Verify by:** build succeeds; fallback branch reviewed.

## Platform & Stack

- **Platform:** iOS (SwiftUI), iOS 18 min, Liquid Glass on 26+
- **Files:** `ios/LFG/Theme.swift` (shared fade), `ios/LFG/SessionListView.swift`, `ios/LFG/SessionDetailView.swift`

## Steps to Verify

1. FlowDeck build + run on iPhone 17 Pro.
2. Screenshot list at rest; swipe up; screenshot mid-scroll.
3. Tap settings button → sheet opens.
4. Open a session → top fade unchanged.
5. Repeat list screenshots on an iPad sim.

## Implementation Phases

### Phase 1: shared fade + list header as a top safe-area inset

- Extract `topChromeFade` from `SessionDetailView` into `TopChromeFade` (Theme.swift).
- `SessionListView`: header moves from a `VStack` sibling above the `List` to
  `.safeAreaInset(edge: .top)` on the list, backed by `TopChromeFade` (26+) or `.bar` (older).

## Decision Log

- "Session view … like that in the session view" read as: the session **list** top bar should
  match the session **detail** top bar. The detail view is the only one with a translucent bar;
  the list is the one with an opaque header.
- Reuse the hand-built fade rather than the system scroll-edge effect: the request is "like the
  session view", and two different blur treatments side by side in a push transition would read
  as inconsistent. System top edge effect hidden on the list so they don't stack.
- The list holds the glass at full strength down to the header's **midline** (`barRow:
  frame.height / 2`), where the session view eases from the top of its nav row. Found on iPad:
  the sidebar panel starts below the status bar, so the strong part of the ramp was clipped off
  and the whole header sat in the weak half — row titles ran legibly through the host status
  line (`07-ipad.png` / `crop-07.png`). Same shared view, one knob; session view untouched.
- Independent auditor NOT run: three stock simulators were already booted on the Air and the
  result is a visual-taste call Eugene grades from the screenshots. Flagged in the hand-off.

## Verification Evidence

Evidence dir: `.claude/evidence/list-translucent-top-bar-20260920/`. iPhone 17 Pro (cc-9657ff48,
iOS 26.5) + iPad Pro 11" M5 (cc-9657ff48-ipad, deleted after), live data from the Air host.

| SC | Action | Result | Artifact |
| --- | --- | --- | --- |
| SC1 | swipe list up, light + dark | rows visible, blurred/dimmed under header and status bar | `03-list-scrolled-light.png`, `04-list-scrolled-dark.png`, `10-iphone-v2-dark.png` (+`crop-10.png`, tuned ramp) |
| SC2 | launch, no scroll | "Working" header and first row fully below the bar, iPhone and iPad | `02-list-at-rest.png`, `09-ipad-rest.png` |
| SC3 | open a session; `grep topChromeFade` → none left, both call `TopChromeFade` | session view fade unchanged | `06-session-view-dark.png` |
| SC4 | tap `sessionSettingsButton` through the fade | Settings sheet opened | `05-settings-opened.png` |
| SC5 | iPad sidebar, at rest + scrolled | header renders inside the sidebar panel; v1 weakness found and fixed (see Decision Log) | `07-ipad.png`, `08-ipad-v2.png`, `09-ipad-rest.png` |
| SC6 | `flowdeck run` ×3 (deployment target 18.0) | BUILD succeeded; pre-26 branch is `Rectangle().fill(.bar).ignoresSafeArea(edges: .top)` — compiled, not run (no iOS 18 runtime on this host) | build output |

Not verified: the pre-iOS-26 fallback at runtime; a deep scroll on iPad with the tuned ramp (the
list was only ~35pt taller than the viewport at capture time).

## Bugs

_None yet._
