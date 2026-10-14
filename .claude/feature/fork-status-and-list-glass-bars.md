# Feature: "Forking…" title status + transparent glass list bars

Tier: product (lfg ships to TestFlight). Platform: iOS (SwiftUI, iOS 26 Liquid Glass).

## User Story

1. As Eugene, when I fork a session from its ••• menu, I want the session's top
   status line to show a spinner and "Forking…" so I know the fork is in flight
   (today the only sign is a disabled menu item I can no longer see).
2. As Eugene, on the Sessions and Tasks lists I want the top bar and the bottom
   dock to be transparent, with rows scrolling behind both and a soft glass
   transition at each edge — the same treatment as the session view — instead of
   an opaque bottom strip and a hard line under the top bar.

## User Flow

1. Open a Claude or Codex session → ••• → "Fork session".
2. While the fork request runs, the title bar's second line reads "Forking…"
   with a spinner. When the fork lands, the app opens the new session.
3. "Continue in LFG" (the external-session notice) runs the same fork call and
   shows the same status.
4. On the Sessions list and the Tasks list, scroll: rows pass under the top
   controls and under the bottom dock. Both edges fade through glass; no opaque
   band and no hard border line.

## Success Criteria

- [x] SC1: The title bar shows a spinner and "Forking…" while a fork is in flight,
  and goes back to the normal line after it ends. — **Verify by:**
  `SessionTitleActivityTests` (precedence + label), and a simulator recording of
  ••• → Fork session against a real host showing the status.
- [x] SC2: A model switch still outranks forking; forking outranks "Moving host…"
  and "Running". — **Verify by:** `SessionTitleActivityTests` precedence table.
- [x] SC3: Sessions list — rows scroll VISIBLY behind the top controls and the
  bottom dock; the glass fade sits only at the screen edges (status bar / home
  indicator); no opaque bottom strip; no hard line under the top bar. — **Verify by:** simulator screenshots/recording, light and dark, iPhone 17 Pro.
- [x] SC4: Tasks list — same as SC3. — **Verify by:** simulator screenshots/recording.
- [x] SC5: The list edge treatment matches the session view's top fade (same glass,
  same ramp). — **Verify by:** side-by-side screenshots of list vs session view.
- [x] SC6: No regressions — dock tabs + create button work, search works, iPad
  sidebar dock stays inside the sidebar. — **Verify by:** independent visual audit
  (`ios_visual_evidence_auditor`), iPhone + iPad.

## Test Strategy

- Pure precedence for the title bar's activity line moves into `LFGCore`
  (`SessionTitleActivity`) with a table test — the one piece of logic here.
- Store tracking (`forkingSessionIds`) is a set insert/remove with `defer`;
  proven live in the simulator.
- Edge treatment is visual only → simulator evidence + independent audit.

## Tests

- `ios/LFGCore/Tests/LFGCoreTests/SessionTitleActivityTests.swift` — SC1, SC2.

## Implementation Details

- `LFGCore/SessionTitleActivity.swift` — one precedence for the title bar's
  activity line: model switch > forking > moving host > running.
- `SessionStore.forkingSessionIds` + `isForking(_:)` — `fork(_:)` inserts the
  source id and removes it in a `defer`. Both entry points (••• → Fork session,
  and "Continue in LFG") call `fork`, so both show the status.
- `SessionTitleBarContent` takes `activity: SessionTitleActivity?` instead of
  three flags. New accessibility id: `sessionForkingStatus`.
- `Theme.swift`: `TopChromeFade` became `ChromeFade(edge:)` (top or bottom).
  The ramp now holds full glass across the whole bar, then fades over a 36pt
  tail past the border; the scrim still darkens most at the screen edge.
- `listScrollChrome(footer:)` hides the system scroll edge effect and overlays
  `ListChromeFades`, which reads the list's own safe-area insets (status + nav
  bar on top; dock + home indicator below) and draws a `ChromeFade` on each edge.
- Session view: a bottom `ChromeFade` sits between the transcript and the
  composer. It reaches the screen edge but respects `.keyboard`, so it rides up
  with the composer.

## Decision Log

- **Lists use the session view's custom glass fade, not the system soft edge.**
  The Oct 10 work used `.scrollEdgeEffectStyle(.soft)`. The session view cannot
  use the system effect (its transcript is rotated 180°, which confuses the edge
  detector), so the only way to make all three surfaces match is the shared
  custom fade.
