# iOS Visual Evidence Audit (re-audit 2)

Verdict: PASS (SC7b is borderline: 53 ms against a ~50 ms target, within one frame)
Timestamp: 2026-09-15 15:22–15:34 (local)
Repository: /Users/eugenechan/dev/personal/lfg/.worktrees/ios-terminal (feature/ios-terminal, vendored `ios/Vendor/SwiftTerm`)
Simulator: iPhone 17 Pro, iOS 26.3, E0DC8228-3248-4630-8929-FBC5DFC6AE6D (hardware keyboard)
App: com.eugenechan.lfg, new build pid 78301 (launched 07:22Z). Host: scratch server 127.0.0.1:9982
Previous audit: `../20260915-145604-ios-visual-audit/`

## Change Audited

1. SwiftTerm patch: small output chunks paint in the same run-loop turn, and URLSession callbacks arrive on the main queue.
2. Disconnect banner reads "Connection lost" and sits above the terminal.
3. Host title and menu show "(host:port)" when two hosts share a name.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC4 open / type / output / close | PASS | `sc4-sc5-open-type-close-reopen.mov`, `01-sc4-after-echo.png` (`REAUDIT_42`), `02-sc4-closed.png` |
| SC5 reopen reattaches to the same shell, one `lfg-term-phone` | PASS | `03-sc5-reopened.png` (earlier output intact), `sc5-tmux-ls.txt`. The session was detached after Close and attached again after reopen. Count = 1 (created 14:56:24, survived the whole audit) |
| SC6 banner, Reconnect, new command | PASS | `20-sc6-before-kill.png`, `21-sc6-banner.png`, `21-sc6-banner-tree.json`, `22-sc6-reconnected.png`, `23-sc6-command-after-reconnect.png` (`RECONNECT2_234`), `sc6-disconnect-reconnect.mov` |
| Fix: banner text and placement | PASS | `21-sc6-banner.png`: the banner says "Connection lost" with no system error text. It sits in its own row (y 126–155) and the terminal starts below it (TextArea y=171, was y=110). No output is covered |
| Fix: host menu disambiguation | PASS | `30-host-menu.png`, `30-host-menu-tree.json`: "Eugenes-MacBook-Pro (127.0.0.1:9982)", "Eugenes-MacBook-Pro (lfg-pro.eugenechantk.me)" (visually cut off as "lfg-pro.eugene…"), "Eugenes-MacBook-Air" |
| Fix: host title disambiguation | PARTIAL | The accessibility label is "Terminal · Eugenes-MacBook-Pro (127.0.0.1:9982)". On screen the title is cut to "Terminal · Eugenes-Mac…", so the new suffix is never visible on a 402 pt wide iPhone |
| SC7a script latency | PASS | `sc7a-term-latency.json`: p50 0.7, p90 1.8, p99 12.7, max 14.7 ms |
| SC7b in-app key to glyph | PASS, borderline (53 ms median) | `sc7b-typing-latency-run{1,2}.mov`, `frames/sc7b-analysis-run{1,2}.txt`, `frames/ticks-montage.png` |
| Regression: bulk output and TUIs | PASS | `regression-bulk-output-tui.mov`, `10`–`16-reg-*.png` + `frames/*-pane.txt`, `frames/reg-sheet-*.png`, `frames/regression-ink.json` |

## SC7b: same method as audit 1

- **Setup:** `keylog.py` ran in the terminal, and `flowdeck ui simulator type` sent one character every ~1.5 s (run 1) or ~1.3 s (run 2).
- **Recording:** 60 fps; the median frame interval was 16.7 ms.
- **Glyph frame:** the first frame where the terminal area changes (`frames2.py`, same thresholds as before).
- **Sync:** each run lines video time up with host time at the status-bar minute tick (`sync_latency.py`). Re-running `sync_latency.py` on audit 1's data reproduces 67 and 71 ms exactly, so the numbers compare directly.

| run | n | median | p90 | min | max | sd |
|---|---|---|---|---|---|---|
| audit 1, run 1 | 42 | 67 | 75 | 61 | 78 | 5.1 |
| audit 1, run 2 | 20 | 71 | 75 | 63 | 80 | 4.2 |
| **re-audit, run 1** | 42 | **53** | 57 | 47 | 60 | 3.1 |
| **re-audit, run 2** | 41 | **53** | 58 | 47 | 70 | 4.5 |

