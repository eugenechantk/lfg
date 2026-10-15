# Keep the desktop switcher on one toolbar row

The Sessions and Tasks switcher must stay centered on the original top bar. Never move it into another row as the window narrows.

## Success criteria

- [x] Both destinations use one top bar at narrow and wide widths. Verify native window captures and control bounds.
- [x] The switcher remains centered within two points. Measure rendered segment bounds across 180–1200 points and responsive boundaries.
- [x] Navigation and toolbar actions remain accessible. Verify switching, task detail, Back, and search with native accessibility actions.
- [x] The signed build passes desktop checks and an independent visual audit.

## Decisions

This is product work. Use the macOS development and testing skills, the existing read-only fixture, and FlowDeck.

The earlier two-row layout does not meet the clarified request. Remove it. Inspect native toolbar spacing before adding custom window chrome.

Preserve the previously requested 180-point minimum. Below 500 points, move Search and Create into More and put task detail Back there too. Below 350 points, hide Minimize and Zoom. Below 280 points, use accessible icons for the two destinations. Restore the full controls while widening.

The optional question about the minimum width received no answer before implementation. The existing 180-point requirement remains the default.

Remove the default title toolbar item with SwiftUI's public `toolbar(removing: .title)` modifier. An empty navigation title still reserved 160 points and pushed the switcher away from center. Native toolbar placement works once the unused title space and crowded actions are removed.

Recreate only the picker when switching between icons and text. Native segments otherwise retain stale images beside the new text.

## Verification evidence

Both destination lists passed 25 widths from 180 through 1201 points. Sessions widened; Tasks narrowed. The maximum center error was 0.5 points, and every segment stayed inside the original 52-point toolbar. Evidence: `.codex/evidence/single-row-desktop-switcher/v4-sessions/measurements.json` and `v4-tasks/measurements.json`.

The task detail menu initially shifted the picker five points at 180. Matching the compact list menu fixed that. Final checks passed Sessions at four widths, Tasks at three widths, and task detail at six widths, including 180. Every final center error was at most 0.5 points. Evidence: `v5-sessions`, `v5-tasks`, and `v5-detail` in the same evidence directory.

At 180, task detail Back returned to the list. Task Search opened and focused its field. Evidence: `back-action.json`, `back-at-180.png`, and `search-at-180.json`. The icon segments expose Sessions and Tasks through native accessibility descriptions and help text.

The signed standalone build passed all 181 desktop checks. A harness rebuild initially raced with standalone resource generation; its resources now use a separate immutable copy.

The independent audit found a resize-direction failure: narrowing Sessions from 900 to 600 points retained the connection item's old 132-point width. Its visible content needed only 18 points. Widening produced the correct 44-point toolbar slot. The retained slot shifted the picker 6.5 points. The fix gives the connection item a distinct identity for each label mode and constrains its content to intrinsic width.

The corrected build passed the Sessions regression sequence 900→600→180→600 and a further 1200→900→700→699→600→500→350→180 sweep. Every state stayed in one row with at most 0.5 points of center error. Evidence: `v6-directions/measurements.json`. The corrected signed build still passes all 181 desktop checks.

The final independent audit passed 27 measurements per destination, including both resize directions from 180 through 1200 points. All 54 states stayed in the original toolbar row with no overlaps. Maximum center error was 0.5 points. The prior 900→600 regression no longer reproduced. Responsive boundaries, narrow searches, destination switching, task detail, and Back navigation passed. Evidence: `.codex/evidence/single-row-desktop-switcher/auditor-final/evidence.md`.

## Installation

Installed and launched the same signed build on Pro and Air. Both installed executables have SHA-256 `cd61137a186ee4d514d151cc012de16dc7b39b2d42b44b7a0c55a4dca7516019`. Both pass signature validation and all 181 desktop checks. Process inspection confirms both run the installed app. Each previous app is preserved under `~/Library/Application Support/lfg-desktop-backups/20261010-single-row-toolbar/lfg.app`.

Proof: `.codex/evidence/single-row-desktop-switcher/deployment/pro-verification.json` and `air-verification.json`. The source manifest matches the current compiled sources. Native visual verification used the isolated Pro harness; Air verification covers installation, signature, checks, and the running process. No commit or push was made.
