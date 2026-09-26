# Cross-provider switch title status

## Goal

Make a cross-provider model switch visible after the session options menu closes.

## User story

When I switch a session from Claude to Codex, or from Codex to Claude, I can see which provider LFG is switching to in the session title bar until the request finishes.

## Behavior

- A cross-provider switch shows a spinner and `Switching to Codex…` or `Switching to Claude…` in the title bar activity line.
- The switch status takes precedence over the normal `Running`, moving-host, or working-directory subtitle while the request is active.
- A same-provider model change keeps the existing title-bar behavior.
- The More menu remains disabled during any model switch and keeps its existing `Switching model…` label.
- The title status clears on success and failure.

## Verification

- [x] Unit-test provider-specific copy and cross-provider gating.
- [x] Build the iOS app with FlowDeck.
- [x] Render the shared title component in Simulator with a held cross-provider switch state.
- [x] Independently audit the runtime visual result.

## Evidence

- `LFGCoreTests`: 796 passed, 1 intentionally skipped.
- FlowDeck Debug build: passed on iPhone 17 Pro simulator (`71442893-3249-4AE6-AE32-7E64D09AB374`).
- Independent visual audit: PASS; exact accessibility text `Switching to Codex…`, visible spinner, no overlap or truncation.
- Audit report: `.codex/evidence/20260926-121521-ios-visual-audit/evidence.md`.

The visual fixture uses the same `SessionTitleBarContent` component as the live session detail. It intentionally does not exercise backend handoff timing.