Samples: run 1 `frames/sc7b-analysis-run1.txt`, run 2 `frames/sc7b-analysis-run2.txt`.

**Delta:** −14 ms (vs 67) and −18 ms (vs 71), about 16 ms or one frame.

**Is the improvement beyond ±1 frame?** Only just, and not conclusively:

- Within a run, the spread is small (sd 3–5 ms), and all 4 runs move in the same direction. The new median (53) is below the old minimum (61).
- But each run is synced on a single clock-tick frame, which carries up to one frame (~17 ms) of timing error per run. Run-to-run offset error can therefore be as large as the delta.
- Conclusion: a ~1 frame improvement is likely real and consistent with the implementer's 33 → 18 ms in-app probe (−15 ms). It cannot be proven beyond the method's resolution.

The remaining ~50 ms is roughly 1 ms server plus 18 ms app (implementer's probe). The rest is consistent with Simulator display and recording latency, which this method cannot separate out.

## Regression check (large or fast output)

Recorded as one 80 s flow: `seq 1 3000`, `ls -la /usr/bin`, `top` (~7 s, `q`), `less /etc/services` (4 × space, `q`), `clear`. Timeline in `frames/regression-timeline.log`.

**Automated check (`flicker.py`):**
- Tracks the amount of visible text in the terminal area for every frame.
- Flags any frame where visible text drops below 50% and recovers within 3 frames.
- Result: **0 flagged frames** across 5,265 frames.
- The one real drop to blank was `top` clearing the screen before its first draw, which is a normal single transition.

**Frame-by-frame contact sheets (`frames/reg-sheet-*.png`):**
- **`seq`:** every frame during scrolling is a coherent full screen of consecutive numbers. No half-drawn frames or gaps.
- **`top`:** each refresh swaps the whole screen in one frame. Quitting restores the previous screen (`ls` listing + prompt) in one frame.
- **`less`:** each page-down is a single-frame whole-page swap, the `:` prompt stays on the last row, and quitting restores the prior screen in one frame.
- **Stale rows:** final screenshots match `tmux capture-pane` text (`frames/1x-reg-*-pane.txt`). No leftover rows after quitting `top`/`less` or after `clear`. The cursor sits on the prompt line.
- **Not the app:** changes at video t≈70 s (and banners at 7 s / 14 s) are system notification banners ("The agent finished its turn") sliding over the header.

## Artifacts

All paths are relative to this directory. Screenshots are numbered 00–30. Videos: `sc4-sc5-open-type-close-reopen.mov`, `sc6-disconnect-reconnect.mov`, `sc7b-typing-latency-run1.mov`, `sc7b-typing-latency-run2.mov`, `regression-bulk-output-tui.mov`. Analysis scripts and data are in `frames/`.

## Commands

- `flowdeck apps --json`
- `FLOWDECK_UI_SKIP_LOCK_CHECK=1 flowdeck ui simulator {tap terminalButton|Close|Host|Reconnect|ctrl, type, key 40, screen --output, record -t N -o} -S E0DC8228-3248-4630-8929-FBC5DFC6AE6D`
- `bun scripts/term-latency.ts http://127.0.0.1:9982 200`
- `kill $(lsof -nP -iTCP:9982 -sTCP:LISTEN -t)` + scratch-server restart with the provided env. It was running at the end (`/api/info` OK). Port 8766 was untouched.
- ffmpeg/ffprobe + `uv run --with numpy` for frame analysis

## Notes

- **Title suffix is invisible on iPhone width.** "(127.0.0.1:9982)" only exists in the accessibility label; the visible title is cut off. The host menu is the only place a user can tell the hosts apart. Repro: open the terminal on a host whose name is shared, then look at the header.
- **tmux status line hidden while disconnected.** While the banner is up, the terminal shrinks and the status line is cropped off the bottom (`21-sc6-banner.png`). It comes back after Reconnect. Cosmetic.
- **`terminalCloseButton` lookup by id failed once** ("Element not found") while a system notification banner covered the header. Tapping the "Close" label worked, and a later id tap resolved.
- **Not covered:** the software keyboard layout, because the Simulator has a hardware keyboard connected.
- **Audit-side input, not an app bug:** a leftover line from audit 1's keylogger session was sent when the first command was entered ("zsh: command not found: abcdef…" in `01-sc4-after-echo.png`).
