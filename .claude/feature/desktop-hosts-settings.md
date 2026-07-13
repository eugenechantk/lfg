# Desktop: Hosts settings pane

## Problem

The desktop client (`desktop/LFGSessions.swift`) polls every host in
`~/.config/lfg-desktop/hosts.json`, but there is no UI to see which hosts it is
polling or to manage them — the only way is hand-editing the JSON file. Eugene
flagged this gap on 2026-07-13.

## Target

A native macOS Settings scene (app menu → Settings…, ⌘,) with a "Hosts" pane:

1. **List configured hosts** in config order. Each row shows:
   - the configured URL,
   - resolved host name from `/api/info` when reachable (e.g. `eugenes-macbook-pro-2`),
   - a status indicator: green dot = reachable, red dot = unreachable, plus
     session count when reachable,
   - a "this Mac" badge for local hosts (reuse `HostState.isLocal`).
2. **Add host**: text field (placeholder `http://host:8766`) + Add button.
   Trim whitespace; reject empty/duplicate entries and strings `URL(string:)`
   can't parse or that lack a scheme+host. On add: persist + trigger refresh.
3. **Remove host**: per-row remove button. Persist + refresh. Removing the last
   host is allowed — existing `loadHosts()` seed behavior re-seeds
   `http://localhost:8766` (keep that behavior).
4. Footer text naming the backing file (`~/.config/lfg-desktop/hosts.json`) so
   the escape hatch stays discoverable.

## Architecture constraints

- Single file `desktop/LFGSessions.swift`, built by `desktop/build.sh` (swiftc,
  no Xcode project). Keep it single-file.
- Lift `@StateObject private var store = SessionStore()` out of `ContentView`
  into `LFGSessionsApp`, inject via `.environmentObject(store)` into both the
  `WindowGroup` and the new `Settings` scene, so the settings pane reads the
  SAME live `HostState`s the list uses (no separate probing).
- Add `Config.saveHosts(_ hosts: [String])` beside `loadHosts()`; settings
  edits go through it. After any change, kick `Task { await store.refresh() }`.
- `SessionStore.refresh()` already re-reads `Config.loadHosts()` each cycle, so
  no other plumbing is needed.
- Note: reachable hosts deduped by `hostId` (localhost + Tailscale IP of the
  same machine collapse into one `HostState`). The settings list must render
  from the CONFIG list (all URLs), joining live state by URL where available —
  not from `store.hosts` alone, else a deduped-away URL row would vanish.

## Success criteria

1. ⌘, opens a Settings window listing both currently configured hosts with
   correct status dots (localhost reachable; Air IP status matches reality).
2. Adding a valid host URL appends it to `hosts.json` (verify file content) and
   it appears in the list; a bogus string is rejected without writing.
3. Removing a host deletes it from `hosts.json` and the sessions list stops
   showing that host's sessions after refresh.
4. Main window behavior unchanged (list, toolbar, open-in-iTerm2).
5. Builds clean via `desktop/build.sh`.

## Verification evidence

`.claude/feature/evidence-desktop-hosts-settings/` — build log, screenshots of
the settings pane, hosts.json before/after add/remove.

## Status

- [x] Implemented (Codex, session 019f5aa6-2ff0-7a52-a11f-36d4075316cb, 2026-07-13)
- [x] Verified (Claude, 2026-07-13) — all five criteria pass. Live GUI run via
  axdriver: settings pane listed both hosts with correct status (localhost
  green/160 sessions/this-Mac badge; Air IP red, confirmed actually
  unreachable via curl); added `http://bogus-host-test:8766` → appeared in UI
  + hosts.json; `nonsense` rejected with validation message, no write;
  removed bogus host → hosts.json restored; main window unaffected
  (screenshot). Screenshots in `evidence-desktop-hosts-settings/`
  (settings-initial / settings-after-add / settings-invalid-rejected /
  main-window-after). New build installed to /Applications/lfg.app and
  relaunched.
