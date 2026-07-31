# Session list restyle — Claude Design §5a "Iteration 4"

**Design source:** https://claude.ai/design/p/3e135dff-613d-4bd6-914d-c2a3f617ad5c
· page `LFG iOS Baseline.dc.html` · section `#5a` · screens **29–34**
**Local render:** `ios/design/claude-design/session-list-5a.html` (serve with
`python3 -m http.server 8899` in that dir → `http://localhost:8899/session-list-5a.html`)
**Target:** `ios/LFG/SessionListView.swift` (+ `Theme.swift`, `LFGApp.swift`)
**Tier:** product (shipping TestFlight app) — full verify loop required.

> The design was rendered and read as ground truth before this spec was written.
> All values below are measured from the rendered artboards, not guessed.

---

## 1. What changes

The list moves from a **system `List(.insetGrouped)` inside a navigation bar** to a
**custom header + full-bleed plain rows on black**. Rows lose their icon tile and
badge pills and become: *dot · title · one meta line*.

| Area | Today | Design §5a |
|---|---|---|
| Title | `navigationTitle("Sessions")`, large-title nav bar | Custom row: "All sessions" 30pt/bold + 3 circular buttons |
| Chrome buttons | gear (topBarLeading), search + filter (topBarTrailing) | search / group-sort / gear — all three as 38pt circles, trailing |
| List style | `.insetGrouped`, grouped cards | Plain, full-bleed, black background |
| Row leading | `AgentBadge` icon tile | 8pt status dot |
| Row body | title + [dot, project, ModelBadge, host capsule, time] | title + single meta line `dir · model · time` + host glyph |
| Separators | system insetGrouped | 1px `rgba(255,255,255,0.07)`, inset 39pt |
| Grouping | Status, Directory | Status, Directory, **Host** (new) |
| Sorting | none | **Recent activity / Name** (new) |
| Collapse | Directory sections only | **All modes** collapsible |
| Group header | UPPERCASE caption + count/badges | chevron + Title-case 15pt + count |
| Composer | `NewSessionBar` capsule, material | `#1C1C1E` capsule h52 r26, plus + placeholder + **mic** |

## 2. Preserved behavior (design mock shows none of these — keep them all)

The mock had no such data; absence is not removal. **Do not drop:**

