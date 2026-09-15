# Feature: ios-terminal

## User Story

As Eugene, away from home with only my iPhone, I want a real shell on the Pro inside the
lfg app, so I can run commands without Termius, Tailscale or WARP. The app already reaches
the Pro through the Cloudflare tunnel + Access.

## User Flow

1. Open lfg → session list header → tap the terminal button (`terminalButton`).
2. A full-screen terminal opens, connected to the default host (host menu if several).
3. Type with the keyboard; the SwiftTerm accessory bar supplies Esc / Ctrl / Tab / arrows.
4. Output streams live; rotating or resizing the view resizes the remote pty.
5. Close (or background the app) → the socket drops, the tmux shell `lfg-term-phone` keeps running.
6. Reopen → reconnects to the same shell, scrollback and running commands intact.

## Success Criteria

- [x] SC1: The server PTY bridge delivers keystrokes and output and never blocks the Bun
  event loop on macOS arm64. **Verify by:** `src/pty.test.ts` (echo round-trip + timer ticks
  keep firing during an idle pty + resize reaches the child), plus a live WebSocket probe
  against a scratch server.
- [x] SC2: `/api/term` requests that came through the tunnel (`cf-connecting-ip` present) are
  upgraded only with a valid Cloudflare Access JWT (RS256, JWKS-verified, matching iss/aud,
  unexpired). Local requests keep working unchanged. Unconfigured + tunnelled → 403.
  **Verify by:** `src/access-jwt.test.ts` (generated key pair: valid / bad signature /
  wrong aud / expired / missing / not configured / local bypass) + a live probe through
  `lfg-pro.eugenechantk.me` after deploy.
- [x] SC3: The iOS client builds the ws/wss terminal URL from the host base URL, with session,
  cols and rows, plus Access headers scoped to that origin; the resize control frame matches
  the server's format. **Verify by:** `LFGCoreTests/TerminalConnectionTests.swift`.
- [x] SC4: The session list shows a terminal button that opens a full-screen terminal, which
  connects, echoes a typed command's output and can be closed. **Verify by:** Simulator
  recording (iPhone 17 Pro) against a scratch server, via `ios_visual_evidence_auditor`.
- [x] SC5: Closing and reopening the terminal reattaches to the same tmux shell (earlier
  output still visible). **Verify by:** Simulator recording of close → reopen, plus
  `tmux ls` showing a single `lfg-term-phone`.
- [x] SC6: A dropped connection shows a visible "Disconnected — Reconnect" state instead of
  a frozen screen. **Verify by:** Simulator: kill the scratch server while the terminal is
  open → the banner appears; restart it → Reconnect restores the shell.

- [x] SC7: Typing feels instant. Keystroke → echo round trip through the real `/api/term`
  path is p50 ≤ 5 ms against a local server and p90 ≤ 20 ms, and in the app a typed character
  appears within ~2 frames (≤ 50 ms) of the key press on a local host. Through the Cloudflare
  tunnel the number is measured and reported (the network sets it, not the app).
  **Verify by:** `bun scripts/term-latency.ts <host> 200` (local now, tunnel after deploy) +
  a 60fps Simulator recording analysed frame by frame by `ios_visual_evidence_auditor`
  (key-press frame → glyph frame).

## Platform & Stack

- **Server:** Bun 1.3.14 / TypeScript (`src/pty.ts`, `src/commands/serve.ts`, new `src/access-jwt.ts`)
- **iOS:** Swift 6 strict concurrency, SwiftUI, SwiftTerm (new SPM dep), `URLSessionWebSocketTask`

## Steps to Verify

1. `bun test src/pty.test.ts src/access-jwt.test.ts`
2. `cd ios/LFGCore && swift test --filter TerminalConnection`
3. Scratch server from the worktree on a spare port → `bun wsprobe.ts ws://127.0.0.1:<port>/api/term?...`
4. `cd ios && xcodegen generate` → FlowDeck build/run on iPhone 17 Pro, host = scratch server
5. After Eugene OKs the deploy: restart the real server → probe wss through the tunnel.

## Implementation Phases

### Phase 1: Server PTY fix (SC1)
### Phase 2: Access JWT gate on /api/term (SC2)
### Phase 3: LFGCore terminal connection (SC3)
### Phase 4: iOS Terminal screen + entry point (SC4–SC6)

## Decision Log

