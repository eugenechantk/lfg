# iOS Visual Evidence Audit

Verdict: PARTIAL
Timestamp: 2026-09-15 14:56–15:10 (local)
Repository: /Users/eugenechan/dev/personal/lfg/.worktrees/ios-terminal (branch feature/ios-terminal)
Simulator: iPhone 17 Pro, iOS 26.3, E0DC8228-3248-4630-8929-FBC5DFC6AE6D (hardware keyboard connected, so the software keyboard stays off-screen)
App: com.eugenechan.lfg (scheme LFG, running build pid 25915, no rebuild)

## Change Audited

Full-screen Terminal screen (SwiftTerm over WebSocket to `/api/term`, attaching to tmux `lfg-term-phone`), opened from the session list's `terminalButton`. Host: scratch server `http://127.0.0.1:9982`. `lsof` confirmed the app's sockets went to :9982, not :8766.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC4: button opens terminal, prompt renders, `echo AUDIT_$((6*7))` gives `AUDIT_42`, accessory bar shows, Close returns to list | PASS (the accessory bar was only checked with a hardware keyboard) | `sc4-sc5-open-type-close-reopen.mov`, `frames/sc4-sc5-contact-sheet.png`, `01-sc4-after-echo.png`, `02-sc4-closed-session-list.png` |
| SC5: reopen reattaches to the same shell, `AUDIT_42` still visible, one `lfg-term-phone` | PASS | `03-sc5-reopened.png`, same video, `sc5-tmux-ls.txt`. I killed the old session before starting. The app created it at 14:56:24. It lost "(attached)" on Close and regained it on reopen. Count = 1 |
| SC6: stopping the server shows a Disconnected/Reconnect banner. After a restart, Reconnect restores the shell | PASS | `06-sc6-disconnected-banner.png`, `06-sc6-disconnected-tree.json`, `07-sc6-after-reconnect.png`, `08-sc6-new-command-after-reconnect.png` (`RECONNECT_123`), `sc6-disconnect-reconnect.mov`. The banner appeared about 130 ms after the kill (synced to the video's clock tick). The tmux shell survived the server restart |
| SC7a: script p50 ≤ 5 ms, p90 ≤ 20 ms | PASS (p99 spikes noted) | `sc7a-term-latency-run{1,2,3}.json` |
| SC7b: in-app key to glyph ≤ ~50 ms | FAIL as measured (about 67–71 ms median), within the method limits below | `sc7b-typing-latency-keylog.mov`, `sc7b-typing-latency-run2.mov`, `frames/sc7b-analysis*.txt`, `frames/an2.json`, `frames/an3.json` |
| SC7c: no drops, dupes or flicker | PASS | 62/62 keystrokes each gave exactly 1 glyph-change frame. Each was a single frame with no partial repaint. Pane text matched the input exactly (`-/-/-/-/abcdef`) |

## Latency

**SC7a** (`bun scripts/term-latency.ts http://127.0.0.1:9982 200`, three runs):

| run | p50 | p90 | p99 | max |
|---|---|---|---|---|
| 1 | 0.8 ms | 2.3 ms | 131.3 ms | 172.7 ms |
| 2 | 0.8 ms | 2.4 ms | 120.8 ms | 126.1 ms |
| 3 | 0.7 ms | 2.3 ms | 106.7 ms | 141.7 ms |

**SC7b method.** In hardware-keyboard mode a keypress leaves no mark on screen, and SwiftTerm's accessory buttons showed no press highlight (checked by frame diff). So:

1. I ran a raw-mode key logger (`frames/keylog.py`) inside the terminal shell. It records the host time each byte reaches the pty.
2. I typed one character every ~1.5 s with `flowdeck ui simulator type`.
3. The recordings are HEVC at about 60 fps (median frame interval 16.7 ms). A frame diff over the terminal area found the frame where each glyph first appears.
4. I synced video time to host time using the frame where the iOS status-bar clock turns over a minute (the simulator clock is the host clock).

Each sample is the glyph frame time minus the pty receive time.

- Run 1, 42 samples (ms): 69 76 64 74 76 78 68 65 63 64 62 64 66 71 73 76 74 62 62 77 65 74 63 74 66 65 71 67 64 62 71 61 64 70 71 62 64 67 75 61 73 69 → **median 67**, p90 75, range 61–78, sd 5.1
- Run 2, 20 samples (ms): 80 71 73 68 71 79 66 69 72 73 75 70 69 67 72 63 67 74 73 66 → **median 71**, range 63–80

**Limits of the method:**

- Frame resolution is ±17 ms.
- The absolute value depends on when SpringBoard redraws the minute. Recorder delay cancels out, but a late clock redraw would make the true latency higher, not lower.
- The number leaves out iOS key handling and the WebSocket send. It starts when the key reaches the pty.
- This is the Simulator, not a device.
- Two independent syncs agreed (67 vs 71 ms), and the ~17 ms spread is about one frame. So a steady ~65–70 ms is solid; exactly 50 vs 70 ms is not provable.

The server round trip is about 1 ms, so roughly 3–4 frames are spent on the iOS side (receive → SwiftTerm feed → draw → composite).

## Artifacts

All paths are relative to this directory. Screenshots are 01–08 `.png`. The four `.mov` recordings are listed above. The `frames/` folder holds the extracted frames, analysis scripts and data.

## Commands

- `flowdeck config get --json`, `flowdeck apps --json`
- `FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator session start -S E0DC8228-… --json`
- `… ui simulator tap terminalButton | Close | Host | "Dismiss context menu" | ctrl | Reconnect -S E0DC8228-…`
- `… ui simulator type 'echo AUDIT_$((6*7))'`, `… key 40`, `… screen --output …`, `… record -t 40/60/75/90 -o …`
- `bun scripts/term-latency.ts http://127.0.0.1:9982 200` ×3
- `kill $(lsof -nP -iTCP:9982 -sTCP:LISTEN -t)`, then the scratch server was restarted with the provided env. At the end it answered `/api/info` and :8766 was untouched.
- Frame analysis: ffprobe/ffmpeg + numpy (`uv run --with numpy`)

## Notes / bugs

1. **In-app echo about 67–71 ms** (SC7b above target). Repro: open the terminal on the local host, run the key logger, type single characters, then compare the pty receive time with the glyph frame.
2. **Script p99 is 107–131 ms** (max 173 ms) on every run. This matches the implementer's known event-loop stall follow-up. About 1–2% of keystrokes will visibly hitch.
3. **Host menu has two identical "Eugenes-MacBook-Pro" entries** (`04-host-menu.png`). :9982 and :8766 both report the same hostName, so you can't tell which host you're on. The title also shows "Terminal · Eugenes-MacBook-Pro", while the implementer's earlier screenshot showed "127.0.0.1:9982".
4. **The Disconnected banner shows a raw, cut-off NSError** ("The operation couldn't be completed. Socket is not connected"). It also covers the top two prompt lines. It works, but it's unpolished.
5. **Accessibility identifiers are missing from FlowDeck's tree.** Only labels show. `wait terminalView` and `wait terminalDisconnectedBanner` timed out even though both were on screen. Taps by id did resolve (`terminalCloseButton`, `terminalReconnectButton`, `terminalHostMenu`).
6. **Legibility.** The monospace font is small (~50 columns), but readable. The long starship prompt wraps to 3 lines. Nerd-font/emoji prompt glyphs render as boxed "?" (the ⎈ / node / ☁️ icons). The tmux status line truncates the session name to `lfg-term-s`.
7. **Not verified:** the software-keyboard layout (whether the keyboard covers the prompt). The simulator has a hardware keyboard connected, and FlowDeck can't toggle that. With the hardware keyboard, the terminal area (y 110–838) ends right above the accessory bar, so the prompt is not covered.
