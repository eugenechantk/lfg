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