- **Rebuilt `PtyBridge` on `Bun.spawn({ terminal })` rather than patching the FFI.** Root
  cause found while probing: `fcntl`/`ioctl` are variadic, and Bun FFI passes variadic
  args in registers, while Apple arm64 expects them on the stack. So `F_SETFL O_NONBLOCK`
  silently never applied (probe: flags stayed `2`), the drain loop's `read()` blocked the
  single event loop, keystrokes never reached tmux, and the "Terminal tab stalls HTTP 20s+"
  hazard in `.claude/CLAUDE.md` follows from it. Resize (TIOCSWINSZ via ioctl) was broken
  the same way. Bun 1.3.14's native terminal option was probed: echo round-trip OK, resize
  reached tmux, timers kept firing.
- **The terminal is its own tmux session (`lfg-term-phone`), never an agent pane.** Attaching
  to agent panes resizes them, which breaks prompt capture (see the pane-size hazard in
  CLAUDE.md). Attaching to an agent pane is out of scope.
- **The Access gate fails closed for tunnelled requests.** If `LFG_ACCESS_TEAM_DOMAIN` /
  `LFG_ACCESS_AUD` are unset, a tunnelled `/api/term` gets 403. A misconfiguration must never
  become a public shell. Values come from `.env` (team `morning-darkness-07e8`, aud from the
  lfg-pro Access app, read from a live `CF_Authorization` JWT).
- **Kept SwiftTerm's built-in iOS input accessory** (esc/ctrl/tab/arrows) instead of building
  a custom key bar: it already exists, is maintained, and handles sticky Ctrl.
- **SwiftTerm pinned to exactly 1.11.2.** 1.20.0 failed on "Validate plug-in
  SwiftTermBuildInfoPlugin" (untrusted build plugin, added in 1.19). 1.18.0 failed on "missing
  Metal Toolchain" (GPU renderer, added in 1.12). Both would also break unattended Fastlane
  archives. 1.11.2 builds clean with the CoreText renderer.
- **Latency is measured with a script, not judged by eye.** `scripts/term-latency.ts` types
  into `cat` so each keystroke's echo is isolated from prompt redraws.
- **Server event-loop stalls (~170 ms, ~2% of keystrokes) are left as a follow-up.** The bare
  bridge shows p99 3 ms, so the terminal path is not the cause. Periodic work elsewhere in
  `serve` (journal pump / session enumeration) blocks the loop, which existed before this
  feature. Worth a separate profiling pass.
- **Replaced the terminal's system toolbar with a plain header.** Close and the host menu
  weren't in the accessibility tree as toolbar items (FlowDeck: "Element not found:
  terminalCloseButton"), which also means VoiceOver couldn't reach them. This matches the
  session list's custom header.