- **2026-10-15 (v6, current): custom fade, host line stays bare.** Eugene chose
  "no glass line, tune a custom fade". Lists hide the system effect and draw
  `ChromeFade` at both edges (`ListChromeFades`, insets read inside the dock's
  `safeAreaBar`); the session view draws the same curve. Curve shaped after
  Settings: ~0.9 strength at the screen edge, 0.78→0.6 across the bar row (content
  faintly visible behind the host line), 0.35 at the bar's border, out by +28pt
  (top) / +32pt (bottom). Evidence: `v6/edges-grid.png`, `v6/cmp-session.png`.
  Fade-profile numbers from v6 are NOT valid: the list barely scrolled during that
  recording, and identical swipes leave sampling gaps; judged by stills instead.
- **2026-10-15 (v5 finding): Apple's default edge effect darkens more when bare
  text sits in the bar.** Eugene: the black at top/bottom transitions too early
  and abruptly. UIKit probe: the list's scroll view uses `.soft`; `.automatic`
  measures the same. So the lists ARE Apple's default. But Apple's Settings renders
  a gentler ramp (dark-mode profile: Settings 76→238 over 96–124pt; ours ~20–40
  then a jump at ~130pt). Giving the host line its standard glass background
  (dropping `.sharedBackgroundVisibility(.hidden)`) made our list match Settings.
  Evidence: `v5/compare-default-vs-glass-host.png`, `v5/profile-*.txt`. Eugene declined
  the glass host line (v6); the experiment was reverted exactly.
- **2026-10-15 (v4, supersedes v3 below): lean on Apple's default.** Eugene: the
  top transition must sit lower (bar content was hard to read) and should use
  Apple's default. HIG Scroll views (2026-06-08): "Prefer the automatic scroll edge
  effect style"; `safeAreaBar` extends it under custom bars. Lists now use the
  system automatic effect (custom fade removed; dock stays in `safeAreaBar`). The
  session view's flipped transcript still breaks the system effect (re-tested: it
  blurred the whole viewport), so `ChromeFade` copies the system curve, measured
  from a list scroll recording; top and bottom tails match within a few points
  (`v4/profile-*.txt`). Evidence: `v4/`.
- **2026-10-15 correction from Eugene (v3, superseded):** content
  must flow VISIBLY behind the top bar and the dock/composer, and transition only at
  the edge of the screen. `ChromeFade(edge:height:)` now covers only the window's
  safe-area zone on that edge (status bar 62pt / home indicator 34pt on iPhone 17
  Pro); no bar-row blur, no tail past the bar. Session view: both fades are
  overlays on the transcript placed at the screen edges. Evidence: `v3/`.
- ~~**Ramp change applies to the session view too.**~~ (superseded) The old ramp thinned the glass
  across the bar row, so list rows read legibly through the "N hosts online"
  line (and transcript text through the session title). Holding full glass to
  the border and fading past it matches "transparent, with a transition at the
  border". Shared component, so both surfaces change together.
- ~~**Session view gets the bottom fade too.**~~ (kept, but now only at the home-indicator zone) Without it, transcript text ran fully
  legible below the composer to the screen edge, while both lists now fade there.
  "Consistent with the session view" reads as one edge treatment everywhere.
- **Fork status is store state, not view state.** The ••• menu's `forking` flag
  lived in a UIKit menu wrapper; "Continue in LFG" had its own. The store's set
  serves the title bar from either path.
- Measuring insets: a `GeometryReader` that ignores the safe area reports zero
  insets on iOS 26.3 (measured: `top=0.0 bottom=0.0`). The reader must keep the
  safe area (measured `top=116 bottom=86`), then the fades stretch back out.

- Context found at start: an earlier agent left uncommitted work (Oct 10,
  `.codex/feature/list-scroll-blur.md`) that moved the dock into a `safeAreaBar`
  and switched the lists to the system `.soft` scroll edge. It was never shipped
  (last TestFlight evidence predates it). I build on it rather than revert it.

## Residual Risks

