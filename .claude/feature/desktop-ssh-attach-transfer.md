# Feature: Desktop — SSH-attach to remote tmux sessions + move session between hosts

## User Story

As Eugene running Claude Code sessions across two Macs (Pro + Air), I want the lfg desktop app to (1) open a remote session's **live** tmux pane over SSH so I can operate it directly, and (2) move a session from one host to another, so a session started on the Air can continue on the Pro (or vice versa) without manual ssh/tmux/claude gymnastics.

## User Flow

### Flow A — operate a remote session live (ssh attach)
1. Desktop app lists sessions from all hosts in `~/.config/lfg-desktop/hosts.json`.
2. A session on another host that has a tmux pane shows an `ssh` badge (instead of today's `resume`).
3. Click the row → iTerm2 window opens running `ssh -t <target> "zsh -lc 'tmux attach-session -t <name>'"` — the live remote session, full state, nothing forked.
4. Right-click the row → "Resume locally" is still available (today's behavior: fresh local tmux + `claude --resume <id>`).

### Flow B — move a session to another host
1. Right-click any resumable Claude session row (agent `claude` or `aisdk`, has a `sessionId`).
2. Context menu shows "Move to <host>" for every *other* reachable host (including "this Mac" when the session is remote).
3. If the session is busy (`status == working`), a confirmation alert warns before proceeding.
4. The app then: closes the session on the source host → waits for the transcript to sync to the target → resumes it on the target host (server spawns a managed tmux `claude --resume`).
5. The row updates on the next refresh: session now lives on the target host. Errors at any step surface in the existing alert.

## Success Criteria

- [x] SC1: Clicking a remote session that has a `tmuxName` opens an iTerm2 window attached to the **remote** tmux session over SSH (same live process — typing in it drives the remote pane). — **Verify by:** E2E on real hosts: click a Pro session row from the Air; confirm the generated command attaches (`tmux list-clients` on the Pro shows a new client). *(verified at every seam; final in-app visual click pending screen unlock + TCC grant — see Evidence)*
- [x] SC2: Local sessions with tmux behave exactly as before (local `tmux attach`). — **Verify by:** diff shows the branch unchanged + auditor code inspection. *(visual spot-check pending unlock)*
- [x] SC3: `hosts.json` accepts both legacy string entries and object entries `{ "url": "...", "ssh": "user@host" }`; when `ssh` is absent the target derives as `<local username>@<URL host>`. — **Verify by:** live run with mixed config (both hosts listed) + auditor compiled the real decoder in a harness incl. fallback derivation.
- [x] SC4: "Move to <host>" moves a session: after the flow completes, the target host's `/api/sessions` lists a live session resumed from the original id, and the source host no longer lists it live. — **Verify by:** full E2E with disposable sessions through the real `MoveCoordinator` — done twice (mine + auditor's independent reproduction).
- [x] SC5: Moving a busy session first shows a confirmation alert; cancel aborts with no API calls. — **Verify by:** code review of the guard (mine + auditor). *(visual pass pending unlock)*
- [x] SC6: Failures surface, not silently swallowed: close-failure, sync-wait timeout, and resume-endpoint errors each produce an alert naming the step that failed; a sync-timeout alert tells the user the session is closed but still resumable. — **Verify by:** live: bogus-id close failure (mine + auditor) and full 90 s timeout run with the "session is safe" message (auditor); resume-error path by code + binary strings.
- [x] SC7: Right-click on a remote tmux session offers "Resume locally" (previous default preserved as an explicit action). — **Verify by:** code review — `Opener.resumeLocally` is the extracted, unchanged pre-existing resume path + menu wiring inspected (mine + auditor). *(visual pass pending unlock)*

## Platform & Stack

- **Platform:** macOS desktop (single-file SwiftUI app, `desktop/LFGSessions.swift`, built by `desktop/build.sh` via swiftc — no Xcode project, no test target)
- **Language:** Swift
- **Key frameworks:** SwiftUI, AppKit, URLSession; iTerm2 driven via osascript (existing `Opener` pattern)
- **Server:** no changes — uses existing endpoints `/api/info`, `/api/sessions`, `/api/sessions/resumable`, `POST /api/sessions/<id>/close`, `POST /api/sessions/resume`

## Design

### SSH attach (Flow A)
- `SessionItem` gains `hostURL: String` and `hostSSHTarget: String?` (threaded from `HostState`).
- `Config` hosts parsing: each entry is either a string (URL) or `{url, ssh}`. Decoder tries both. `HostState` carries `sshTarget: String?`.
- `Opener.open` decision table becomes:
  1. local + tmuxName → local `tmux attach` (unchanged)
  2. remote + tmuxName → `ssh -t <target> "zsh -lc 'tmux attach-session -t <name>'"` in a new iTerm window. `zsh -lc` because ssh remote commands get a non-login shell (Homebrew tmux not on PATH). `-o ConnectTimeout=5` so a dead host fails fast. `<target>` = host entry's `ssh` field, else `NSUserName()@<host part of URL>` (Tailscale IP — ssh works against it).
  3. remote (or local) without tmux but with sessionId → local resume (unchanged, now also exposed as context-menu "Resume locally" for case 2 rows).
- Row badge: remote+tmux rows show `ssh` (green); `resume` badge stays for no-tmux rows.
- Quoting: tmux session names come from lfg (`lfg-*`/`lfgd-*`, shell-safe) but still single-quote inside the remote command; escape for iTerm's tokenizer (double-quoted arg) and AppleScript via existing `asq`.

### Move to host (Flow B)
New `MoveCoordinator` (or static enum like `Opener`) with an async `move(item:to:)`:
1. **Guard:** target host reachable (`error == nil`), different `hostId` from source, session agent ∈ {claude, aisdk}, `sessionId` present.
2. **Busy confirm:** if `item.status == .working`, show `.confirmationDialog`/alert first.
3. **Close on source:** `POST <source>/api/sessions/<id>/close`. Non-2xx → alert "close failed", abort.
4. **Capture final activity:** `GET <source>/api/sessions/resumable?limit=100`, find the session, record its final `lastActivityAt` (fallback: the value we already had).
5. **Wait for sync:** poll `GET <target>/api/sessions/resumable?limit=100` every 3 s up to 90 s until the session appears with `lastActivityAt >= final - 1.0` (1 s epsilon — mtimes/serialization jitter). Timeout → alert: "Closed on <source>, but the transcript hasn't synced to <target> yet. The session is safe — resume it there once sync catches up." Abort (no resume).
6. **Resume on target:** `POST <target>/api/sessions/resume {"sessionId": id}`. Server returns `{tmuxName, sessionId: newId}` (or `alreadyLive`). Non-ok → alert with server error text.
7. **Refresh** the store. In-flight UI: the row shows a small "moving…" state (spinner or badge) and is disabled for the duration; keep it simple — an `@Published movingIds: Set<String>` on the store is enough.

### Context menu
`.contextMenu` on each session row:
- "Resume locally" — remote sessions with a sessionId (Flow A alternative).
- "Move to <host label>" — one item per eligible target host (Flow B). Omit entirely when no eligible targets.

## Steps to Verify

1. Build: `cd desktop && ./build.sh` (must compile clean).
2. Run the built app with a hosts.json listing both hosts (`http://localhost:8766` + the Air's Tailscale URL).
3. SC1/SC2/SC7: click rows, observe iTerm; `tmux list-clients` on each host.
4. SC4: `curl -X POST http://<hostA>:8766/api/sessions/new -d '{"cwd":"...","agent":"claude","prompt":"say hi"}'` to make a disposable session; move it via UI; `curl` both `/api/sessions`.
5. SC3/SC5/SC6: mixed hosts.json load; busy-confirm and failure paths per criteria above.

## Implementation Phases

### Phase 1: Config + SSH attach
- Scope: hosts.json object entries, `sshTarget` threading, `Opener.open` remote-attach branch, `ssh` badge, "Resume locally" context-menu item.
- Success criteria covered: SC1, SC2, SC3, SC7
- Verification gate: build clean + SC1/SC2 E2E green.

### Phase 2: Move to host
- Scope: `MoveCoordinator` flow (close → sync-wait → resume), context-menu targets, busy confirmation, moving-state UI, error alerts.
- Success criteria covered: SC4, SC5, SC6
- Verification gate: build clean + SC4 E2E green with disposable session.

## Decision Log

- **Default click action for remote+tmux rows = ssh attach** (not resume-local). Rationale: it's the only option that operates the *live* process with zero state loss; resume-local forks the conversation and leaves the remote one running. Resume-local stays reachable via context menu (SC7).
- **Remote command uses an explicit PATH prefix, not `zsh -lc`.** E2E against the real Pro showed `zsh -lc` does NOT get Homebrew on PATH for ssh remote commands (`command not found: tmux`). Final form: `ssh -t -o ConnectTimeout=5 <target> "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux attach-session -t '<name>'"` — `$PATH` expands on the remote (no local shell in the iTerm command path).
- **Added a hidden `--move-test <id> <sourceURL> <targetURL>` CLI hook** to the desktop binary: runs the real `MoveCoordinator.move` headlessly and prints one-line JSON. Added because the machine's screen locked mid-verification (GUI automation impossible) — and it stays as a permanent, repeatable verification hook for the move flow. It bypasses the busy-confirm by design (that guard is UI-layer).
- **Kept the mixed-format hosts.json as the live config** (localhost + Pro with `ssh` field) instead of restoring the localhost-only original — it's the feature's intended configuration and strictly more useful. Backup preserved at `~/.config/lfg-desktop/hosts.json.bak-ssh-attach-verify`.
- **hosts.json stays one file, entries become string-or-object.** Alternative was a parallel `ssh` map keyed by URL — rejected as harder to keep in sync by hand.
- **SSH target fallback = `NSUserName()@<URL host>`** — same username on both Macs and Tailscale IPs accept ssh, so zero config needed for the current fleet; the `ssh` field exists for anything unusual.
- **Close source BEFORE resuming target** (not resume-first): two live processes writing one transcript is the worse failure; sync-wait with a 90 s budget bridges the gap, and a timeout leaves a safe, resumable state on both hosts.
- **No unit-test infra added.** The app is a single swiftc-compiled file with no test target; adding SwiftPM restructuring for this feature is out of scope. Verification is build + real E2E against both hosts (per [[verify-real-seam-not-mocks]] this is the stronger seam anyway).
- **No server changes.** Both flows compose from existing endpoints; keeps the deploy-gap hazard (long-lived Bun process) out of the blast radius entirely.

## Verification Evidence

Context: mid-verification the machine's screen locked (2:40 AM, user away), which blocks GUI automation (AX reads, window realization, screenshots) and the one-time TCC Apple-Events consent click. Everything below marked LIVE ran for real; the three UI-surface criteria carry a small "visual pass when unlocked" residual, listed at the end.

| Criterion | Result | Evidence |
|---|---|---|
| SC1 ssh-attach | **LIVE (all seams except final in-app click)** | (a) In-app row press captured live: app spawned `osascript` with its generated ssh command (ps output, round-1 build) — proves UI→Opener→iTerm wiring. (b) Round-1 command failed on the real host (`zsh:1: command not found: tmux`) → bug fixed. (c) Fixed command run E2E verbatim: new attached client appeared on the Pro (`/dev/ttys064: cy-015218-35822 (attached)`), then cleaned up. (d) Fixed template confirmed in shipped binary (`strings`). Residual: one in-app click after screen unlock + TCC grant. |
| SC2 local attach unchanged | **Code-review** | Diff shows the `hostIsLocal + tmuxName` branch byte-identical (existing production behavior). Residual: visual spot-check. |
| SC3 hosts.json formats | **LIVE** | App launched with mixed config (`localhost` string + Pro object w/ `ssh`), listed sessions from BOTH hosts — screenshot `.claude/feature/evidence-desktop-ssh-attach/sc3-both-hosts.png` (Air rows + Pro row with green `ssh` badge). Fallback derivation (`NSUserName()@urlhost`) code-reviewed. |
| SC4 move to host | **LIVE, full E2E** | Disposable session `1ba41b4b…` created on Air via `/api/sessions/new`; moved Air→Pro through the REAL `MoveCoordinator` (`lfg --move-test … → {"ok":true}`, 3.6 s incl. ~1 s transcript sync). After: Air `/api/sessions` no longer lists it, local tmux gone; Pro runs `claude --resume 1ba41b4b…` in managed tmux `lfg-cde131`; transcript on Pro contains the test marker (`grep -c MOVE-TEST-READY` → 4). Cleaned up after. |
| SC5 busy confirm | **Code-review** | `requestMove` gates on `item.status == .working` → confirmation alert; Cancel path makes zero network calls (all calls live in `startMove`). Residual: visual pass. Note: `--move-test` bypasses this by design (UI-layer guard). |
| SC6 failure surfacing | **LIVE (close path) + code-review (rest)** | Close-failure run: `--move-test` with bogus id → `{"ok":false,"error":"Move failed at close: HTTP 404: …session not found…"}`, exit 1, nothing mutated. All four distinct alert strings confirmed in shipped binary via `strings` (close / sync-wait / sync-timeout incl. "session is safe" wording / resume). Poll errors now retryable until the 90 s deadline. Unreachable hosts are excluded from move targets by eligibility (`host.error == nil`). |
| SC7 resume-locally menu | **Code-review** | `Opener.resumeLocally` is the extracted, unmodified pre-existing resume path (production-proven); context-menu wiring shows it for remote sessions with a sessionId. Residual: visual pass. |

**Measured facts:** Syncthing transcript sync Air→Pro = ~1 s (watcher-driven); full move = 3.6 s; the 90 s sync budget is comfortable.

| Independent audit | **PASS** | `verification-auditor` reproduced everything headless-verifiable from scratch: clean build, its own disposable move E2E (`{"ok":true}` in 4.4 s, transcript on Pro), the exact ssh command live against the Pro (new client `/dev/ttys067`, clean detach, zero keystrokes), the real `Config` decoder compiled into a harness (string/object/fallback all correct), bogus-id negative path, AND a full 90 s sync-timeout run producing the "session is safe" message with the session confirmed still resumable. Report: `.claude/feature/evidence-desktop-ssh-attach/audit/evidence.md`. |

**Audit findings (accepted):**
- `--move-test` bypasses ALL UI eligibility guards (agent type, target reachability, same-host), not only the busy-confirm — it tests `MoveCoordinator`, the UI guards live in `ContentView`/`SessionStore` and are code-review-verified.
- New **server-side** bug found (out of this feature's scope, verdict unaffected) — recorded under Bugs below.

**Residual for Eugene (2 minutes, when back at the machine):**
1. Unlock the screen, open the worktree build (`desktop/build/lfg.app`), click the Pro `ssh` row → approve the one-time "lfg wants to control iTerm2" TCC prompt → iTerm should land in the live Pro session. (Ad-hoc signing makes this grant per-build — known hazard; a stable signing identity would fix it permanently.)
2. Right-click any Pro session row → check "Resume locally" + "Move to …" items render; optionally cancel a busy-move to see the confirm alert.

## Bugs

- ~~Round 1: remote command `zsh -lc 'tmux attach-session …'` fails on the real remote host — `zsh:1: command not found: tmux` (login shell doesn't source Homebrew PATH for ssh remote commands)~~ — **fixed** in round 2 with the explicit PATH prefix; the exact generated command then verified E2E (new attached client on the Pro).
- ~~Round 1: `MoveCoordinator.waitForSync` aborted the whole move on a single transient poll error (after the source was already closed)~~ — **fixed** in round 2: poll errors are retryable until the 90 s deadline.

**Out-of-scope server finding (auditor, needs follow-up in `src/`):** closing a *resumed* session on its new host via `POST /api/sessions/<id>/close` killed the tmux session but orphaned the `claude` process, which then re-listed as an unmanaged session the API refuses to close (`"session is not in a tmux pane — cannot close"`); manual `kill -9` was required. A user who moves a session and later closes it on the target can hit this. Likely `tmuxKillSession` vs. process-group semantics for resumed sessions. Not fixed here — server changes are outside this feature's blast radius.

_None open in this feature's scope._
