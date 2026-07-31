# Delegation Brief: Session list restyle (lfg iOS client)

## Goal

Restyle the lfg iOS client's session list to match Claude Design §5a "Iteration 4 —
Session list restyle" (screens 29–34), and add the two new capabilities that design
introduces (Host grouping, Sort by name), **without losing any existing behavior**.

## Read these first — they are the spec

1. **`.claude/feature/session-list-restyle.md`** — the full spec. Exact pt geometry,
   colors, per-component measurements, preserved-behavior list, new state model,
   a11y identifiers, and verification criteria. **This is authoritative; follow it
   literally.** Every number in it was measured off the rendered design, not guessed.
2. **`ios/CLAUDE.md`** — iOS conventions and traps for this repo. Non-negotiable.
3. **`ios/design/claude-design/session-list-5a.html`** — the design itself. To view it:
   `cd ios/design/claude-design && python3 -m http.server 8899`, then open
   `http://localhost:8899/session-list-5a.html`. Screens 29–34 left to right.
   Read the markup directly for any value the spec doesn't name.

## Files

**Edit:**
- `ios/LFG/SessionListView.swift` — the main work (header, rows, group headers, menu,
  search field, composer bar, collapse state).
- `ios/LFG/Theme.swift` — `statusColor` remapping (see spec §3).
- `ios/LFG/LFGApp.swift` — `GroupMode.host`, new `SortMode`, persisted in `AppSettings`.

**Do NOT touch:**
- `ios/LFG/SessionStore.swift` — the state core. If you believe you need a change there,
  stop and report it instead; it is high-traffic and another agent session may be in it.
- `ios/LFGWidgets/` — another session is actively working there right now.
- `ios/LFGCore/` — no API/model change should be needed for this task.
- Any server code (`src/`), the desktop app, or the web client.

## Constraints

- **Swift 6, strict concurrency complete.** `@MainActor` where the existing code is.
- **`project.yml` is the source of truth**, not `LFG.xcodeproj`. If you must add a file,
  edit `project.yml` then `cd ios && xcodegen generate`.
- Follow the existing file's style: private computed properties for derived state,
  `@ViewBuilder` helpers, doc comments explaining *why* on non-obvious decisions
  (the file already does this well — match its density).
- Non-UI logic belongs in `LFGCore` with a test. If you add a pure function (e.g. the
  name-sort comparator or the host-group key), put it in `LFGCore` and unit-test it.
- Dark mode is the only mode the design specifies. Do not regress light mode into
  something broken — use semantic/asset colors where the spec's value is just the dark
  rendering of an existing semantic color, and hard-code only where the spec is explicit.

## Spec summary (details in the spec doc)

Plain English, no implementation code:

1. **Header.** Replace the navigation bar on this screen with a custom header row:
   "All sessions" in 30pt bold on the left, three 38pt circular buttons on the right
   (search, group/sort, settings). Hide the nav bar **for this screen only** — `RootView`
   is a `NavigationSplitView` and the detail column must keep its bar.
2. **Rows.** Full-bleed on black. Leading 8pt status dot, then a 17pt single-line title,
   then a 15pt meta line reading `directory · model · relative-time`, then a fixed host
   cluster (small display glyph + 13pt host label) shown only in multi-host setups.
   Hairline separator inset 39pt. Drop the agent icon tile and the model/host pill chips.
3. **Group headers.** Chevron + Title-case name + count. Tapping collapses the group to a
   54pt row (screen 33) — and this now works in **every** grouping mode, not just directory.
   Default state is expanded.
4. **Group/Sort menu.** A native `Menu` with two inline `Picker`s in sections:
   GROUP BY (Status / Directory / Host) and SORT BY (Recent activity / Name). Do not
   hand-build the popover — the native menu is the correct translation. The trigger
   button tints blue while the menu is open.
5. **Search.** Inline field below the header (not a nav-bar searchable), 40pt tall,
   radius 12. Header stays visible while searching.
6. **Composer bar.** Bottom-pinned capsule, 52pt tall, radius 26, with a leading plus, the
   "Plan, ask, build…" placeholder, and a **new trailing mic button**. Wire the mic to open
   the new-session sheet with the composer focused — do not ship a dead control.
7. **New state.** `GroupMode.host` (only offered when more than one host is configured;
   sessions with no host go to a trailing "Unknown host" bucket) and `SortMode`
   (`recentActivity` default, `name` = case-insensitive title ascending). Sort applies
   within each group, never across groups.
8. **Preserve everything in spec §2.** The design mock had no agent nesting, no
   "Load more", no connection banner, no empty state, no offline dimming — because its
   mock data had none of those conditions. Their absence from the design is **not** a
   removal instruction. All of it must still work and still be reachable.

## Verification (run these; report the output)

```bash
cd ios/LFGCore && swift test          # must be green
cd ios && xcodegen generate           # only if project.yml changed
```

For the app build, use FlowDeck (`flowdeck build`) — this repo forbids calling
`xcodebuild`/`xcrun`/`simctl` directly. If FlowDeck is unavailable in your sandbox, say so
in your report rather than falling back to raw Apple CLIs.

Do **not** attempt simulator/visual verification — Claude owns that half and will drive the
running app against the design.

## Definition of done

- [ ] Screens 29–34 implemented to the spec's geometry and colors.
- [ ] Status / Directory / **Host** grouping all render correct sections and counts.
- [ ] **Sort by Name** reorders within a group; Recent activity is the default and restores.
- [ ] Group collapse works in **all three** modes and renders the 54pt collapsed row.
- [ ] Search field appears inline below the header and filters.
- [ ] Composer bar matches, including the mic, and the mic does something real.
- [ ] Every item in spec §2 (preserved behavior) still functions.
- [ ] All a11y identifiers from spec §7 present — existing ones kept, new ones added.
- [ ] `swift test` green. Project builds.

## Report back

- Files changed (and why, if you touched anything outside the three named files).
- Verification command output, verbatim.
- Anything you could not do, or any place you deviated from the spec — **say so
  explicitly**; a silent deviation costs more than an admitted gap.
- Anything in the spec that turned out to be wrong or unbuildable as written.
