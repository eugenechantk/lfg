# Vendored SwiftTerm

- Upstream: https://github.com/migueldeicaza/SwiftTerm
- Version: **v1.11.2** (`b1262db5b6bea699a8260a8c66999436c508ca56`), MIT (see `LICENSE`)
- Kept: `Sources/SwiftTerm` (library target only). Removed: fuzzers, termcast, tests, benchmarks.

Why vendored, not an SPM URL dependency: the latency patch below changes an internal method
that can't be overridden from outside the module. Why 1.11.x: 1.12 added a Metal renderer,
which needs Xcode's separately downloaded Metal Toolchain, and 1.19 added a build-tool plugin
that needs manual trust. Both break unattended archives.

To check that the vendored copy is upstream plus only these patches:

```
git clone https://github.com/migueldeicaza/SwiftTerm /tmp/st && git -C /tmp/st checkout v1.11.2
diff -ru /tmp/st/Sources/SwiftTerm ios/Vendor/SwiftTerm/Sources/SwiftTerm
```

## Patches

### 1. Paint small output chunks immediately (`Apple/AppleTerminalView.swift`)

`feedFinish()` always called `queuePendingDisplay()`, which waits a fixed 1/60 s before
`setNeedsDisplay`. Every typed character's echo is its own small chunk, so each keystroke
paid that delay plus the next-frame wait. Now a chunk of ≤ 256 bytes fed on the main thread
calls `updateDisplay()` directly. Larger chunks keep the throttle, so multi-read full-screen
repaints still coalesce.

Measured in the lfg Simulator (in-app `CACurrentMediaTime` probes, 16–24 keystrokes, local
server), key sent → frame drawn, median: **33.3 ms before, 20.3 ms after** (18.0 ms once
URLSession callbacks were also delivered on the main queue in `TerminalScreen.swift`).

### 2. Drags never send arrow keys (`iOS/iOSTerminalView.swift`)

`panSelectionHandler` turned a drag into ↑/↓/←/→ keystrokes whenever `allowMouseReporting`
was off (which the key bar's hand button toggles). A swipe meant to scroll recalled shell
history instead. The arrow branch is removed. lfg owns vertical drags and scrolls tmux history
through `/api/term` (`TerminalScreen.swift`, `src/term-scroll.ts`).

### 3. No mouse-reporting toggle in the key bar (`iOS/iOSAccessoryView.swift`)

The hand button toggled `allowMouseReporting`. lfg sets it to `false` permanently: with tmux
`mouse on`, touches became tmux mouse events, and a swipe pasted a tmux buffer (lfg's queued
agent messages) into the shell. The button is still built, but it is no longer added to the bar.

### 4. The S2 key row (`iOS/iOSAccessoryView.swift`, `iOS/iOSTerminalView.swift`)

lfg's design (board `s2-terminal`) puts every extra key in one horizontally scrolling 50pt row:
esc, tab, ctrl, ⌥, ↑ ↓ ← →, | / ~, ⌘V and the keyboard switch, in 40×36pt keys (#3A3A3C,
8pt corners, 14pt monospaced semibold) on #1C1C1E with a 1px #2C2C2E top border. `setupUI`
and `layoutSubviews` are replaced; the function keys are no longer offered. ⌥ toggles
`TerminalView.metaModifier` (the next key is ESC-prefixed; the key un-latches on the
`metaModifierReset` notification), ⌘V calls `TerminalView.paste`, and a latched ctrl or ⌥
key turns white with black text. The keyboard key hides and shows the keyboard (board icon,
"Hide keyboard" / "Show keyboard") instead of swapping in SwiftTerm's alternate key panel:
hidden keeps the terminal first responder with an empty, clear `HiddenKeyboardView`, so the key
row stays on screen 34pt up as on the board (iOS 26 puts 16pt of keyboard backdrop above any
non-empty input view, so the view is the home-indicator inset minus 16). The row's top border is 0.5pt. The row is a `KeyRowScrollView` that delays key delivery and lets a drag cancel it, so a swipe that starts on a key scrolls the row instead of pressing the key.

### 5. CSS line height (`iOS/iOSTerminalView.swift`, `Apple/AppleTerminalView.swift`)

Board `s2-terminal` sets the output in 12pt (Wide: 10.5pt) monospace with `line-height: 1.45`.
SwiftTerm sizes a row as ascent + descent + leading and has no line-spacing option.
`TerminalView.lineHeightMultiple` (iOS only, nil by default) makes each row
`pointSize × multiple` tall; `drawTerminalContents` moves the baseline up by half the extra
height (CSS half-leading), and the caret is the text's ascent + descent tall at the same
inset instead of filling the row (`caretHeight()`, `caretContentInset()`).

