# Delegation Brief: New session as its own view — Phase A (foundation + screen 23 + nav swap)

## Goal

Replace the lfg iOS client's modal "New session" **sheet** with a full-screen
**pushed view** matching the Claude Design artboard `23-new-session-view`, and
build the token/atom/composer foundation the three follow-up sheets (Phase B)
will sit on.

## Read first (authoritative spec — do not work from this brief alone)

`/Users/eugenechan/dev/personal/lfg/.claude/new-session-view/component-breakdown.md`

It carries the exact colors, type ramp, metrics, component table, a11y ids, build
order and risks. **Every literal value comes from there.** This brief only scopes
which parts of it Phase A covers.

The design HTML itself is at
`ios/design/claude-design-20260731/LFG iOS Baseline.dc.html`. Artboard 23 starts
at **line 1455**; read it — it is the ground truth for spacing and color, and it
is short. A rendered capture of all four artboards is at
`ios/design/claude-design-20260731/iter2-screens-23-26.png`.

## Scope — Phase A only

Build-order steps **1, 3, 4, 8** from the breakdown:

1. **Tokens + atoms** — palette, `FourPointStar` shape, `LFGSparkMark`,
   `SelectionCheck`, `SectionHeader`, `RowSeparator`.
   (Atoms A4/A6/A7 are unused until Phase B — build them anyway, they are the
   shared vocabulary.)
3. **Composer card (D2)** with `ConfigChip` (C3), `SendButton` (C4),
   `AttachButton` (C5).
4. **Screen 23** — `NewSessionView` shell, `NavRow` (C2), `CircularBackButton`
   (C1), `EmptyDraftState` (D1).
8. **Navigation swap** — sheet → push.

**OUT of scope for Phase A** (Phase B): `FloatingSheet` (C8), `SheetHeader` (C7),
`SheetSearchField` (C6), the Directory/Host/Model sheets (S2/S3/S4), `recentDirs`
persistence, `DirectoryRow`/`HostRow`/`ModelRow` (D3/D4/D5).

**Chips in Phase A are non-functional placeholders**: they render exactly as
designed (label + chevron, correct fonts/colors) and read their label from
existing state, but tapping them does nothing yet. Wire a
`@State private var activeSheet: ActiveSheet?` enum now (`case directory, host,
model`) and have the chips set it — Phase B attaches the panels. The chevron
must already flip to `chevron.up` in `#0A84FF` when `activeSheet` matches that
chip, so Phase B is purely additive.

## Constraints

- **Repo:** `/Users/eugenechan/dev/personal/lfg`. iOS client is `ios/`.
- **Read `ios/CLAUDE.md` before editing** — it is the house rulebook for this
  target (Swift 6 strict concurrency, `SessionStore` is the single source of
  truth, non-UI logic goes in `LFGCore` with a test, lenient decoding).
- **`ios/project.yml` is the source of truth, not `LFG.xcodeproj`.** New files
  under `ios/LFG/` are picked up by the existing glob — but if you add a
  directory, run `cd ios && xcodegen generate`.
- **Put new UI in NEW files.** `ios/LFG/SessionListView.swift` and
  `ios/LFG/RootView.swift` are being edited by a concurrent agent session right
  now. Touch them **only** for the entry-point swap, keep those edits minimal and
  additive, and re-read them immediately before editing.
- Suggested new files: `ios/LFG/NewSession/NewSessionTheme.swift`,
  `NewSessionAtoms.swift`, `NewSessionComposer.swift`. Rewrite
  `ios/LFG/NewSessionView.swift` in place.
- **Do not** change `LFGCore`. No API/model changes are needed in Phase A.
- **Do not** touch `MessageComposer.swift` — the design's composer differs enough
  (chip rows, bare `plus` instead of `paperclip`, different send colors, no
  bottom padding) that it gets its own view. Leave the existing one for
  `SessionDetailView`.
- Preserve the existing start behavior exactly: `store.startOptimistic(req, on:
  selectedHost, attachments:)` → `onCreated(placeholder)` → dismiss/pop. The
  optimistic-reconciliation path is load-bearing; do not restructure it.
- Dark mode is the design target. Do not add a light-mode variant.

