# lfg desktop

A minimal macOS app that lists every Claude Code / Codex session across all
configured `lfg serve` hosts and reopens any of them in iTerm2 with one click.

## What a click does

| Session | Action |
| --- | --- |
| On this Mac, has a tmux pane | New iTerm2 window attached to that tmux session (`tmux attach -t <name>`) |
| On another host with a tmux pane | New iTerm2 window attached over the host profile's SSH or Mosh transport |
| Closed Claude or Codex session | New iTerm2 window with a fresh local tmux session running the agent's native resume command in the session's cwd |
| Running without a tmux pane | Not openable; resuming would duplicate an already-running session |

Cross-host resume works when the agent's transcript directory
(`~/.claude/projects` or `~/.codex/sessions`) is synced between machines, so
the remote session's history is already on disk locally. Opened iTerm2 windows
are stretched to the full visible height of the display they open on.

## UI

- **Menu-bar quick access** — the status item opens a compact window with
  de-duplicated Needs Input, Running, and Recent sections. Needs Input comes
  from the server's live prompt state (not the separate Paused/error state).
  Rows use the same iTerm2 attach/resume path as the main window, and Open All
  Sessions reveals the single main app window. The panel shows up to four
  actionable/running rows and five recent rows, with full counts in each header;
  its search field filters every section using the same matching rules as the
  main window.
  Its monochrome template icon is generated from the canonical iOS logo at
  build time, so macOS supplies the correct menu-bar tint in light and dark mode.
- **Toolbar** (Liquid Glass, per the HIG toolbar groupings) — host connection
  status replaces the static title on the leading edge, the Status / Directory
  segmented control sits in the center area, and refresh + search sit on the
  trailing edge. A single host shows Connected/Connecting/Offline; multiple
  hosts get one named green/gray/orange status chip each.
