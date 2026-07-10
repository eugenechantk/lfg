# lfg desktop

A minimal macOS app that lists every Claude Code / Codex session across all
configured `lfg serve` hosts and reopens any of them in iTerm2 with one click.

## What a click does

| Session | Action |
| --- | --- |
| On this Mac, has a tmux pane | New iTerm2 window attached to that tmux session (`tmux attach -t <name>`) |
| On another host (or local without tmux) | New iTerm2 window with a fresh local tmux session running `claude --resume <sessionId>` in the session's cwd |

Cross-host resume works because `~/.claude/projects` syncs between machines,
so the remote session's transcript is already on disk locally. Opened iTerm2
windows are stretched to the full visible height of the display they open on.

## UI

- **Toolbar** (Liquid Glass, per the HIG toolbar groupings) — the Status /
  Directory segmented control sits in the center area; refresh and search are
  grouped on the trailing edge. Search collapses to a glass icon and expands
  into a field when clicked.
- **Search** — filters on title, project, last user message, model, agent, host.
- **Status / Directory segments** — group like the iOS client: by status
  (Working / Paused / Idle) or by directory (collapsible sections, most
  recently active first, running/idle tallies; ambiguous leaf names get their
  parent directory prefixed).
- Auto-refreshes every 10 s; badge shows `tmux` (attach) or `resume` per row.

## Hosts

`~/.config/lfg-desktop/hosts.json` (seeded with localhost on first run):

```json
{ "hosts": ["http://localhost:8766", "http://100.75.162.40:8766"] }
```

Each entry is one `lfg serve` machine (Tailscale IP or MagicDNS name). The
host whose URL is loopback — or whose reported hostname matches this machine —
is treated as local. Hosts reached twice (localhost + Tailscale IP) are
deduped by `hostId`. Unreachable hosts are listed at the bottom of the window.

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
