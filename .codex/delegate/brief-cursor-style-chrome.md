# Delegation Brief: Cursor-style chrome (iOS Live Activity + session list toolbars)

**Repo:** `/Users/eugenechan/dev/personal/lfg`
**Full spec (READ THIS FIRST, it is the source of truth):** `.claude/feature/cursor-style-chrome.md`
**Design references (open these images):**
- `.claude/feature/live-activity-cursor-style/ref-live-activity.png`
- `.claude/feature/live-activity-cursor-style/ref-session-list.png`

## Goal

Restyle two iOS surfaces to match the reference designs: (1) the fleet lock-screen
Live Activity becomes a quiet, typographic card with two state layouts, and (2) the
session list gains a search + sort top toolbar and a pinned bottom "new session"
composer bar.

## Constraints

- **Read `.claude/CLAUDE.md` and `ios/CLAUDE.md` first** — they contain non-negotiable
  repo conventions and traps.
- **`ios/project.yml` is the source of truth, NOT `LFG.xcodeproj`.** Edit `project.yml`,
  then `cd ios && xcodegen generate`. Direct `.xcodeproj` edits get clobbered.
- **Do NOT touch:** `SessionStore.swift`, `SessionDetailView.swift`, `Components.swift`,
  `Models.swift`, `UnreadBadges.swift`, `ManualUnread.swift`, or anything under
  `src/` (the Bun server) — those carry another feature's in-flight work.
  The ONLY files you should change are:
  - `ios/LFGWidgets/LFGSessionActivityWidget.swift`
  - `ios/LFG/SessionListView.swift`
  - `ios/LFG/RootView.swift` (add `onOpenURL` only — leave everything else alone)
  - `ios/project.yml` (URL scheme only) + the regenerated `ios/LFG.xcodeproj`
- Swift 6, strict concurrency complete. Match the surrounding code's comment density —
  this codebase comments the *why* behind non-obvious decisions, not the *what*.
- Do not change the `LFGFleetAttributes` model, the server payload, or
  `FleetActivitySnapshot` — the widget already receives everything it needs
  (`rows[].title/host/state/since`, `working`, `needsInput`, `hosts`).
- Do not add new `GroupMode` cases — it already has exactly `.status` and `.directory`.
- Do not commit or push. Leave the working tree dirty for review.

## Spec

The feature doc has the full pixel-level spec (fonts, spacings, colors, layout anatomy
for both Live Activity states, the Dynamic Island treatment, the toolbar table, and the
bottom bar anatomy). Implement Phase 1 and Phase 2 as written there. Summary of the
shape so you know what you're building:

**Phase 1 — Live Activity** (`LFGSessionActivityWidget.swift`)
One card with two mutually exclusive layouts, chosen by `context.state.needsInput > 0`:
- *All working* → count-led list: a big count + the word "Active", then one plain
  `title … elapsed` row per session, then a `+N More` overflow line. No state dots, no
  host pills, no dividers, no app-mark glyph.
- *Any needs input* → attention layout: a small "Needs input" label, the blocked
  session's title as a 2-line headline, a `host · elapsed · N working` meta line, and a
  trailing "Reply" button that is a `Link` to `lfg://session/<sid>`.
Dynamic Island adopts the same typography in its expanded region; compact/minimal keep
their current dot + count behavior.

**Phase 1b — deep link**
Register the `lfg` URL scheme in `project.yml`'s LFG target `info.properties`
(`CFBundleURLTypes`), and handle it in `RootView` with `.onOpenURL`: parse
`lfg://session/<sid>` and call `store.openFromNotification(sid)` — that path already
defers the selection onto the next runloop turn, which is REQUIRED (setting the
NavigationSplitView selection synchronously during a view update crashes / renders
black; see `ios/CLAUDE.md`). Ignore any other URL shape.

**Phase 2 — session list chrome** (`SessionListView.swift`)
- Top bar: settings gear stays leading; the `+` button and the principal `StatusBadge`
  are removed; trailing gains a search toggle button and a sort `Menu` (a `Picker`
  bound to `settings.groupMode` inside the `Menu` gives the checkmark for free).
- The always-visible inline search field becomes toggle-revealed (animated, focused on
  reveal, cleared on hide). Filtering logic is unchanged.
- The segmented group-mode `Picker` is deleted (the sort menu replaces it).
- Both idioms get a large `Sessions` navigation title plus the existing
  `sidebarStatusSubtitle(statusSubtitle)` — iPhone previously had an empty inline title.
- A pinned bottom composer bar (`.safeAreaInset(edge: .bottom)` on the `List`): a `+`
  circle, the placeholder "Plan, ask, build…", the whole capsule one plain Button that
  sets `showNewSession = true`. Give it `.accessibilityIdentifier("newSessionBar")`.

## Verification (run these yourself before reporting back)

1. `cd /Users/eugenechan/dev/personal/lfg/ios/LFGCore && swift test` — must be green.
2. `cd /Users/eugenechan/dev/personal/lfg/ios && xcodegen generate` — must succeed after
   the `project.yml` change.
3. Build the app for a simulator. **Use FlowDeck (`flowdeck build ...`), not raw
   `xcodebuild`** — repo rule. Both the `LFG` app target and the `LFGWidgets` extension
   must compile clean (no warnings introduced).
4. Confirm via `git status` that only the four allowed files (+ the regenerated
   `.xcodeproj`) changed.

Screenshot/simulator verification is NOT your job — Claude runs the visual evidence pass
after you return. Get it compiling and correct-by-spec.

## Definition of done

- [ ] Live Activity renders both layouts per spec; no dots/pills/dividers/glyph remain
      in the lock-screen or expanded-island rows.
- [ ] `lfg://session/<sid>` scheme registered and handled via `store.openFromNotification`.
- [ ] Session list: search toggle + sort menu in the toolbar, `+` and principal badge
      gone, segmented picker gone, large title + status subtitle, pinned bottom bar
      presenting the New Session sheet.
- [ ] `swift test` green; `xcodegen generate` clean; app + widget extension build clean.
- [ ] No files outside the allowed set are modified.

## Report back

Files changed, the verification command output (swift test + build result), which parts
of the spec you deviated from and why, and anything you could not complete.
