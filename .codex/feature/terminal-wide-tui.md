# Feature: Wide terminal on iPhone

## User story

Desktop-oriented TUIs can render beyond the phone terminal's right edge. The user needs to read their full width without losing vertical tmux history scrolling.

The live `lfg-term-phone` tmux window was also pinned to `window-size manual` at 120 columns. That made Fit display only the left part of a fixed 120-column pane. The server now restores `window-size latest` before attaching, so the pane follows the phone PTY size.

## Flow and success criteria

1. Open Terminal in Fit mode, preserving the current phone-width shell.
2. Tap **Wide** to give the shell a 120-column grid. The PTY receives the new dimensions and the TUI redraws.
3. Drag left or right to view all columns. Vertical drags still scroll tmux history.
4. Tap **Fit** to return to the phone-width grid and its left edge.
5. Switching hosts retains the selected width mode.

## Verification

- FlowDeck build passed on the dedicated iPhone 17 Pro simulator.
- Simulator gesture evidence: `.codex/evidence/20260925-231118-ios-visual-audit/evidence.md`. Wide exposed the hidden chart, totals, and streaks; horizontal return, vertical history, Fit reset, and cross-host mode retention passed.
- A second 15-second recording, `.codex/evidence/20260925-231118-ios-visual-audit/connected-pan-verified.mov`, proves both horizontal directions while the terminal is connected. The first gesture recording's horizontal pan occurred after a connection loss and alone did not prove connected scrolling.
- `bun test src/pty.test.ts` passed. An isolated tmux test forced manual sizing, restored automatic sizing, then proved a 48-column PTY attach and a 120-column resize changed the tmux window to those widths.
- `tsc --noEmit` passed.

## Residual risks

- The user's specific third-party TUI may require more than 120 columns; this mode targets common desktop-width layouts.
- The long-lived production host has not been restarted. Its currently running process still uses the old attach behavior until the server is next deployed or restarted.
