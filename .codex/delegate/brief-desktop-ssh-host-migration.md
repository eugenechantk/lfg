# Brief: Reconcile desktop hosts model onto `HostEntry {url, ssh}`

## Context
Working dir (git worktree): `/Users/eugenechan/dev/personal/lfg/.claude/worktrees/desktop-ssh-merge`
Single file to edit: `desktop/LFGSessions.swift` (single-file SwiftUI macOS app; no Xcode project).
Build/verify: `cd desktop && ./build.sh` (swiftc, `-parse-as-library`, target arm64 macOS). Must compile clean.

This is a merge-in-progress (staged, uncommitted) of a feature branch into `main`. Two sides
evolved the host model incompatibly and it currently **does not compile (12 errors)**:

- **main** shipped a hosts-settings editor UI (`HostsSettingsView`) built on a simple `[String]`
  host model (`configuredHosts: [String]`, `saveHosts(_:[String])`, `HostsFile { hosts: [String] }`).
- **the feature branch** upgraded the host model to rich objects: `Config.HostEntry { url: String; ssh: String? }`,
  `Config.loadHosts() -> [HostEntry]`, and `Config.sshTarget(for:)` — needed so a per-host SSH target can drive
  the new "SSH-attach to remote tmux" and "move session between hosts" features.

The merge kept the branch's `HostEntry` model AND main's `[String]` settings UI → type mismatches.

## Goal
Unify EVERYTHING on `Config.HostEntry`. The `[String]` host model must be fully removed from the
settings/editor path. After your change, `cd desktop && ./build.sh` compiles clean with zero errors.

## Required changes (all in `desktop/LFGSessions.swift`)

### 1. `Config` (around lines 159–230)
- Make `HostEntry` `Codable` (it's currently `Decodable, Equatable`). Add a custom `encode(to:)` that writes a
  **bare JSON string when `ssh == nil`**, and an object `{ "url": ..., "ssh": ... }` when `ssh` is set. This keeps
  `hosts.json` clean/backward-compatible and round-trips with the existing lenient `init(from:)` (string OR object).
- Make `HostsFile` `Codable` (currently `Decodable`). You may drop `SeedHostsFile` and seed with `[HostEntry]` instead.
- Change `saveHosts(_ hosts: [String])` → `saveHosts(_ hosts: [HostEntry])`, encoding `HostsFile(hosts: hosts)`.
- Keep `loadHosts() -> [HostEntry]` and `sshTarget(for:)` as-is.

### 2. `HostsSettingsView` (around lines 974–1150)
- `configuredHosts: [String]` → `[HostEntry]`.
- `HostRow` should carry the full `HostEntry` (keep `index` for identity); update `rows`, `settingsRow(for:)`,
  `addHost`, `removeHost`, `validate`, `persist` to the entry model.
- Host lookups that used `row.url` must use `row.entry.url` (e.g. `store.hosts.first { $0.url == row.entry.url }`,
  `store.duplicateHostsByURL[row.entry.url]`).
- **Fuller editor (this is the point of the migration):** the add-row currently has only a URL field. Add an
  **optional SSH field** (e.g. a second `TextField` "user@host (optional)") so a host can be saved WITH an ssh target.
  `addHost` builds `HostEntry(url:, ssh:)` from both fields (nil/empty ssh → `nil`). In each configured row, show the
  effective ssh target (use `Config.sshTarget(for: entry)` — it derives `NSUserName()@<host>` when ssh is absent) as
  secondary text, so the user can see what SSH-attach will use.
- `validate` dedupe check: `configuredHosts.contains { $0.url == url }`.
- `persist(_ hosts: [HostEntry])`.

### 3. `@main` / top-level-code error (line ~1641)
There's a `'main' attribute cannot be used in a module that contains top-level code` error on `LFGSessionsApp`.
This is likely a cascade from the type errors — re-check after fixing 1 & 2. If it persists, find the top-level
executable statement (suspect `MoveTestCLI`) and guard it so the file stays parse-as-library clean with `@main`.

## Constraints
- Touch ONLY `desktop/LFGSessions.swift`. Do not change server or iOS code.
- Preserve all existing behavior: lenient decode (string OR object), the seed-on-empty, status dots, dedupe,
  "this Mac" badge, remove button, validation messages, `configPath` footer.
- Do NOT alter the SSH-attach (`Opener`) or move (`MoveCoordinator`/`MoveTestCLI`) logic — only make the host
  MODEL they depend on consistent.

## Definition of done
`cd desktop && ./build.sh` prints `Built: .../lfg.app` with **zero swiftc errors**. Report the exact build output.