- **Vendored SwiftTerm 1.11.2 with a one-method latency patch** (after audit #1 failed SC7b).
  The per-keystroke delay was internal to SwiftTerm (`feedFinish` → fixed 1/60s
  `asyncAfter`), with no public or overridable way around it. Chunks ≤256 bytes on the main
  thread now paint in the same run-loop turn; bigger chunks keep the throttle so full-screen
  repaints don't flicker. The alternative, a GitHub fork, is an outward action with its own
  upkeep. Diff and re-check recipe in `ios/Vendor/SwiftTerm/PATCHES.md`.
- **The ≤50ms in-app target can't be proven on the Simulator.** After the fix, the app's
  own part (key sent → frame drawn) is 18ms median. Of that, 8.6ms is waiting for the next
  60Hz frame, which a 120Hz iPhone halves. The Simulator's display and recording path adds a
  fixed cost on top that no app change touches. The on-device check is the real proof.
- **Disconnect banner shows "Connection lost"**, never the system error text, and sits above
  the terminal instead of over it. **Duplicate host names get "(host:port)"** in the title
  and host menu.
- **The worktree branches from `e72b400`.** Main has uncommitted iOS edits from other
  sessions, so new code goes in new files and edits to shared files stay small and additive.

## Verification Evidence

| SC | Command / action | Observed | Artifact |
|---|---|---|---|
| SC1 (red) | `bun test src/pty.test.ts` against the old FFI bridge | runner hung until killed (event loop blocked) | this session |
| SC1 (root cause) | `fcntl(F_SETFL, flags\|O_NONBLOCK)` via FFI, then `F_GETFL` | `before: 2, after: 2, nonblock: false` | scratchpad `nb.ts` |
| SC1 | `bun test src/pty.test.ts` after rewrite | 5 pass / 0 fail (echo, event-loop ticks, `stty size` = `41 132`, onExit, names) | — |
| SC1 (live) | ws probe → scratch server :8791 `/api/term`, HTTP `/api/info` while open | `OPEN`, `GOT LFG_42`, HTTP 200 in 0.001s | scratchpad `wsprobe.ts` |
| SC2 | `bun test src/access-jwt.test.ts` | 11 pass / 0 fail | — |
| SC2 (real JWT) | real `CF_Authorization` JWT from lfg-pro vs live JWKS | valid → ok; aud `x` → wrong audience; tampered sig → bad signature | scratchpad `realjwt.ts` |
| SC2 (server) | scratch server with env config: ws upgrade attempts | local → UPGRADED; tunnelled no JWT → REFUSED; forged → REFUSED; real JWT → UPGRADED; `/api/term/scan` no JWT → 403 | scratchpad `gateprobe.ts` |
| SC2 (tunnel) | live probe via lfg-pro after deploy | _pending deploy approval_ | — |
| tsc | `bunx tsc --noEmit` | 0 errors | — |
| SC3 | `LFG_TERM_TEST_URL=http://127.0.0.1:8791 swift test --filter TerminalConnectionTests` | 9 pass / 0 fail, including the live URLSession ws round trip (`SWIFT_42`) | — |
| build | `flowdeck build` (SwiftTerm 1.11.2) | BUILD succeeded, no warnings in new files | — |
| SC4 (self-check, not the audit) | sim: tap `terminalButton` → type `echo SIM_$((40+2))` + Enter | terminal connected to 127.0.0.1:9982, `SIM_42` printed, accessory bar visible | `.claude/evidence/s1.png`, `s2.png` |
| SC7 local | `bun scripts/term-latency.ts http://127.0.0.1:9982 200` (full lfg server) | p50 0.9 ms, p90 1.9 ms, **p99 173.5 ms**, max 194.3 ms | — |
| SC7 isolate | same probe → bare Bun ws server + the same `PtyBridge` | p50 0.7 ms, p90 1.5 ms, p99 3.3 ms, max 6.3 ms → the p99 spikes are lfg server event-loop stalls, not the terminal path | scratchpad `bare-term.ts` |
| regression | `swift test` (all LFGCore) | 472 tests, 0 failures, 1 skipped (live test without a server URL) | — |
| SC4–SC7 audit #1 | `ios_visual_evidence_auditor` | **PARTIAL**: SC4/5/6 PASS; SC7a PASS (p50 0.8ms); **SC7b FAIL** (in-app key-at-shell → glyph-on-screen median 67–71ms vs ≤50ms target); bugs: duplicate host labels, raw error text in a banner that covered output | `.claude/evidence/20260915-145604-ios-visual-audit/evidence.md` |
| SC7 fix: breakdown before | in-app `CACurrentMediaTime` probes (tx→rx→feed→upd→draw), 16 keys | tx→drawn median **33.3ms** = net 3.7 + main hop 4.4 + SwiftTerm fixed throttle 9.7 + wait for frame 10.0 + draw 5.6; the rest of the auditor's ~70ms is the Simulator's display/record pipeline | scratchpad `probe-before.log` |
| SC7 fix: after patch 1 | vendored SwiftTerm, immediate paint for chunks ≤256B, 20 keys | median **20.3ms** (throttle 0.0) | scratchpad `probe-after.log` |
| SC7 fix: after patch 2 | URLSession callbacks on the main queue, 24 keys | median **18.0ms** (hop 0.0, wait for frame 8.6, draw 2.6) | scratchpad `probe-after2.log` |
| vendored diff | `diff -rq` against upstream v1.11.2 `Sources/SwiftTerm` | only `Apple/AppleTerminalView.swift` differs (the documented patch) | `ios/Vendor/SwiftTerm/PATCHES.md` |
| fixes | `swift test --filter TerminalConnectionTests` (live, 9982) + full `swift test` | 11/11 pass; 474 tests, 0 failures | — |
| SC4–SC7 audit #2 | `ios_visual_evidence_auditor`, re-run | **PASS**. SC4/5/6 PASS. SC7a p50 0.7ms / p99 12.7ms. SC7b in-app key-at-shell → glyph median **53ms** (both runs), was 67/71ms, same method. Regression (seq 3000, ls, top, less): no flicker, tearing or stale rows across 5,265 frames. Fixes verified: banner text and position, host menu. **PARTIAL:** title suffix truncated off screen. | `.claude/evidence/20260915-152237-ios-visual-audit-2/evidence.md` |
| title fix | two-line title (label + host:port caption when names clash); `swift test --filter TerminalConnectionTests`; sim screenshot | 11 tests pass; title "Eugenes-MacBook-Pro" over "127.0.0.1:9982", fully visible (static proof, self-verified; no third full audit for a label change) | `.claude/evidence/s3-title.png` |
| deploy (Eugene approved restart) | copied the server changes into the main checkout (uncommitted; `serve.ts` hunk only; backup in scratchpad `main-backup-160500`), added `LFG_ACCESS_*` to `.env`, killed listener 1763 → serve-forever respawned 41409 | `/api/info` 200 local; 9 sessions, all with `tmuxTarget`; main checkout `tsc` 0 errors; pty + access-jwt tests 16 pass | — |
| SC2 (tunnel) | wss through lfg-pro with service token | `OPEN`, `GOT LFG_42`; no-credential request → 403 at the edge | scratchpad `wsprobe.ts` |
| SC2 (prod gate) | gate probe on :8766 | local UPGRADED; tunnelled no JWT REFUSED; forged REFUSED; real JWT UPGRADED; scan without JWT 403 | scratchpad `gateprobe-prod.ts` |
| SC7 (tunnel) | `bun scripts/term-latency.ts https://lfg-pro…` from this Mac | p50 516ms, but this Mac's client leg goes through Surfshark (edge trace 1.48s via VPN vs 0.15s on en0), so not representative | — |
| SC7 (tunnel, VPN bypassed) | raw ws client bound to en0 (`ws_en0_latency.py`), 2×100 keys | p50 **115 / 146 ms**, p90 269 / 287 ms, p99 870 / 445 ms; same-time localhost p50 1.2ms, p99 14.7ms → the tail is the Cloudflare hop | scratchpad `ws_en0_latency.py` |
| BUG2 found + fixed | sim: switch host in the menu → terminal stays blank; the server shows a client attached | `TerminalHostingView` kept the first controller's UIView; fixed with `.id(ObjectIdentifier(controller))` | `.claude/evidence/s5-tunnel.png` (bug) |
| app through tunnel | sim → host menu → lfg-pro → `echo TUNNEL_$((20+22)) from $(hostname -s)` | `TUNNEL_42 from Eugenes-MacBook-Pro`, using the app's real Keychain Access credential; the ✕ close icon renders | `.claude/evidence/s6-tunnel.png` |
| regression | `bun test <file>` for each of the 66 test files | all pass individually | — |
| regression (pre-existing) | `bun test` (whole suite, one process) | hangs until killed, **also on untouched base `e72b400`**, so not caused by this branch | — |

## Residual Risks / Follow-ups

- **Deployed server code is uncommitted in the main checkout**, alongside other sessions' dirty
  work. The branch still needs a commit and merge so the next checkout doesn't lose it.
- **The physical iPhone is not tested yet**: the app with the terminal isn't installed there
  (TestFlight or a direct install).
- On-screen (software) keyboard layout not verified; the Simulator uses a hardware keyboard.
- Nerd Font prompt glyphs render as boxed "?". Bundling a Nerd Font would fix it.
- While the disconnect banner shows, the tmux status line is clipped until Reconnect (cosmetic).
- Full-server event-loop stalls (earlier p99 ~107–173ms; 12.7ms in audit #2) are intermittent
  and pre-existing.
- Whole-suite `bun test` hangs on base `e72b400` too (pre-existing).
- Attaching the terminal to an agent's own pane is deliberately out of scope (pane geometry hazard).

## Bugs

- BUG2 (fixed): switching hosts left the previous host's terminal view on screen (blank, dead
  input) because the UIViewRepresentable kept its first UIView. Fixed with a per-controller `.id`.
- BUG1 (pre-existing, found 2026-09-15): the PTY never becomes non-blocking on arm64 macOS,
  so `/api/term` drops input and can freeze the server. Fixed in Phase 1.
