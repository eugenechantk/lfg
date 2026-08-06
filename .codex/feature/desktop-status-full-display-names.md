# Feature: Full Desktop Status Display Names

## User Story

As a desktop client user, I want each host's configured display name shown in full in the status line so I can identify the machine without guessing from truncated text.

## User Flow

1. Configure multiple desktop hosts with display names.
2. Open the desktop client.
3. Read every complete display name in the leading status line.

## Success Criteria

- [x] SC1: Multi-host status chips preserve the full configured display name instead of applying the previous 120-point middle truncation. — **Verify by:** desktop feature CLI intrinsic-width regression assertion and an off-screen long-name snapshot.
- [x] SC2: The desktop app continues to build and all existing desktop feature assertions pass. — **Verify by:** `desktop/build.sh` and `--desktop-feature-test`.
- [x] SC3: The long-name status snapshot visibly contains the complete fixture name. — **Verify by:** independent macOS visual evidence audit of the generated PNG.

## Platform & Stack

- **Platform:** macOS 26
- **Language:** Swift
- **Key frameworks:** SwiftUI, AppKit
- **Packaging:** Single-file `swiftc` app bundle; no Xcode project

## Test Strategy

- Add a headless rendering assertion comparing a long-name status bar's intrinsic width with a short-name fixture; the long label must contribute its natural width.
- Update the multi-host visual fixture to provide enough canvas for the complete label.
- Rebuild, run all embedded desktop assertions, render status snapshots, and independently inspect the long-name result.

## Tests

- `desktop/LFGSessions.swift`
  - `--desktop-feature-test`: long multi-host display names materially increase the status bar's intrinsic width.
  - `--status-snapshots`: complete long display-name fixture.

## Implementation Details

- Removed the per-chip 120-point maximum width and middle truncation.
- Kept each display name on one line at its natural width.
- Added a 25th embedded desktop assertion that compares long- and short-name rendered widths.
- Renamed and widened the multi-host snapshot fixture to show the complete long name.

## Decision Log

- Prefer the configured display name's intrinsic width over a per-chip cap. The containing macOS toolbar can manage genuinely constrained windows, but the status view itself must not intentionally abbreviate user-defined identity.

## Verification Evidence

| Criterion | Command / action | Result | Evidence |
| --- | --- | --- | --- |
| SC1 | `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` | PASS — 25 assertions, including the long-name intrinsic-width regression. | Command output: `{"ok":true,"tests":25}` |
| SC2 | `cd desktop && ./build.sh` followed by `--desktop-feature-test` and `--status-snapshots` | PASS — production app built and signed; assertions passed; four PNG fixtures rendered. | Command output in this turn. |
| SC3 | Independent visual audit of a freshly rebuilt and rendered `multi-connected-offline-full-name.png` | PASS — `Extremely Long Creative Production Mac Studio Host` is visible in full on one line with no truncation. | `.codex/evidence/20260806-174336-ios-visual-audit/evidence.md` |
| SC1–SC3 installed-app check | Restarted `/Applications/lfg.app`, inspected its real AX window, and captured the live 760-point window | PASS — the installed toolbar visibly renders `Pro` and `Air` in full. The running process now starts from the installed fixed bundle. | `.codex/evidence/desktop-status-live-restart/after-restart.png` |

## Residual Risks

_None. Independent audit verdict: PASS._

## Bugs

- Resolved: the first install replaced the bundle but left the 17:30 pre-fix process running. Restarted the installed app at 17:48 and verified the live window. Future installs must quit and relaunch the app before visual acceptance.