## Spec — behavior

**Navigation (breakdown "Navigation model"):**

- `SessionListView`'s two entry points currently set `showNewSession = true`
  (lines ~383 and ~430), which drives a `.sheet` in `RootView` (~line 60).
- Compact width (iPhone): present via `.navigationDestination(isPresented:)` in
  the sidebar column so it is a real full-screen push with a working back
  gesture.
- Regular width (iPad): present the same view as `.fullScreenCover` — a push
  would confine it to the 300–460pt sidebar. Use
  `@Environment(\.horizontalSizeClass)` to choose.
- Remove the old `.sheet(isPresented: $showNewSession)` from `RootView`. Keep the
  `showNewSession` binding plumbing if that is the least invasive way to drive
  the new presentation.

**Agent selection is gone from the UI.** The design has no agent chip. Keep the
`agent` value in `NewSessionView`'s state (the create request still needs it) and
keep defaulting it to `.claude`; Phase B's model sheet will set it implicitly
from the chosen model's runtime group. Do not render an agent picker.

**Composer:**

- The card is pinned to the bottom safe area with **no extra bottom padding**.
  Attach with `.safeAreaInset(edge: .bottom)`.
- Send button: `#2C2C2E` fill + `rgba(255,255,255,0.85)` icon when the draft is
  empty; `#0A84FF` fill + white icon when non-empty. Disabled when empty.
- Attach button is a bare `plus` (`PhotosPicker`), 26pt, not a paperclip.
- Directory chip label = current `cwdLabel` logic. Host chip = selected host
  label + its reachability dot from `store.reachabilityByHost`. Model chip =
  current `model`. Host chip renders even with a single host (the design shows
  it unconditionally) — unlike today's `settings.hosts.count > 1` gate.

**Back button:** custom 38×38 circle. Hiding the system back button normally
kills the interactive pop gesture — see the breakdown's Risks section. Prefer
`.toolbar(.hidden, for: .navigationBar)` plus the custom `NavRow`, which keeps
the edge-swipe alive. Confirm the gesture still works.

## Accessibility identifiers — required

Apply the Phase-A subset from the breakdown's a11y table exactly (they are the
verification contract, not decoration): `newSession.root`, `newSession.back`,
`newSession.title`, `newSession.emptyState`, `newSession.composer`,
`newSession.chip.directory`, `newSession.chip.host`, `newSession.chip.model`,
`newSession.attach`, `newSession.send`, `newSession.input`.

## Verification (run these — they are the definition of "builds")

```
cd /Users/eugenechan/dev/personal/lfg/ios
xcodegen generate          # only if you added a new directory
flowdeck build             # MUST succeed with no errors and no new warnings
```

Use **`flowdeck`** for anything Xcode-related — this repo forbids calling
`xcodebuild`/`xcrun`/`simctl`/`devicectl` directly (see `ios/CLAUDE.md`).
`flowdeck --help` and `flowdeck build --help` document the flags.

Do **not** attempt simulator runs, installs, or UI automation — Claude owns the
live visual verification against the design and will do it after your run.

## Definition of done

- [ ] `flowdeck build` succeeds cleanly.
- [ ] Tapping the new-session entry in the session list **pushes** a full-screen
      "New session" view (iPhone) — no sheet, no Cancel button.
- [ ] The screen renders: circular back chevron left, centred "New session"
      title, spark-mark empty state, bottom-pinned composer card with directory
      + host chips above the input and plus / model chip / send below.
- [ ] All literal colors, sizes and spacings match the breakdown's token tables
      and the screen-23 metrics block.
- [ ] Chips set `activeSheet` and flip their chevron to blue `chevron.up`; no
      panel is presented yet.
- [ ] Send still creates the session through `store.startOptimistic` and
      navigates to it.
- [ ] The interactive back-swipe still pops the view.
- [ ] All Phase-A accessibility identifiers present.
- [ ] `RootView.swift` / `SessionListView.swift` diffs are minimal and additive.
- [ ] No changes under `ios/LFGCore/`.

## Report back

- Files created / modified (paths).
- Full `flowdeck build` output tail proving success.
- Any breakdown value you could not honor natively, and what you did instead.
- Anything left incomplete.
