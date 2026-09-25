# Feature: Wide terminal on iPhone

## User story

Desktop-oriented TUIs can render beyond the phone terminal's right edge. The user needs to read their full width without losing vertical tmux history scrolling.

## Flow and success criteria

1. Open Terminal in Fit mode, preserving the current phone-width shell.
2. Tap **Wide** to give the shell a 120-column grid. The PTY receives the new dimensions and the TUI redraws.
3. Drag left or right to view all columns. Vertical drags still scroll tmux history.
4. Tap **Fit** to return to the phone-width grid and its left edge.
5. Switching hosts retains the selected width mode.

## Verification

- Build the iOS app with FlowDeck.
- In Simulator, open Terminal, toggle Wide/Fit, and drag in both directions over a wide text fixture; record the interaction.
- Check that the active grid width and the server PTY dimensions match after each toggle.

## Residual risks

- The user's specific third-party TUI may require more than 120 columns; this mode targets common desktop-width layouts.
