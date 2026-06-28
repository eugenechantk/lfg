# lfg — Native iOS / iPadOS client

A native SwiftUI client for the `lfg serve` backend, focused on the **Live
sessions** MVP (parity with the PWA's Live tab). See the full spec in
[`../.claude/ios-mvp-live-sessions-feature-doc.md`](../.claude/ios-mvp-live-sessions-feature-doc.md)
and verification evidence in
[`../.claude/ios-mvp-verification-report.md`](../.claude/ios-mvp-verification-report.md).

## Structure
- `project.yml` — XcodeGen source of truth (run `xcodegen generate`).
- `LFG/` — the SwiftUI app:
  - `LFGApp` / `AppSettings` — entry + persisted host/filter.
  - `SessionStore` — observable store reducing `/api/sessions` snapshots + the
    `/api/live/stream` SSE deltas (msg/prompt/busy/queue).
  - `RootView` — adaptive NavigationSplitView (iPhone stack / iPad rail+stage) +
    connection gating.
  - `SessionListView`, `SessionDetailView`, `NewSessionView`, `SettingsView`,
    `Components`, `Theme`.
- `LFGCore/` — SPM package: API `Models`, `SSEParser`, `LFGClient`, + unit tests.

## Build & run (FlowDeck)
```bash
cd ios && xcodegen generate
# from repo root:
flowdeck build
flowdeck run
```
Set the server URL in-app:
- **Simulator:** `http://127.0.0.1:8766` (simulators share the Mac's loopback).
- **Real device over Tailscale:** the host's MagicDNS https URL (tailnet-only).

## Tests
```bash
cd ios/LFGCore && swift test    # models + SSE parser (15 tests)
```

## Backend contract
The app is a pure client of `lfg serve` — it spawns no agents itself. On a
**macOS host**, CLI agent enumeration + the interactive prompt panel require the
`src/procinfo.ts` shim (shipped). On Linux it works unchanged.