- **Narrow windows** — the window resizes down to 440pt wide, so it can sit in
  a third of a 13" Air's screen. Under 760pt the toolbar switches to a compact
  form: the centered segmented control becomes an icon pull-down on the
  trailing edge (a centered item reserves twice the wider side's width, which a
  narrow window can't spare), and the search field becomes a toggle that
  reveals a search row under the toolbar. AppKit charges roughly 300pt of
  toolbar chrome before any item gets a point, so those swaps are what make 440
  reachable at all.
- **Host labels are dropped by measurement, not by breakpoint.** The labelled
  status cluster is measured off-screen (`DesktopConnectionStatusBar.labelledWidth`,
  cached per name set) and keeps its labels while they fit the leftover budget
  — short names like "Pro"/"Air" survive down to ~480pt, long ones give way to
  bare dots (names on hover) sooner. `ContentView.hostLabelsFit` is the pure
  decision and is covered by `--desktop-feature-test`.
- **Search** — filters on title, project, last user message, model, agent, host.
- **Status / Directory segments** — group like the iOS client: by status
  (Working / Paused / Idle) or by directory (collapsible sections, most
  recently active first, running/idle tallies; ambiguous leaf names get their
  parent directory prefixed).
- Auto-refreshes every 10 s; badge shows `tmux` (local attach), `mosh`/`ssh`
  (remote attach, whichever transport that row will use), or `resume` for a
  closed Claude/Codex session. A running process never receives a Resume badge.

## Hosts

`~/.config/lfg-desktop/hosts.json` (seeded with localhost on first run):

```json
{
  "hosts": [
    "http://localhost:8766",
    {
      "url": "https://lfg-air.eugenechantk.me",
      "ssh": "air",
      "displayName": "Air",
      "transport": "ssh"
    }
  ]
}
```

The Add Host field is prefilled with
`https://lfg-pro.eugenechantk.me`, and its SSH field with `pro`. Adding that
canonical endpoint gives it the friendly name `Pro` and forces plain SSH for
Cloudflare Access; existing host files are never rewritten automatically.

Each entry is one `lfg serve` machine. The
host whose URL is loopback — or whose reported hostname matches this machine —
is treated as local. Hosts reached twice (localhost plus a remote endpoint) are
deduped by `hostId`. Unreachable hosts are listed at the bottom of the window.
The optional `displayName` can be edited in Settings and overrides the reported
machine hostname everywhere the host is labeled. Leaving it blank restores the
hostname/URL fallback. Legacy string entries and objects containing only `url`
and `ssh` remain supported; their omitted `transport` defaults to `automatic`.

### Remote attach transport

Opening a session on another host uses **mosh** when `transport` is `automatic`
and `mosh` is on this machine's PATH, falling back to plain `ssh -t` when it
isn't. mosh survives IP
changes, sleep, and packet loss, so an attached window keeps working across
network roams instead of dying with its TCP stream. The `ssh` config field is
still the target either way; mosh uses ssh for the initial handshake, then UDP
60000–61000.

Set `"transport": "ssh"` for a Cloudflare Access SSH alias. The tunnel carries
the SSH stream, but not Mosh's post-bootstrap UDP connection, so these profiles
must never automatically switch to Mosh.

The corresponding aliases live in `~/.ssh/config`:

```sshconfig
Host pro
    HostName ssh-pro.eugenechantk.me
    User eugenechan
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h

Host air
    HostName ssh-air.eugenechantk.me
    User eugenechan
    ProxyCommand /opt/homebrew/bin/cloudflared access ssh --hostname %h
```

Cloudflare Access service tokens are stored per HTTPS origin in the macOS
Keychain, never in `hosts.json`. Import the same private JSON shape used by the
iOS build without printing the secret:

```sh
build/lfg.app/Contents/MacOS/lfg \
  --import-cloudflare-credential https://lfg-pro.eugenechantk.me \
  /path/to/BundledCloudflareAccess.private.json

build/lfg.app/Contents/MacOS/lfg \
  --cloudflare-credential-status https://lfg-pro.eugenechantk.me
```

The import reads only `clientID` and `clientSecret`; the explicit URL selects
the Keychain origin, allowing one account-level service token to authorize more
than one protected LFG hostname when their Access policies allow it.

Two things the previous Mosh shell aliases got wrong that the automatic
transport does not:

- `mosh host -- tmux attach` **fails** — mosh `exec`s its `--` argv with no
  shell in the loop, and sshd's non-interactive PATH is
  `/usr/bin:/bin:/usr/sbin:/sbin` with no Homebrew, so `tmux` is not found and
  the window dies instantly. The remote command is wrapped in an explicit
  `/bin/sh -c` with a PATH prefix.
- `--server` is passed as `PATH=… exec mosh-server` rather than a hardcoded
  `/opt/homebrew/bin/mosh-server`, so it also resolves on Intel Homebrew hosts
  (`/usr/local/bin`).

To see the exact command a row would run, without opening a window:

```
./build/lfg.app/Contents/MacOS/lfg --attach-command <ssh-target> <tmux-session>
```

## Build

```
./build.sh        # -> build/lfg.app
```

Single-file SwiftUI (`LFGSessions.swift`) compiled with `swiftc` — no Xcode
project. Targets macOS 26 (for the Liquid Glass toolbar APIs —
`ToolbarSpacer`, `DefaultToolbarItem(kind: .search)`). The app icon is converted from the iOS client's
`AppIcon.appiconset/AppIcon-1024.png`. The bundle is signed with the machine's
Developer ID identity when available (falls back to ad-hoc) so the macOS
automation permission for iTerm2 survives rebuilds; expect exactly one
"lfg wants to control iTerm" consent prompt after the signing identity changes.

For UI automation, set `LFG_DESKTOP_CONFIG_DIR` to a disposable directory. The
app will read and write `hosts.json` there instead of touching the user's real
`~/.config/lfg-desktop` configuration.

Headless verification hooks are built into the executable because this target
has no Xcode test bundle:

```sh
build/lfg.app/Contents/MacOS/lfg --desktop-feature-test
build/lfg.app/Contents/MacOS/lfg --status-snapshots /tmp/lfg-status-snapshots
build/lfg.app/Contents/MacOS/lfg --menu-bar-snapshot /tmp/lfg-menu-bar.png
build/lfg.app/Contents/MacOS/lfg --rename-test <sessionId> <hostURL> "<title>"
build/lfg.app/Contents/MacOS/lfg --window-fit 440 490 760 1000
build/lfg.app/Contents/MacOS/lfg --window-shot 440 /tmp/lfg-narrow.png [--search]
```

The second and third commands render inspectable status-bar and menu-bar-window
fixtures off-screen, so visual verification still works while the login session
is locked. The fourth drives the same `MoveCoordinator.rename` the row's
"Rename…" context menu calls, against a live host — an empty title clears the
override — because a locked login session can't be driven through the menu.

The last two cover window sizing. `--window-fit` builds the real window
off-screen at each width and reports whether every toolbar item is still
visible (exit 1 if any collapsed into the » overflow, or if the window refused
the requested width) — this is how the 440pt minimum and the 760pt compact
breakpoint were chosen. `--window-shot` draws that same window, chrome
included, into a PNG via `cacheDisplay`, so it needs neither Screen Recording
permission nor an awake display; AppKit-backed controls (the segmented picker,
the wide search field) come out as blank rounded rects in those shots, which is
a limitation of `cacheDisplay`, not a layout bug.
