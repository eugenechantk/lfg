# Delegation Brief: New session as its own view — Phase B (the three floating sheets)

## Prerequisite

Phase A (`.codex/delegate/brief-new-session-view-A.md`) is landed and verified:
`NewSessionView` is a pushed full-screen view with the composer card and three
config chips that already set `activeSheet` and flip their chevron to blue
`chevron.up`. Phase B attaches the panels those chips open. **Read the Phase A
diff first** — reuse its palette and atoms, do not re-declare them.

## Goal

Implement artboards `24-new-session-view-directory-picker`,
`25-new-session-view-host-picker` and `26-new-session-view-model-picker-grouped`
as a single reusable floating-sheet component plus three content bodies.

## Read first (authoritative spec)

`/Users/eugenechan/dev/personal/lfg/.claude/new-session-view/component-breakdown.md`
— components **C6, C7, C8, D3, D4, D5, S2, S3, S4**, plus the "New state
required" section.

Design HTML: `ios/design/claude-design-20260731/LFG iOS Baseline.dc.html` —
artboard 24 at **line 1506**, 25 at **1604**, 26 at **1679**. Read all three;
they share the sheet chrome and differ only in body and top inset.
Rendered capture: `ios/design/claude-design-20260731/iter2-screens-23-26.png`.

## Scope

Build-order steps **2, 5, 6, 7** from the breakdown.

### C8 `FloatingSheet` — the shared container

**This is not a `.sheet`.** A system sheet cannot inset from the bottom or from
both sides. Build it as an overlay inside `NewSessionView`:

- Scrim `rgba(0,0,0,0.5)` filling the screen below the panel, tap-to-dismiss.
- Panel inset `6pt` left / right / bottom, corner radius `34`, clipped.
- iOS 26: `.glassEffect(.regular, in: .rect(cornerRadius: 34))`. Below 26: the
  gradient + material fallback per the breakdown. The translucent top edge
  letting the composer show through is **intended** — do not make it opaque.
- Presented with `.transition(.move(edge: .bottom))` and an interactive drag-down
  to dismiss.
- Opening a sheet must **dismiss the keyboard** (breakdown Risks) or the panel
  and keyboard fight for the bottom of the screen.

**Height is content-driven, not a fixed detent.** Panel height =
`min(contentHeight, screenHeight - 150)`, anchored to `bottom: 6`. The design's
three top insets (150 / 494 / 190) are the *result* of that rule with their
respective content, not values to hardcode. The host sheet in particular is short
because it has two rows and no search field.

### C7 `SheetHeader` (70pt) and C6 `SheetSearchField`

Exact metrics in the breakdown. The close (✕) and confirm (✓) circles are both
44×44. Confirm commits the current selection and dismisses; close dismisses
without committing. Selection is applied live as rows are tapped, so "confirm"
is really just dismiss-and-keep — but the ✕ must revert to the value the sheet
opened with.

### S2 Directory sheet

- Search field: "Search directories". Filters both sections by name and path.
- `RECENT` section — **new persisted state**. Add `recentDirs: [String]` to
  `AppSettings` (MRU, cap 5). Push the chosen `cwd` on successful session start.
  Hide the section entirely when empty.
- `ALL DIRECTORIES` — `store.repos`, plus the existing `Root` (`store.root`) and
  `Inbox` (`store.inbox`) entries that today's menu offers.
- Row (D3, 54pt): 18pt check gutter · name 17 · path 12 monospaced, truncating
  tail.
- Keep an affordance for today's "Add directory by path…" alert. The design does
  not draw one; put it at the end of `ALL DIRECTORIES` as a row rather than
  dropping the capability. Flag this in your report as an addition.

### S3 Host sheet

- No search field. Rows (D4, 58pt): 18pt check gutter · 8pt reachability dot ·
  name 17 + subtitle 13.
- Subtitle composed from `store.reachabilityByHost[host.id]` and `host.isDefault`:
  `"Reachable · Default"` / `"Reachable"` in `labelTertiary`, `"Unreachable"` in
  `#FF9F0A`.
- Renders even with one host configured (Phase A already shows the chip
  unconditionally).

### S4 Model sheet

- Search field: "Search models". Filters across all groups.
- Grouped by `AgentKind`: section header = `AgentKind.displayName` **uppercased**
  (`CLAUDE (CLI)`, `CODEX (CLI)`, `OPENCODE`), body = that kind's `models`.
  Header metrics differ slightly from the directory sheet: padding `11/16/6`.
- Row (D5, 44pt): 18pt check gutter · name 17.
- **Selecting a model sets the agent too** — this is the whole reason the agent
  picker was removed. Set `agent` to the `AgentKind` whose group the row came
  from, and `model` to the row's value. `AgentKind.aisdk` and `.codexAisdk` share
  model lists with `.claude` / `.codex`; decide whether to show all five groups
  or collapse the ai-sdk variants, and **say which you chose and why** in your
  report.

## Constraints

- Repo `/Users/eugenechan/dev/personal/lfg`, iOS client `ios/`. Read
  `ios/CLAUDE.md`.
- New UI in new files (e.g. `ios/LFG/NewSession/NewSessionSheets.swift`).
- **`recentDirs` persistence is non-UI state** → per `ios/CLAUDE.md` the MRU
  logic belongs in `LFGCore` **with a unit test** (`swift test` must pass). The
  `AppSettings` storage wiring stays in the app target.
- **Do not use `List`** inside the panel — an opaque `List` row background seams
  against the translucent sheet, which is exactly the artifact the design
  verifier flags. Use `ScrollView` + `LazyVStack` with clear backgrounds.
- `SessionListView.swift` / `RootView.swift`: do not touch in Phase B.
- Preserve `store.startOptimistic` behavior.

## Accessibility identifiers — required

`sheet.directory`, `sheet.host`, `sheet.model`, `sheet.close`, `sheet.confirm`,
`sheet.search`, and `sheet.row.<name>` on every row.

## Verification

```
cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test   # recentDirs MRU
cd /Users/eugenechan/dev/personal/lfg/ios && flowdeck build
```

Use `flowdeck` only — no direct `xcodebuild`/`xcrun`/`simctl`. Do not run the
simulator or drive UI; Claude owns live visual verification.

## Definition of done

- [ ] `swift test` passes (including a new MRU test).
- [ ] `flowdeck build` succeeds cleanly.
- [ ] Each chip opens its panel; ✕ reverts, ✓ commits, scrim tap and drag-down
      dismiss, keyboard dismisses on open.
- [ ] Panels size to content and inset 6pt on left/right/bottom with a 34pt
      radius and a translucent top edge.
- [ ] Directory sheet shows RECENT (populated after a start) + ALL DIRECTORIES
      with search; host sheet shows live reachability; model sheet is grouped by
      runtime and sets the agent implicitly.
- [ ] No `List` inside any panel.
- [ ] All Phase-B accessibility identifiers present.

## Report back

- Files created / modified.
- `swift test` + `flowdeck build` output tails.
- Your ai-sdk grouping decision and rationale.
- The "Add directory by path…" placement.
- Anything from the breakdown you could not honor natively.
