# Feature: Desktop Host Names and Connection Status

## User Story

As a desktop client user, I want to give each configured host a friendly display name and see host connectivity in the title bar so I can identify machines and outages at a glance, consistently with iOS.

## User Flow

1. Open the desktop client's Settings window.
2. Edit a configured host's display name and commit the edit.
3. See the friendly name used anywhere the desktop client labels that host.
4. Return to the main window and see host connection status where the static “lfg” title was.
5. With one host, see Connected/Connecting/Offline plus the running count; with multiple hosts, see one named online/offline chip per host.

## Success Criteria

- [x] SC1: Existing string and object entries in `hosts.json` continue to load, and a friendly display name round-trips through persistence. — **Verify by:** desktop host-config CLI tests.
- [x] SC2: Settings exposes an editable display-name field for every configured host; blank input restores hostname/URL fallback behavior. — **Verify by:** desktop host-config CLI tests plus macOS accessibility/UI audit.
- [x] SC3: Session rows, move targets, unreachable-host copy, Settings details, and search use the custom display name immediately after save. — **Verify by:** desktop host-config CLI tests plus macOS accessibility/UI audit.
- [x] SC4: The main window replaces the static “lfg” title with an iOS-style status bar: aggregate state for one host and per-host chips for multiple hosts. — **Verify by:** desktop status-presentation CLI tests plus macOS accessibility/UI audit.
- [x] SC5: The desktop app builds successfully and existing desktop CLI tests still pass. — **Verify by:** `desktop/build.sh` and the built binary's test modes.

## Platform & Stack

- **Platform:** macOS 26
- **Language:** Swift
- **Key frameworks:** SwiftUI, AppKit
- **Packaging:** Single-file `swiftc` app bundle; no Xcode project

## Test Strategy

- Add deterministic command-line tests for backward-compatible config coding, label precedence, name normalization, and connection-status presentation.
- Add store-level propagation and temp-directory persistence assertions for save/reload, blank restore, search, move-target, session-item, and unreachable-host labels.
- Render single-host and multi-host status views into off-screen PNG artifacts so every connection state remains inspectable even when the login session is locked.
- Build the production app bundle.
- Use cursor-free macOS accessibility inspection and screenshots for the Settings edit surface and title-bar status rendering.

## Tests

- `desktop/LFGSessions.swift`
  - host-config CLI test mode: legacy decode, named decode/encode, blank-name normalization, display-label precedence.
  - status-presentation CLI test mode: connecting/connected/offline aggregation and per-host status labels.

## Implementation Phases

### Phase 1: Host display names

- Extend `Config.HostEntry` with a backward-compatible optional `displayName`.
- Add Settings editing and feed display names into `HostState`.
- Cover SC1–SC3.

### Phase 2: Connection status title bar

- Add deterministic desktop connection-presentation state.
- Replace the static title with the iOS-style status view.
- Cover SC4.

### Phase 3: Verification

- Run CLI tests, production build, and cursor-free UI audit.
- Cover SC5 and visually verify SC2–SC4.

## Decision Log

- Preserve the compact legacy string encoding when neither SSH nor a display name is set; emit an object only when extra metadata exists.
- Keep the centered Status/Directory picker in `.principal`; place connection status in the leading title/navigation area formerly occupied by “lfg”.
- Treat the initial unrefreshed host state as Connecting rather than Offline, matching iOS's tri-state semantics.
- Honor `LFG_DESKTOP_CONFIG_DIR` as an explicit automation-only config root so end-to-end Settings tests can safely mutate disposable state rather than the user's real `~/.config/lfg-desktop/hosts.json`.

## Verification Evidence

| Criterion | Command / action | Result | Evidence |
| --- | --- | --- | --- |
| SC1 | `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` | PASS — 24 assertions cover legacy string/object decode, SSH retention, isolated config-root selection, disk persistence/blank restore, immediate store propagation, live host labels, and connection-state semantics. | Command output: `{"ok":true,"tests":24}` |
| SC2 | Cursor-free Settings AX tree plus independent `--desktop-feature-test` rerun | PASS — two editable display-name fields and two save buttons have stable identifiers/nonzero frames; disk save/reload and blank fallback assertions pass. | `.codex/evidence/20260806-desktop-host-status/settings-tree.json`, `.codex/evidence/20260806-145747-desktop-final-audit/evidence.md` |
| SC3 | Independent `--desktop-feature-test` rerun | PASS — assertions cover saved-name propagation to session items, search, move targets, unreachable-host copy, and blank fallback before refresh. | `.codex/evidence/20260806-145747-desktop-final-audit/evidence.md` |
| SC4 | Live screenshot/tree plus independent `--status-snapshots` rerun | PASS — static title is replaced; four inspected fixtures cover Connected + running, Connecting, Offline, and multi-host connected/offline/middle-truncated states. | `.codex/evidence/20260806-desktop-host-status/main.png`, `.codex/evidence/20260806-145747-desktop-final-audit/status-snapshots/` |
| SC5 | `cd desktop && ./build.sh` followed by `--desktop-feature-test` and `--status-snapshots`; `--move-test` usage smoke | PASS — production app bundle built and signed; all 24 feature assertions passed; four PNGs rendered; the existing move-test hook still dispatches and returns its expected usage error/exit 1 without mutating a live session. | Terminal output and snapshot directory in this turn |

## Residual Risks

_None. Independent audit verdict: PASS._

## Bugs

_None yet._
