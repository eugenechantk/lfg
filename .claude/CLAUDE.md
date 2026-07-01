# lfg — Project Instructions

lfg runs many concurrent Claude Code agent sessions on a single host, with a Bun server and an iOS client. The hazards below come from real sessions burning time rediscovering them.

## Architecture hazards

- **Single-process Bun server.** One event loop serves all HTTP. A long-lived PTY/terminal websocket (e.g. opening the Terminal tab) can saturate it — HTTP stalls 20s+ and a restart loses in-memory session tracking. Treat embedded terminal/PTY surfaces as **capture-once-then-leave**; don't hold them open during other work.
- **A "previously-fixed" bug that recurs is usually a deploy gap, not a code bug.** Bun has no hot-reload and the `serve` process is long-lived (restarts are deferred because they drop in-memory session tracking), so the running code routinely lags source. Before re-debugging already-correct, unit-tested code, compare the running process start time (`ps -eo pid,lstart | grep '[c]li.ts serve'`) against the fixed file's mtime (`stat -f %Sm src/<file>.ts`). Process older than the fix → restart (`serve-forever.sh` respawns on child exit), don't re-debug.
- **No `/proc` on macOS.** `listSessions` in `src/sessions.ts` enriches sessions via `/proc/<pid>/cwd`, which is Linux-only. On macOS, CLI/tmux sessions won't enumerate — this is expected, not a bug. Grep source for platform assumptions (`/proc`, `systemd`, `launchd`, `pgrep`) before theorizing about missing state.
- **Sending to a tmux Claude session is `sendq.ts` driving `tmux send-keys` + screen-scrape confirm.** Two traps live here: (1) `send-keys -l` transmits text byte-for-byte, so an embedded `\n` is an Enter — multi-line messages submit/fragment at the first newline. Insert multi-line via bracketed paste (`load-buffer` + `paste-buffer -p`); Claude collapses it to a `[Pasted text +N lines]` chip and submits it whole. (2) Don't gate the Enter on re-finding your text in the composer scrape — a busy Claude swallows it into its own queue and clears the composer, so the scrape misfires. Confirm via transcript growth (idle) or composer-cleared → `queued` (busy). See `.claude/diagnosis-pending-pickup.md`. Failures now log to `data/sendq.log`.
- **Concurrent sessions edit shared files.** Multiple lfg agents may touch the same high-traffic files (stores, central views like `SessionStore.swift`) simultaneously → "file modified since read" errors and build breaks from someone else's in-flight code. Before editing a shared file, check `lfg-sessions` / `git status` for concurrent work and keep edits minimal and additive.
- **`GET /api/file?path=…` is how the iOS client fetches host files for inline rendering** (`src/commands/serve.ts`). It's read-only and traversal-hardened via `realpath` containment against a fixed root set: `REPOS_ROOT`, `SELF_REPO`, `~/` (homedir), and `$TMPDIR/lfg-uploads`. A path resolving outside all of these → 403; missing → 404. Don't narrow these roots without checking what the client references (agents emit absolute paths under home/cwd — see the "Referencing files…" directive in the global `~/.claude/CLAUDE.md`). The endpoint's security posture is "same as the rest of the API" — unauthenticated behind Tailscale, justified because the Terminal tab already grants a full shell.

## iOS / Swift gotchas

- **`ios/` is the iOS client.** Build/install with FlowDeck (`/flowdeck`), never raw `xcodebuild`/`simctl`/`devicectl`.
- **Device-only iOS bug? First ask: did the device get the latest build?** A stale installed build (works on sim, broken on device) caused a file-open 404 that looked like a code bug.
- **SSE parsing:** `URLSession.AsyncBytes.lines` drops SSE blank lines — split raw bytes on `\n` yourself. `\r\n` is a single Swift grapheme, so `firstIndex(of: "\n")` never matches CRLF; split on `unicodeScalars` instead.
- **UI automation for text fields is unreliable for URLs.** To set a URL in a SwiftUI text field during automation, write the app's `Library/Preferences/<bundleid>.plist` (PlistBuddy) in the sim data container and relaunch, rather than driving the field.

## Verification

- See user memories [[verify-real-seam-not-mocks]] and [[verify-ui-by-tapping]]: a green mocked suite isn't "verified" — exercise the real seam (wire transport, UI gesture) once, or mark it "unverified until live."
