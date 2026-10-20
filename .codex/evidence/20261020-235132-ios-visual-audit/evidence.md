# iOS Visual Evidence Audit

Verdict: PASS

Timestamp: 2026-10-21 00:18 +0800

Repository: `/Users/eugenechan/dev/personal/lfg`

Simulator: iPhone 17 Pro (`cc-8bcc8476-visual-phone`, `0388A5A5-C4F9-49F1-AA76-4BAB286D0DD2`); iPad Pro 11-inch M5 (`cc-8bcc8476-visual-ipad`, `91FADD2B-FC25-4778-98B0-1622FB3222EF`)

App: `com.eugenechan.lfg`, scheme `LFG`, project `ios/LFG.xcodeproj`

## Change Audited

Native **Usage limits** destination in the session-list menu. The sheet compares Claude Code and Codex account quotas, preserves readings during refresh and failures, distinguishes unknown or API-billed limits, and adapts on iPhone and iPad.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| Usage limits is between Terminal and Settings | PASS | `03-iphone-menu-light.jpg`, `03-iphone-menu-light-tree.json` |
| Normal provider cards merge the same proven account across both hosts | PASS | `31-iphone-normal-ultimate-final.jpg`, `31-iphone-normal-ultimate-final-tree.json` |
| Refresh keeps prior values visible and disables the header action | PASS | `05-iphone-refreshing.jpg`, `05-iphone-refreshing-tree.json` |
| Stale, exhausted, critical, and failed-read states keep useful data and plain-language warnings | PASS | `32-iphone-error-controls-ultimate-final.jpg`, `32-iphone-error-controls-ultimate-final-tree.json` |
| A missing quota remains unknown and renders no bar | PASS | `23-iphone-weekly-final-standard.jpg`, `23-iphone-weekly-final-standard-tree.json` |
| API billing renders explanatory notices without quota bars | PASS | `10b-iphone-api-reset-light-settled.jpg`, `10-iphone-api-reset-light-tree.json` |
| An unidentified account stays separate and explains why | PASS | `11-iphone-unidentified-light.jpg`, `12-iphone-unidentified-scrolled.jpg` |
| Sheet scrolls, keeps its header available, and Close dismisses it | PASS | `08-iphone-scrolled.jpg`, `14-ipad-dismissed-tree.json` |
| True dark appearance renders the complete native sheet | PASS | `16-iphone-normal-dark-final.jpg`, `16-iphone-normal-dark-final-tree.json` |
| Accessibility XL scales and wraps body copy while bars remain readable; all content stays reachable by scrolling | PASS | `17-iphone-accessibility-xl-dark.jpg`, `18-iphone-accessibility-xl-scrolled.jpg`, `19-iphone-accessibility-xl-bottom.jpg` |
| iPad uses a fitted, centered form sheet over the split view; final error controls fit and remain readable | PASS | `13-ipad-normal-light.jpg`, `33-ipad-error-controls-ultimate-final.jpg`, `33-ipad-error-controls-ultimate-final-tree.json` |
| A real stopped fixture retains dated values, marks cards offline, dims them, and exposes recovery | PASS | `35-iphone-offline-retained-ultimate-final.jpg`, `35-iphone-offline-retained-ultimate-final-tree.json` |
| Try again remains hittable and clears the offline/error state after recovery | PASS | `36-retry-action.json`, `36-iphone-retry-recovered-ultimate-final.jpg`, `36-iphone-retry-recovered-ultimate-final-tree.json` |
| Complete list to menu to sheet to refresh to dismiss flow | PASS | `37-core-flow-refresh-retention-ultimate-final.mov`, `38-core-flow-dismissed-ultimate-final-tree.json` |

## Artifacts