- Agent child-row nesting + the "N agents" disclosure (status mode).
- "Mark all read" affordance on the Unread group.
- "Load more" row at the bottom of Closed (`canLoadMoreClosed`).
- `ConnectionBanner` when aggregate reachability is not `.ok`.
- `EmptyListState` (connected / not-connected variants).
- Offline row dimming (`opacity 0.55`) + orange host treatment.
- Pull-to-refresh (`.refreshable`).
- The `blocked` / "Paused" group (absent from the mock's data only).
- Multi-host filtering + the `statusSubtitle` status string.
- All existing accessibility identifiers.

## 3. Tokens

### Status dot colors — **changed by the design**

| Group | Today | Design | Note |
|---|---|---|---|
| working | green | `#30D158` | same |
| unread | purple | `#BF5AF0` | same |
| closed | secondary 45% | `rgba(235,235,245,0.30)` | same intent |
| **needsInput** | blue | **`#FF9F0A`** orange | changed |
| **idle** | secondary gray | **`#0A84FF`** blue | changed |
| blocked | orange | — *not in mock* | → **`#FFD60A`** yellow, to stay distinct from the new orange needsInput |

### Surfaces / text

| Token | Value |
|---|---|
| screen bg | `#000000` |
| raised surface (buttons, search field, composer) | `#1C1C1E` |
| menu surface | `#2C2C2E` |
| separator | `rgba(255,255,255,0.07)` |
| label | `#FFFFFF` |
| label-secondary | `rgba(235,235,245,0.60)` |
| meta text | `rgba(235,235,245,0.50)` |
| label-tertiary / count | `rgba(235,235,245,0.30)` |
| host glyph + text | `rgba(235,235,245,0.40)` |
| placeholder | `rgba(235,235,245,0.45)` |
| accent (check, caret) | `#0A84FF` |

## 4. Components — exact geometry

All values are **pt**, measured from the rendered artboards at 390×844.

### 4.1 Header (`29`, all screens)
- Container: `padding 6 / 16 / 2`, space-between.
- Title "All sessions": **30pt, weight 700, tracking −0.6**.
- Button cluster: `gap 10`; each button **38×38 circle**, bg `#1C1C1E`,
  glyph **19pt**, stroke-width 2 (gear 1.6), white.
- Order: magnifying-glass, group/sort (`line.3.horizontal.decrease`), gear.
- Active state: the group/sort button turns **`#0A84FF`** while its menu is open (`30`).
- SF Symbols: `magnifyingglass`, `line.3.horizontal.decrease`, `gearshape`.

### 4.2 Group header — expanded (`29`, `31`, `32`, `34`)
- Section spacing: `margin-top 20`.
- Header: `padding 0 / 20 / 8`, `gap 9`.
- Chevron `chevron.down`, **13pt**, weight ~bold, `rgba(235,235,245,0.40)`.
- Name **15pt**, `rgba(235,235,245,0.60)` — **Title case, not uppercase**.
- Count **15pt**, `rgba(235,235,245,0.30)`.

### 4.3 Group header — collapsed (`33`)
- Row **height 54**, `padding 0 20`, `gap 9`.
- Chevron `chevron.right`, 13pt, `rgba(235,235,245,0.40)`.
- Name **17pt, full white** (brighter than the expanded state), fills width.
- Count **17pt**, `rgba(235,235,245,0.30)`, trailing.
- Separator below, inset **20** from leading.

### 4.4 Session row (`29`)
- `padding 15 / 20 / 16`, `gap 11`.
- Dot: **8×8 circle**, `margin-top 6` (aligns to the title's first line), fixed.
- Title: **17pt / line-height 22**, white, **1 line**, tail-truncated.
- Meta line: `margin-top 4`, `gap 7`:
  - text **15pt / lh 20**, `rgba(235,235,245,0.50)`, 1 line, truncated —
    content `"<dir> · <model> · <relative time>"`; closed rows omit the model
    (`"inbox · 40m"`).
  - host cluster (fixed, never truncates): `gap 4`, glyph **12pt**
    (`display` / desktop-computer icon) + text **13pt / lh 20**, both
    `rgba(235,235,245,0.40)`.
- Separator: 1px `rgba(255,255,255,0.07)`, inset **39** from leading
  (= 20 padding + 8 dot + 11 gap).

> The host cluster is shown on **every** row in the mock. Keep the existing rule
> — only render it when `settings.hosts.count > 1` — and let the meta text take
> the full width otherwise.

### 4.5 Group/Sort menu (`30`)
- Anchored below the group/sort button: `top 104, right 16`, **width 236**.
- Surface `#2C2C2E`, **radius 14**, shadow `0 14 44 rgba(0,0,0,0.6)`.
- Section labels "GROUP BY" / "SORT BY": **12pt, weight 600, tracking 0.6**,
  `rgba(235,235,245,0.50)`, `padding 9 / 15 / 5`.
- Items: **height 44**, `padding 0 15`, `gap 11`, label **17pt** white.
- Checkmark **17pt `#0A84FF`** on the selected item; unselected items reserve a
  17pt-wide empty leading slot so labels stay aligned.
- Dividers `rgba(255,255,255,0.08)`: inset 15 between items **within** a section,
  **full-width** between sections.
- Contents: GROUP BY → Status · Directory · **Host**; SORT BY → **Recent activity** · **Name**.

**Implement as a native `Menu`** with two `Picker`s (`.pickerStyle(.inline)`),
sectioned — do not hand-build the popover. This is a *system-control-to-theme*
mapping; the native menu's own material/metrics are the correct translation.

### 4.6 Search field (`34`)
- `margin 8 / 16 / 0`, **height 40**, **radius 12**, bg `#1C1C1E`.
- `gap 9`, `padding 0 12`; glyph 18pt `rgba(235,235,245,0.60)`; text **17pt**;
  caret `#0A84FF`.
- Appears **below** the header, above the list; header stays visible.

### 4.7 Composer bar (`29`, all screens)
- Pinned bottom: `bottom 26, leading/trailing 12`.
- Surface `#1C1C1E`, **radius 26**, **height 52**, `gap 12`, `padding 0 14`.
- Leading `plus` **24pt**, `rgba(255,255,255,0.90)`, stroke 1.9.
- Placeholder "Plan, ask, build…" **17pt**, `rgba(235,235,245,0.45)`.
- Trailing `mic` **20pt**, `rgba(235,235,245,0.60)` — **new affordance**.
- The bar scrolls *over* content (content passes behind it, see `31`/`34`).

> Mic: wire it to the same new-session action for now unless dictation already
> exists — do **not** ship a dead control; if it can't do anything real, open the
> new-session sheet with the composer focused.

## 5. New state

Add to `AppSettings` (persisted, same pattern as `groupMode`):

- `GroupMode` gains `case host` — label "Host". Group key = owning host's label
  via `store.host(forSession:)`; sessions with no host fall into a trailing
  "Unknown host" bucket. Only offer this mode when `settings.hosts.count > 1`
  (with one host it is a single meaningless group).
- New `SortMode: String, CaseIterable { case recentActivity, name }` —
  labels "Recent activity" / "Name". `recentActivity` = existing
  `lastActivityAt` descending (the current behavior, so it is the default);
  `name` = `session.title` case-insensitive ascending. Sort applies **within**
  each group, not across groups.
- Collapse state: today `expandedDirs` only covers directory mode. Generalize to
  one `collapsedSections: Set<String>` keyed by section id, applying in **all**
  modes. **Default = expanded** (screens 29/31/32 show groups open; 33 is the
  after-tap state). Keep it in-memory per run, as today.

## 6. Structural notes for implementation

- Replacing `List` with `ScrollView` + `LazyVStack` is the honest translation of
  full-bleed rows on black — an inset-grouped `List` cannot produce this. But
  that costs `.refreshable`, swipe actions, and `List` selection binding.
  **Prefer keeping `List` with `.listStyle(.plain)`**, `.listRowInsets(EdgeInsets())`,
  `.listRowBackground(Color.black)`, `.listRowSeparator(.hidden)` and a
  hand-drawn separator per row. That preserves selection, refresh, and swipe
  while matching the design. Only fall back to `ScrollView` if `List` cannot hit
  the geometry.
- The custom header replaces the nav bar on iPhone:
  `.toolbar(.hidden, for: .navigationBar)` on this screen only. **Do not** hide
  it globally — `RootView` is a `NavigationSplitView` and the detail column and
  iPad sidebar chrome must keep their bars.
- iPad: the list is the sidebar column. Verify the custom header does not fight
  the split-view sidebar's own title; keep `sidebarStatusSubtitle` reachable
  (fold the status string under the "All sessions" title if the nav bar is gone).
- Row selection must still drive `selection` binding → detail push.

## 7. Accessibility identifiers (test contract)

Keep existing (`sessionSearchToggle`, `sessionSearchField`, `sessionSortMenu`,
`newSessionBar`, `loadMoreClosedButton`) and add:

| id | Element |
|---|---|
| `sessionListHeader` | "All sessions" title |
| `sessionSettingsButton` | gear circle |
| `sessionGroupHeader-<sectionId>` | each group header (tap = collapse) |
| `sessionRow-<sessionId>` | each session row |
| `sessionComposerBar` | bottom composer capsule |
| `sessionComposerMic` | mic button |
| `groupModeOption-<mode>` / `sortModeOption-<mode>` | menu items |

## 8. Verification criteria

1. Screens 29, 30, 31, 32, 33, 34 each match the artboard geometry above.
2. Grouping by Status / Directory / Host each render correct sections + counts.
3. Sort by Name reorders within a group; Recent activity restores.
4. Tapping a group header collapses it to the 54pt row (screen 33) in **every** mode.
5. Search shows the field (screen 34), filters, and header stays put.
6. Every §2 preserved behavior still works — specifically: agent nesting,
   load-more, empty state, connection banner, offline dimming, pull-to-refresh.
7. Row tap still opens the detail; iPad split view unbroken.
8. `cd ios/LFGCore && swift test` green.
