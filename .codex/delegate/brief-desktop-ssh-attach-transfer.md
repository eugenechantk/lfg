# Delegation Brief: desktop ssh-attach + move-to-host

Goal: In the lfg macOS desktop app, (1) clicking a remote session that has a tmux pane opens an iTerm2 window ssh-attached to that remote tmux session, and (2) a context menu lets the user move a resumable Claude session from one host to another (close on source → wait for transcript sync → resume on target).

Working dir: /Users/eugenechan/dev/personal/lfg/.claude/worktrees/desktop-ssh-attach-transfer (a git worktree — do all work here, do NOT touch the main checkout).

Full spec (read it first): .claude/feature/desktop-ssh-attach-transfer.md — the "Design" section is the authoritative behavior spec, including the exact move-flow ordering, timeouts, and error wording expectations.

## Constraints

- ONLY file to modify: `desktop/LFGSessions.swift` (single-file SwiftUI app, ~955 lines). No server changes, no iOS changes, no new files except none.
- Build with `cd desktop && ./build.sh` (swiftc; no Xcode project). Must compile clean.
- Match the file's existing style: `Opener`-style static enums, `shq`/`asq` quoting helpers, osascript via Process (never NSAppleScript), errors surfaced through the existing `alertMessage` alert.
- macOS gotchas that already bit us (respect them): iTerm windows must be launched via `create window with default profile command "..."` (never create-then-write-text); iTerm tokenizes the command param itself — quoted args OK, shell builtins NOT.
- Do NOT commit. Leave changes in the working tree.

## Spec (condensed — feature doc governs)

### A. hosts.json: string-or-object entries
- `~/.config/lfg-desktop/hosts.json` entries become either `"http://host:8766"` (legacy) or `{"url": "http://host:8766", "ssh": "user@host"}`. Decode both (custom Decodable init or try-string-then-object). Seed file stays string-form.
- Thread an optional `sshTarget` through `HostState` into `SessionItem` (also add the host's base `url` to `SessionItem` — the move flow needs it).
- SSH target fallback when `ssh` absent: `NSUserName() + "@" + <host part of the URL>`.

### B. SSH attach (new default for remote+tmux rows)
- In `Opener.open`: new branch — if NOT hostIsLocal AND session has `tmuxName`: open iTerm window with command:
  `ssh -t -o ConnectTimeout=5 <sshTarget> "zsh -lc 'tmux attach-session -t <name>'"`
  (zsh -lc so the remote login PATH finds Homebrew tmux; single-quote the tmux name inside; the whole remote command is ONE double-quoted iTerm arg; escape for AppleScript with `asq` as today).
- Local+tmux path unchanged. No-tmux resumable path unchanged.
- Row badge: remote sessions WITH tmuxName show `ssh` (green); `resume` badge only for rows whose open path is resume. `tmux` badge for local unchanged.

### C. Context menu on session rows
- "Resume locally" — shown for remote sessions with a sessionId; runs the existing local-resume path (extract it from `Opener.open` into a callable so both paths share it).
- "Move to <host label>" — one item per eligible target: reachable host (`error == nil`), different hostId than the session's host, and session agent is "claude" or "aisdk" with a non-nil sessionId. Omit items when none eligible.

### D. Move flow (async coordinator, e.g. `enum Mover` or methods on SessionStore)
1. If the session's status is working/busy → show a confirmation first ("Session is working — move anyway?" destructive-style confirm). Cancel = no network calls.
2. POST `<sourceURL>/api/sessions/<sessionId>/close` — non-2xx or transport error → alert "Move failed at close: <detail>" and abort.
3. GET `<sourceURL>/api/sessions/resumable?limit=100`, find the session, capture its final `lastActivityAt` (fallback to the value the app already had).
4. Poll GET `<targetURL>/api/sessions/resumable?limit=100` every 3 s, up to 90 s, until the session id appears with `lastActivityAt >= final - 1.0`. Timeout → alert telling the user it was closed on the source but the transcript hasn't synced yet; the session is safe and resumable later. Abort (no resume call).
5. POST `<targetURL>/api/sessions/resume` with JSON body `{"sessionId": "<id>"}` — server returns `{ok, tmuxName, sessionId}` or an error string; non-ok → alert with the server's error text.
6. Refresh the store.
- While a move is in flight: track the session id in a `@Published movingIds: Set<String>` on SessionStore; the row shows a "moving…" state (small ProgressView or badge) and its open button + context menu are disabled.
- All URLSession work off the main actor except state updates.

## Verification (run these yourself)

1. `cd desktop && ./build.sh` — compiles with no errors (warnings acceptable if pre-existing).
2. Launch check: `open build/LFG Sessions.app` (or however build.sh names it — check the script) and confirm it launches and lists sessions (a running local server on :8766 may or may not be present in this environment; if unreachable, confirm the app still launches and shows the unreachable notice rather than crashing).
3. Config parse check: temporarily point the app at a mixed-format hosts.json (string + object entry) — confirm both parse (no decode failure). You can do this by writing a scratch hosts.json to ~/.config/lfg-desktop/hosts.json ONLY IF you first back up the existing file and restore it after; otherwise skip runtime config check and state so.
4. Static sanity: print (or log) nothing new to stdout in release; no force-unwraps on network data.

## Definition of done

- [ ] `desktop/build.sh` compiles clean.
- [ ] Remote+tmux rows: click → iTerm command is the ssh-attach form above (exact command string constructible — include it in your report).
- [ ] Local rows unchanged behavior (attach), no-tmux rows unchanged (resume).
- [ ] hosts.json accepts string and object entries; ssh fallback = NSUserName()@urlhost.
- [ ] Context menu: "Resume locally" + "Move to <host>" per eligibility rules.
- [ ] Move flow implements close → capture final activity → sync-poll (3s/90s, 1s epsilon) → resume → refresh, with the three distinct error alerts and busy-confirm.
- [ ] In-flight move state disables the row and shows a moving indicator.

## Report back

Files changed, the exact iTerm/ssh command string your code produces for a sample remote session, build output tail, what you could and couldn't runtime-verify (and why), and anything incomplete.
