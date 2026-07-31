# New Session as its own view — component breakdown

**Design source:** Claude Design project `3e135dff-613d-4bd6-914d-c2a3f617ad5c`
(“# LFG iOS baseline screens”), file `LFG iOS Baseline.dc.html`, section **`3a` —
“Iteration 2 — New session as its own view”** (line 1449).

**Canonical artboards** (`ios/design/claude-design-20260731/LFG iOS Baseline.dc.html`):

| Artboard | Line | State |
| --- | --- | --- |
| `23-new-session-view` | 1455 | Idle / empty draft |
| `24-new-session-view-directory-picker` | 1506 | Directory sheet open |
| `25-new-session-view-host-picker` | 1604 | Host sheet open |
| `26-new-session-view-model-picker-grouped` | 1679 | Model sheet open + **filled draft** (send enabled) |

Local render: `python3 -m http.server 8791` in that dir →
`http://localhost:8791/LFG%20iOS%20Baseline.dc.html`.
Ground-truth capture: `ios/design/claude-design-20260731/iter2-screens-23-26.png`.

**Superseded:** section `2a` “Iteration 1 — New session flow redesign” (screens
19–22) is an earlier exploration of the same flow presented as a *sheet*. Do not
implement against it. Section `1a` screen `12-new-session-sheet` is the
*shipping* baseline being replaced.

**Not in scope:** section `4a` (Live Activity), section `5a` (Session list
restyle — owned by a concurrent session, `.claude/feature/session-list-restyle.md`).

---

## What changes vs. today

`ios/LFG/NewSessionView.swift` today is a `NavigationStack` inside a **`.sheet`**
(`RootView.swift:60`) with a horizontally-scrolling pill bar (agent / model /
directory / host) sitting above a stock `MessageComposer`. The design replaces
that with:

1. A **pushed full-screen view** with a custom nav row (circular back chevron,
   centred title) — no sheet, no Cancel button.
2. Config controls move **inside** the composer card: directory + host on a row
   above the text, model on the controls row next to the attach button.
3. **The agent picker disappears.** Agent is chosen implicitly by picking a model
   from its runtime group in the model sheet.
4. Menus become **custom bottom sheets** (grabber + circular close/confirm,
   search field, checkmark-gutter rows), not `Menu`/`Picker` popovers.
5. The directory sheet gains a **RECENT** section — new persisted state.

---

## Design tokens

Dark mode only in the design; the app is dark-mode-dominant. Use semantic colors
where a system equivalent is exact, literals where the design is specific.

### Color

| Token | Value | Used by |
| --- | --- | --- |
| `canvas` | `#000000` | screen background |
| `surfaceRaised` | `#1C1C1E` | composer card, back-button circle |
| `surfaceControl` | `#2C2C2E` | send button (idle) |
| `sheetFill` | `linear-gradient(180deg, rgba(0,0,0,0.4), rgba(18,18,18,1))` | sheet panel |
| `sheetScrim` | `rgba(0,0,0,0.5)` | behind sheet |
| `grabber` | `#333333` | sheet grabber |
| `closeButtonFill` | `rgba(120,120,128,0.32)` | sheet close circle |
| `confirmButtonFill` | `rgb(0,145,255)` | sheet confirm circle |
| `accent` | `#0A84FF` | selection checkmarks, active chevrons, send (enabled) |
| `searchFill` | `rgba(120,120,128,0.24)` | sheet search field |
| `separator` | `rgba(255,255,255,0.12)` | row separators |
| `labelPrimary` | `#FFFFFF` / `#F5F5F5` (sheet titles) | primary text |
| `labelSecondary` | `rgba(235,235,245,0.6)` | secondary text, chevrons |
| `labelTertiary` | `rgba(235,235,245,0.5)` | section headers, row paths |
| `placeholder` | `rgba(235,235,245,0.45)` | composer + search placeholder |
| `modelChipLabel` | `rgba(235,235,245,0.85)` | model chip text |
| `statusOK` | `#30D158` | reachable host dot |
| `statusWarn` | `#FF9F0A` | unreachable host dot + label |
| `brandOrange` | `#FF9F45` | LFG sparkle mark |

### Type ramp

| Role | Size / weight / line |
| --- | --- |
| Nav title | 17 semibold |
| Sheet title | 17 semibold / 22, `#F5F5F5` |
| Empty-state title | 17 semibold |
| Empty-state body | 15 regular |
| Row title | 17 regular |
| Row subtitle (host) | 13 regular |
| Row path (dir) | 12 monospaced |
| Section header | 12 semibold, tracking 0.6, uppercase |
| Chip label | 15 (directory chip **semibold**, host/model chip regular) |
| Composer text | 17 / 24 |
| Search placeholder | 17 |

### Icon → SF Symbol

| Design | SF Symbol |
| --- | --- |
| back chevron | `chevron.left` |
| chip chevron down / up | `chevron.down` / `chevron.up` |
| close ✕ | `xmark` |
| confirm ✓ | `checkmark` |
| selection ✓ | `checkmark` |
| plus (attach) | `plus` |
| send ↑ | `arrow.up` |
| search | `magnifyingglass` |
| LFG mark | custom 4-point-star shape (two stars, see below) |

---

## Components — atoms → controls → content → screens

Every row: **Source JSX/HTML** (`file · line`), **Apple HIG**, **Native target**.

### Atoms

| # | Component | Source | HIG | Native target |
| --- | --- | --- | --- | --- |
| A1 | `StatusBarMock` | `StatusBar.dc.html` | Status bars | **None** — real status bar. Design-only chrome; ignore. |
| A2 | `HomeIndicator` | `…Baseline.dc.html:1500` | — | **None** — system. Ignore. |
| A3 | `LFGSparkMark` — two 4-point stars, `#FF9F45`; large 36×36 at `left:16,top:6`, small 17×17 at `left:5,top:1`, in a 58×48 box | `:1466` | — | New `Shape` (`FourPointStar`) + `LFGSparkMark` view. Reuse the existing `clip-path` polygon: `(50 0)(60 40)(100 50)(60 60)(50 100)(40 60)(0 50)(40 40)` in unit space. |
| A4 | `SelectionCheck` — 18×18 `checkmark`, `#0A84FF`, stroke 2.4 | `:1543` | Lists — selection | `Image(systemName:"checkmark")` in an 18pt-wide gutter, `.opacity(selected ? 1 : 0)` so rows stay aligned. |
| A5 | `StatusDot` — 7px (chip) / 8px (row) circle | `:1481`, `:1629` | — | `Circle().frame(width:7/8)`. Green `#30D158` / orange `#FF9F0A`. **Do not** reuse `Theme.StatusDot` (that's session-group coloured). |
| A6 | `RowSeparator` — 1px `rgba(255,255,255,0.12)`, `margin-left:16` | `:1541` | — | `Divider()` overridden, or `Rectangle().frame(height:1)` with leading padding 16. |
| A7 | `SectionHeader` — 12 semibold, tracking 0.6, `rgba(235,235,245,0.5)`, padding `9/16/5` (dir) or `11/16/6` (model) | `:1550` | Lists — headers | Plain `Text().textCase(.uppercase)`. **Not** a `Section` header (system styling won't match). |

### Controls

| # | Component | Source | HIG | Native target |
| --- | --- | --- | --- | --- |
| C1 | `CircularBackButton` — 38×38 circle `#1C1C1E`, `chevron.left` 18pt stroke 2.6 white | `:1460` | Navigation bars — back | **Custom.** Hide the system back button (`.navigationBarBackButtonHidden`) and draw this. Keep the interactive-pop edge swipe working (`.navigationBarBackButtonHidden` kills it — re-enable via a `UIGestureRecognizerDelegate` shim or `.toolbar(.hidden)` + custom row, see Risks). |
| C2 | `NavRow` — `back · centred title · 38pt spacer`, gap 10, padding `0 14 8` | `:1459` | Navigation bars | **Custom `HStack`**, not `.navigationTitle`. The design's row is 38pt tall with no large-title area and sits directly under the status bar. Use `.toolbar(.hidden, for: .navigationBar)` and own the row. |
| C3 | `ConfigChip` — label + 12pt chevron, gap 5 | `:1477` | Pull-down buttons | **Custom `Button`.** Three variants: *directory* (15 semibold, white), *host* (dot + 15 regular `labelSecondary`), *model* (15 regular `modelChipLabel`). Chevron is `chevron.down` `labelSecondary` when closed → **`chevron.up` `#0A84FF` when its sheet is open**. |
| C4 | `SendButton` — 32×32 circle, `arrow.up` 17pt stroke 2.2 | `:1490` | Buttons | Fill `#2C2C2E` + icon `rgba(255,255,255,0.85)` when draft empty; fill `#0A84FF` + icon `#FFFFFF` when non-empty (`:1745`). Replaces `MessageComposer`'s `Color.accentColor`/gray. |
| C5 | `AttachButton` — 26×26 `plus`, stroke 1.9, `rgba(255,255,255,0.9)` | `:1488` | — | `PhotosPicker` labelled with `Image(systemName:"plus")`. Design shows a bare plus, **not** the current `paperclip`. |
| C6 | `SheetSearchField` — 36pt, radius 10, `rgba(120,120,128,0.24)`, magnifier 17 + placeholder 17 | `:1531` | Search fields | **Custom** `TextField` in a rounded rect. Not `.searchable` (that renders a system bar with different metrics). |
| C7 | `SheetHeader` — 70pt: grabber 36×4 `#333` at top 5; close 44×44 circle `rgba(120,120,128,0.32)` + `xmark` 17 at `left:16,top:13`; title centred at `top:24`; confirm 44×44 circle `rgb(0,145,255)` + `checkmark` 17 white at `right:16,top:13` | `:1518` | Sheets — grabber | **Custom.** Note corner radius on the circles is `24` on a 44pt box → effectively a circle. |
| C8 | `SheetScaffold` — design draws it inset `left/right/bottom: 6`, top varies; radius 34; gradient fill; scrim `rgba(0,0,0,0.5)` behind | `:1517` | Sheets | **System `.sheet`** with `.presentationDragIndicator(.visible)`, `.presentationCornerRadius(34)`, `.presentationBackground(.regularMaterial)`, and `.large` (directory/model) or `.medium` (host) detents. **Supersedes an earlier custom overlay** — see the deviation note below. |

> **DEVIATION — sheets are native, per Eugene (2026-08-01).** This was first built
> as a custom `ZStack` overlay, because a system sheet cannot inset 6pt from the
> sides and bottom the way the design draws it. Eugene's instruction is to follow
> Apple's native sheets, so: the 6pt side/bottom insets are **not** implemented, the
> grabber is the system drag indicator, and translucency comes from
> `.presentationBackground(.regularMaterial)` rather than the design's
> `linear-gradient(180deg, rgba(0,0,0,0.4), rgb(18,18,18))`. Panel height is a
> system detent rather than content-measured. Everything inside the sheet (header
> buttons, search field, rows, section headers) still follows the design exactly.

### Content

| # | Component | Source | HIG | Native target |
| --- | --- | --- | --- | --- |
| D1 | `EmptyDraftState` — spark mark, “Describe a task to start” (17 semibold, +8), “Your first message kicks off the session.” (15 `labelSecondary`, +6), block at `margin-top:74` from nav row | `:1464` | — | Custom `VStack`. Replaces the current `sparkles` SF Symbol + `.headline`/`.subheadline` block. |
| D2 | `ComposerCard` — `#1C1C1E`, radius 24, padding `14/16/12`, pinned `bottom:34`, horizontal 12 | `:1475` | Text views / keyboard | Extend `MessageComposer` (or a new `NewSessionComposer`) — see Layout below. |
| D3 | `DirectoryRow` — 54pt, gap 12: check gutter 18 · name 17 · path 12 mono `labelTertiary` truncating tail | `:1542` | Lists & tables | Custom row in a `ScrollView`+`LazyVStack`. **Not** `List` — an opaque `List` background seams against the translucent sheet. |
| D4 | `HostRow` — 58pt, gap 12: check gutter 18 · dot 8 · name 17 + subtitle 13 | `:1628` | Lists & tables | Same. Subtitle: `"Reachable · Default"` in `labelTertiary`, or `"Unreachable"` in `#FF9F0A`. Compose from `store.reachabilityByHost` + `host.isDefault`. |
| D5 | `ModelRow` — 44pt, gap 12: check gutter 18 · name 17 | `:1712` | Lists & tables | Same. Grouped under `SectionHeader` = `AgentKind.displayName` uppercased (`CLAUDE (CLI)`, `CODEX (CLI)`, `OPENCODE`). |

### Screens

| # | Screen | Source | Native target |
| --- | --- | --- | --- |
| S1 | `NewSessionView` idle | `:1455` | Rewrite `ios/LFG/NewSessionView.swift` |
| S2 | `DirectorySheet` | `:1506` | New — sheet top `150pt` (tall) |
| S3 | `HostSheet` | `:1604` | New — sheet top `494pt` (content-sized, 2 hosts) |
| S4 | `ModelSheet` | `:1679` | New — sheet top `190pt` |

Sheet heights are **content-driven**, not fixed detents. Implement as
`maxHeight = screenHeight - topInset` where the panel sizes to its content and
clamps: directory ≈ `h-150`, model ≈ `h-190`, host = fits content (`h-494` for
two rows). Simplest faithful rule: panel height = `min(contentHeight, h - 150)`,
anchored to `bottom: 6`.

---

## Layout — screen 23 exact metrics

From the status-bar bottom (`top:54`), inside a `390×844` frame:

```
nav row            padding 0/14/8, height 38            → back(38) gap10 title(flex,center) spacer(38)
empty state        margin-top 74 from nav row bottom
  spark mark       58×48 box, centred
  title            +8
  subtitle         +6
composer card      absolute bottom 34, horizontal 12
  card             #1C1C1E r24, padding 14/16/12
    chip row       gap 14 → [dir chip] [host chip]
    text           margin-top 12, 17/24, min-height 68
    control row    margin-top 18, gap 14 → [plus 26] [model chip] …spacer… [send 32]
```

`bottom: 34` in a 844pt frame with a 34pt home-indicator inset ⇒ the card sits on
the **safe-area bottom edge**, not floating above it. Use `.safeAreaInset(edge:
.bottom)` with **no** extra bottom padding (today's `MessageComposer` adds
`.padding(.bottom, 8)` — drop it here).

---

## New state required

| State | Where | Notes |
| --- | --- | --- |
| `recentDirs: [String]` | `AppSettings` (persisted) | MRU list of `cwd`s, capped ~5. Push on successful session start. Feeds the sheet's `RECENT` section. Design shows 3. |
| `selectedModel` implies `agent` | `NewSessionView` | Derive `AgentKind` from which runtime group the model came from. Drop the standalone `agent` picker. |
| sheet routing | `NewSessionView` | `enum ActiveSheet { directory, host, model }?` — exactly one open at a time. |

`ALL DIRECTORIES` = `store.repos` (plus `root`/`inbox` entries — today's
`Root`/`Inbox` menu items). Directory rows show `name` + full `cwd`.

---

## Navigation model

Entry: `NewSessionBar` / `EmptyListState` in `SessionListView` (`:383`, `:430`)
currently set `showNewSession = true` → `.sheet` in `RootView:60`.

**Change to a push.** `SessionListView` lives in the sidebar column of
`RootView`'s `NavigationSplitView`, which supplies a navigation stack.

- **Compact (iPhone)** — `.navigationDestination(isPresented:)` in the sidebar
  column. Collapsed split view ⇒ full-screen push with a real back gesture. This
  is what the design draws.
- **Regular (iPad)** — a push would confine the screen to the 300–460pt sidebar.
  Present the *same view* as a `.fullScreenCover` instead; the custom back
  chevron dismisses it. **Decision, not from the design** — the design is
  iPhone-only (390×844) and pushing into a 360pt sidebar is strictly worse.

On start: keep the existing optimistic path (`store.startOptimistic` →
`onCreated(placeholder)` → select the new session) and pop/dismiss.

---

## Accessibility identifiers (test contract for the verifier)

> **Container ids are deliberately absent.** `newSession.root` and
> `newSession.composer` were specified below but had to be **dropped**: SwiftUI
> propagates a container's `.accessibilityIdentifier` to every descendant, so
> putting an id on the screen root or the composer card overwrote all ten child
> ids and left the entire contract unqueryable (verified twice on-device). Only
> leaf elements carry identifiers.

| Id | Element |
| --- | --- |
| ~~`newSession.root`~~ | screen container — **removed**, see note above |
| `newSession.back` | C1 back button |
| `newSession.title` | nav title |
| `newSession.emptyState` | D1 |
| ~~`newSession.composer`~~ | D2 card — **removed**, see note above |
| `newSession.chip.directory` | C3 directory |
| `newSession.chip.host` | C3 host |
| `newSession.chip.model` | C3 model |
| `newSession.attach` | C5 |
| `newSession.send` | C4 |
| `newSession.input` | composer text field |
| `sheet.directory` / `sheet.host` / `sheet.model` | C8 panels |
| `sheet.close` / `sheet.confirm` | C7 buttons |
| `sheet.search` | C6 |
| `sheet.row.<name>` | D3/D4/D5 rows |

---

## Build order

1. **Tokens + atoms** — `Theme` additions (`NewSessionPalette`), `FourPointStar`,
   `LFGSparkMark`, `SelectionCheck`, `SectionHeader`, `RowSeparator`.
2. **Sheet chrome** — `FloatingSheet` (C8) + `SheetHeader` (C7) + `SheetSearchField` (C6).
3. **Composer** — `ComposerCard` (D2) with C3/C4/C5.
4. **Screen 23** — `NewSessionView` shell + `EmptyDraftState`. → verify
5. **Screen 24** — `DirectorySheet` + `recentDirs` state. → verify
6. **Screen 25** — `HostSheet`. → verify
7. **Screen 26** — `ModelSheet` + filled/enabled-send state. → verify
8. **Navigation swap** — sheet → push (+ iPad `fullScreenCover`), delete
   `showNewSession` sheet from `RootView`.

---

## Risks

- **`navigationBarBackButtonHidden` kills the interactive pop gesture.** The
  custom back circle must not cost the edge swipe. Standard fix: set
  `interactivePopGestureRecognizer.delegate = nil` via a `UIViewControllerRepresentable`
  shim, or hide the whole bar with `.toolbar(.hidden, for: .navigationBar)` which
  keeps the gesture. Verify by swiping — the verifier *cannot* test this
  synthetically, so it is a manual check.
- **`List` inside `FloatingSheet` will seam.** Opaque row backgrounds against a
  translucent panel is the exact artifact the verifier's internal-consistency
  check flags. Use `ScrollView` + `LazyVStack` with clear backgrounds.
- **Keyboard.** The composer is bottom-pinned; the sheets cover it. Opening a
  sheet must dismiss the keyboard, or the panel and keyboard fight.
- **Shared-file contention.** `SessionListView.swift` and `RootView.swift` are
  also touched by the concurrent session-list-restyle work. Keep edits to those
  two files **minimal and additive** (entry-point swap only); all new UI goes in
  new files.
