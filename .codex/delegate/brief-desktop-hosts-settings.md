# Delegation Brief: desktop hosts settings pane

Goal: Add a native macOS Settings scene (⌘,) to the lfg desktop app so Eugene can see and manage which lfg hosts it polls, instead of hand-editing `~/.config/lfg-desktop/hosts.json`.

Full spec: `.claude/feature/desktop-hosts-settings.md` (read it first — it is the source of truth).

## Constraints

- All work in `desktop/LFGSessions.swift` (single file, ~970 lines) — keep it single-file. Built by `desktop/build.sh` (plain swiftc, no Xcode project). Do NOT create an Xcode project or new files besides evidence.
- Do not touch anything outside `desktop/`.
- macOS 26 target; the app already uses Liquid Glass toolbar APIs (`.buttonStyle(.glass)`), so modern SwiftUI is fine.
- Match the file's existing comment style: comments state constraints, not narration.
- Do NOT commit to git.

## Spec (condensed — details in the feature doc)

1. New `Settings` scene in `LFGSessionsApp` containing a `HostsSettingsView`.
2. Lift `@StateObject private var store = SessionStore()` from `ContentView` (line ~545) into `LFGSessionsApp`; inject via `.environmentObject` into both `WindowGroup { ContentView() }` and the `Settings` scene. `ContentView` switches to `@EnvironmentObject`.
3. `HostsSettingsView` renders from `Config.loadHosts()` (the config list, ALL urls) joined with live `store.hosts` state by URL — not from `store.hosts` alone, because reachable duplicates are deduped by hostId and a deduped-away URL must still show as a row.
   - Row: URL, resolved hostName when available, green/red status dot (reachable/unreachable; a URL with no matching HostState after dedupe counts as reachable-duplicate — show it as such, e.g. "duplicate of <hostName>"), session count, "this Mac" badge via `isLocal`.
   - Add: TextField placeholder `http://host:8766` + Add button. Trim; reject empty, duplicates, and strings without a parseable scheme+host. Persist then `Task { await store.refresh() }`.
   - Remove: per-row button. Persist + refresh. Removing the last host is allowed (loadHosts re-seeds localhost — keep that).
   - Footer `Text` naming `~/.config/lfg-desktop/hosts.json`.
4. Add `Config.saveHosts(_ hosts: [String])` writing the same `HostsFile` JSON shape.

## Verification (run these yourself)

- `cd desktop && ./build.sh` → builds clean, zero warnings introduced.
- Back up `~/.config/lfg-desktop/hosts.json` first; restore it when done.
- Launch the built app, open Settings (⌘,), and confirm: both configured hosts listed with status; add `http://bogus-host-test:8766` → appears in list AND in hosts.json; remove it → gone from both. Capture screenshots to `.claude/feature/evidence-desktop-hosts-settings/`.
- If GUI verification is impossible in your sandbox, still do the build + a file-level check of save/load, and say so explicitly in the report.

## Definition of done

- [ ] Settings scene opens via ⌘, and lists configured hosts with live status
- [ ] Add/remove persists to hosts.json and triggers a store refresh
- [ ] Invalid/duplicate input rejected without writing
- [ ] Main window behavior unchanged
- [ ] `desktop/build.sh` builds clean
- [ ] hosts.json restored to its original two-host content

## Report back

Files changed, verification output (build log tail, hosts.json before/after), screenshots taken, anything incomplete or unverified.