- Verified on simulators (iPhone 17 Pro + iPad Pro 11", iOS 26.3). Shipped to
  TestFlight as 1.3.0 (202610141854), VALID + IN_BETA_TESTING. The screen-edge
  correction shipped as 202610150036 (same checks pass); not yet seen on a phone.
- The screen-edge correction (v3) was self-verified only (light/dark, both lists,
  session view, keyboard); no independent audit re-run. Dock and + code unchanged.
- The fork status was exercised against a stub host with a 6 s fork. A real Codex
  fork can take up to the server's 30 s bootstrap watch; the status simply stays
  up longer. Not exercised against a real host, to avoid forking real sessions.
- iOS < 26 keeps the old path (no fades; dock via `safeAreaInset`). Not run.
- This tree also holds the Oct 10 uncommitted list-bar work (`RootView`,
  `SessionListView`, `shared/ScheduledTasksView.swift`) that these changes build on.
  It should ship in the same commit as this feature.

## Verification Evidence

Evidence dir: `.claude/evidence/fork-status-and-list-glass-bars/`. Simulator: iPhone 17 Pro, iOS 26.3
(`cc-2dfc6941`). Stub host: `fixture.ts` on 127.0.0.1:8960 (48 sessions, 32 tasks, 30-message
transcripts, a 6 s `POST /api/sessions/fork`), alongside the real hosts.

### Self-verification (implementer)

| SC | Action | Result | Artifact |
| --- | --- | --- | --- |
| SC1, SC2 | `cd ios/LFGCore && swift test` | 644 XCTest + 271 Swift Testing pass; `SessionTitleActivity` 6/6 | terminal |
| SC1 | ••• → Fork session on fixture "Review 01" | Title line showed spinner + "Forking…" for the 6 s request; then opened "Forked review branch" with its normal path line. Fixture logged the POST. | `10-forking-status.png`, `11-after-fork.png`, `fork-status.mov` |
| SC3 | Scroll Sessions list, light + dark | Rows blur under the host line and under the dock; fade just past each border; no opaque strip | `sessions-scroll-light.mov`, `frames/top-grid.png`, `frames/bot-grid.png`, `cmp-v2.png` |
| SC4 | Scroll Tasks list, light + dark | Same edges as Sessions | `cmp-tasks.png` |
| SC5 | Session view, long transcript | Same top blur under the title; bottom fade behind the composer reaches the screen edge; with the keyboard open the fade rides above it | `19-session-view-bottom-fade.png`, `20-session-view-keyboard.png` |
| Before | Shipped build (HEAD) | Opaque strip behind the dock; rows legible through the top bar | `.codex/evidence/list-scroll-blur/before-sessions-scrolled.png` |

### Independent audit

- **Audit 1: FAIL** — `audit/evidence.md`. SC1, SC3, SC4 PASS; SC5 PARTIAL (B2);
  SC6 FAIL (B1). iPad: dock inside sidebar, sidebar edges, search, tabs, keyboard
  all PASS. iPhone keyboard unverified (software keyboard off in the sim).
- **Audit 2: PARTIAL → closed by implementer.** B1 and B2 fixed. SC1, SC3, SC4,
  SC5, SC6 PASS on iPhone and iPad (+ opens New session / New task 3/3, tabs,
  search). Bottom ramps now match numerically: list 756→788pt (dock top), session
  view ~686→720pt (composer top) — `audit/audit2/a2-50-fade-profiles.txt`. Only gap:
  keyboard with the new fade, because the sim's software keyboard would not show.
- **Keyboard (implementer, after audit 2):** the sim had latched "hardware keyboard
  present" after FlowDeck typing; a shutdown + relaunch of the session sim brought
  the software keyboard back. With it open, the composer and its fade sit above
  the keyboard and the bubble above the composer blurs into its top edge
  (`46-keyboard-pinned-fade.png`, `47-keyboard-pinned-fade-scrolled.png`).

## Bugs

- **B1 (audit 1, SC6 FAIL) — dock + button did nothing.** Fixed; audit 2 PASS.
  Its action never ran (temporary log: no `tapped` line); tab buttons in the same
  dock worked. The + label carried its own interactive glass; inside the list's
  `safeAreaBar` (the Oct 10 dock move) that glass took the touch. HEAD, where the
  dock was a TabView overlay, opened on first tap. Fix: glass wraps the Button
  (as on the tab pill) and the label gets `contentShape(Circle())`. After: log
  shows `tapped` → `showNewSession -> true`; New session and New task both open
  (`41-plus-after-fix.png`, `cmp-plus.png`).
- **B2 (audit 1, SC5 PARTIAL) — session view bottom fade ended ~16pt short.**
  Fixed; audit 2 PASS. Measured: composer top at y=718 (156pt above the
  screen bottom) but the fade was sized from `bottomChromeHeight` = 140. Fix: the
  fade is now a background of the composer, pinned to its top edge and offset up
  by `ChromeFade.tail`, so the ramp ends exactly at the composer's top whatever
  the measurement (`44-session-view-bottom-pinned.png`).
