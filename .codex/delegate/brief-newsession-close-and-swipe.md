# Delegation Brief: new-session view — cross button + swipe-back

## Goal

In the new-session view:

1. The top-left circular button shows a **cross** (`xmark`) instead of a back chevron.
2. **Swipe from the left edge goes back**, which it currently does not.

## Working directory

`/Users/eugenechan/dev/personal/lfg` (main checkout, branch `main`). iOS only.

## Current state

- The button is `CircularBackButton` — `ios/LFG/NewSession/NewSessionAtoms.swift:98`. It
  draws `Image(systemName: "chevron.left")` at 14pt semibold in a 38pt glass circle, and is
  placed by the header at `NewSessionAtoms.swift:126`.
- Presentation differs by size class — `ios/LFG/NewSession/NewSessionPresentation.swift:14`:
  - **compact (iPhone)**: `.navigationDestination(isPresented:)` — a real navigation **push**
  - **regular (iPad)**: `.fullScreenCover` — a modal, with no pop to perform
- `ios/LFG/NewSessionView.swift:113` sets `.toolbar(.hidden, for: .navigationBar)`.

## Why the swipe is missing (do not "fix" this by re-showing the nav bar)

UIKit's `interactivePopGestureRecognizer` is wired to the navigation bar's back item. Hiding
the navigation bar — which this view does deliberately, because it draws its own header —
leaves that recognizer disabled, so the edge swipe does nothing. This is the standard
SwiftUI/UIKit interaction, not a bug in this view's layout.

Restore the gesture without restoring the bar. The usual approach is a tiny
`UIViewControllerRepresentable` (zero-size, in the background) that finds the enclosing
`UINavigationController` and makes its `interactivePopGestureRecognizer` fire again with a
hidden bar — e.g. by giving it a delegate whose `gestureRecognizerShouldBegin` returns true
when the stack can pop. Use whatever mechanism you judge most robust, but:

- It must only affect **this** view's navigation controller, not install global state that
  outlives the screen or leaks into other pushed screens.
- It must not be applied on the **regular/iPad** `fullScreenCover` path, where there is no
  navigation stack to pop — guard by size class or by the presence of a nav controller.
- It must not swallow or fight other gestures: the composer's text interaction, the
  scrollable content, and the sheets presented from this view (`activeSheet`) must all keep
  working. Left-edge only.
- Do not set a `UIGestureRecognizerDelegate` on a shared/system object without restoring it,
  and do not retain the navigation controller strongly in a way that creates a cycle.

## Spec

### 1 — Cross button

- Swap the glyph to `xmark`. Keep the 38pt glass circle, its
  `glassOrRaised(..., interactive: true)` treatment, and the existing sizing approach — only
  the symbol and its optical weight/size change. `xmark` reads heavier than `chevron.left` at
  the same point size, so pick a size/weight that looks balanced in the same circle rather
  than reusing 14pt semibold unexamined.
- Update the accessibility **label** to "Close" (it currently says "Back"), because the
  control now reads as dismissal.
- **Keep the accessibility identifier `newSession.back` unchanged.** It is referenced by
  `.claude/new-session-view/component-breakdown.md:246`; renaming it would desync that doc
  and any automation using it. Note the mismatch in your report rather than renaming.

### 2 — Swipe-back

Left-edge swipe pops the new-session view on iPhone, matching what the cross button does.

## Constraints

- Only files under `ios/`. Nothing in `src/`, `web/`, or `desktop/`.
- Do not restart the lfg server, kill tmux sessions, or `git push`.
- **Do not run or launch the app and do not start a `flowdeck ui simulator` session** — a
  simulator is in use for verification. Build only:
  `cd ios && flowdeck build -w LFG.xcodeproj -s LFG -S "0F95D0E2-5B76-40BF-8EC1-FD605E4CB71D"`
  If your sandbox blocks flowdeck's log writes, say so explicitly rather than reporting an
  unverified build.
- Match the surrounding comment style — the existing code documents *why* for non-obvious
  choices (see the sizing comment on the current button), and a gesture shim is exactly the
  kind of thing that needs its rationale recorded.

## Verification

1. `cd ios/LFGCore && swift test` — green (164 currently pass).
2. The build command above.
3. State clearly what you could not verify without running the app — the gesture in
   particular is not verifiable from a build alone.

Claude will verify on the simulator: that the button renders as a cross, that a left-edge
swipe dismisses the view, and that the composer, its sheets, and scrolling still work.

## Definition of done

- [ ] Top-left control is a cross, optically balanced in the existing circle
- [ ] Accessibility label reads "Close"; identifier `newSession.back` unchanged
- [ ] Left-edge swipe pops the view on iPhone
- [ ] iPad `fullScreenCover` path unaffected; no global/leaked gesture state
- [ ] Composer, sheets, and scrolling unaffected
- [ ] `swift test` green; app builds

## Report back

Files changed, how you restored the gesture and why that approach, what you could not verify
without running the app, and the identifier/label mismatch noted above.