- `03-iphone-menu-light.jpg`: real session-list menu order.
- `31-iphone-normal-ultimate-final.jpg`: final iPhone normal light state.
- `05-iphone-refreshing.jpg`: values retained while refresh is in flight.
- `32-iphone-error-controls-ultimate-final.jpg`: final stale/exhausted/error state with outlined notice and capsule retry control.
- `10b-iphone-api-reset-light-settled.jpg`: API billing and past-reset state.
- `12-iphone-unidentified-scrolled.jpg`: separate unidentified account and explanation.
- `13-ipad-normal-light.jpg`: iPad fitted form sheet; `33-ipad-error-controls-ultimate-final.jpg` ties the final error control to iPad runtime.
- `16-iphone-normal-dark-final.jpg`: true dark state after `set-appearance dark`.
- `17-iphone-accessibility-xl-dark.jpg` through `19-iphone-accessibility-xl-bottom.jpg`: enlarged text and scrolling.
- `23-iphone-weekly-final-standard.jpg`: corrected weekly-only state.
- `35-iphone-offline-retained-ultimate-final.jpg`: actual transport failure with retained, dimmed account cards and offline footer copy.
- `36-iphone-retry-recovered-ultimate-final.jpg`: actual Try again recovery.
- `37-core-flow-refresh-retention-ultimate-final.mov`: 20-second FlowDeck recording from session list through menu, sheet, slow refresh with values retained, and Close.
- Matching `*-tree.json` files contain accessibility semantics.
- `sim-navigate-*/*/trace.jsonl` and `replay.sh` preserve navigation evidence.

## Commands

- `flowdeck config get --json`
- `flowdeck simulator create ...` and `flowdeck simulator boot ...` for isolated iPhone and iPad simulators.
- `flowdeck run -w ios/LFG.xcodeproj -s LFG -S <udid> -d .codex/build/account-usage --launch-env='LFG_SESSION_UI_FIXTURE=1 ...' --json`
- `flowdeck ui simulator session start -S <udid> --json`
- `sim_navigate.py ... --goal 'In LFG, open the session list more menu, verify Usage limits is between Terminal and Settings, then choose Usage limits ...'` — reached the native sheet; initial run escalated only because Jev reported completion confidence `0.65`, while the final screen and screenshot contained the requested state. Replay: `sim-navigate-normal/20261020-235339-in-lfg-open-the-session-list-more-menu-v/replay.sh`.
- `sim_navigate.py ... --goal 'In LFG, open the session list more menu, choose Usage limits ...'` on iPad — DONE. Replay: `sim-navigate-ipad/20261020-235650-in-lfg-open-the-session-list-more-menu-c/replay.sh`.
- `flowdeck ui simulator set-appearance dark -S <iphone-udid> --json`
- `flowdeck run ... --launch-options='-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL' --json`
- `flowdeck ui simulator record -S <iphone-udid> --output 37-core-flow-refresh-retention-ultimate-final.mov --duration 20 --force --json`
- FlowDeck tap/swipe actions drove refresh, Close, and scrolling. One coordinate tap opened the visually identified ellipsis when the first FlowDeck tree omitted its identifier; subsequent AXe navigation resolved `sessions_more` directly.

## Notes

- All data came from the isolated read-only fixture on port 8991. No production host, task, database, or session was changed.
- The first file named `15-iphone-normal-dark-final.jpg` is light because an iOS launch argument did not alter simulator appearance. It is excluded from proof. `16-iphone-normal-dark-final.jpg` is the verified dark capture after FlowDeck changed the simulator appearance.
- The exact approved `usage-identity.dc.html` renders a provider heading inside each card iteration. The native repeated heading in multi-account states matches that rendered reference, despite a prose line that can be read as one heading per provider group.
- During the audit, source corrections removed an invented duration from a synthetic missing window, added the approved error outline and retry treatment, and correctly classified transport failures as offline. The final FlowDeck build succeeded after those reviews. The final runtime evidence uses that binary; unchanged earlier light/dark, Dynamic Type, and menu evidence is retained where the later changes did not affect the shown state.
- Stopping the isolated fixture first reproduced a real defect: numbers stayed visible, but cards were not marked offline. The corrected final binary now dims both cards, says `Fixture Air, Fixture Pro are offline`, keeps all four quota values, dates the reading, and recovers through Try again.
