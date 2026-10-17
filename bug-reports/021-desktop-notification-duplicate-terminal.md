# Bug 021: Notification opens a duplicate terminal

## Status: FIXED AND INSTALLED

## Description

Clicking a desktop notification opens another iTerm window while an existing terminal already holds the session.

## Steps to Reproduce

1. Connect Air to Pro with an interactive `mosh-bridged pro` shell.
2. Start an agent inside tmux from that shell.
3. Click the agent's notification on Air.
4. LFG opens a second terminal instead of selecting the existing one.

The user has not yet confirmed which Mac showed the reported duplicate. Live inspection found this unsupported pattern on Air.

## Root Cause

The old lookup recognizes terminal markers and direct attach commands.
An interactive Mosh shell has neither the agent session name in its local command nor a terminal marker on its remote tmux client.
The live session `codexy-224629-13403` uses remote Mosh port 60119 and Air terminal `/dev/ttys010`.
The old discovery returns only its `tmux new-session` command, which the attachment parser ignores.

## Success Criteria

- [x] Match an existing interactive Mosh bridge using the live server port and exact host. Verify parser tests and Air's real process topology.
- [x] Focus the existing iTerm pane without adding another tmux client. Verify a disposable interactive Mosh shell through native notification activation.
- [x] Keep host and port matching exact. Verify wrong-host, wrong-port, malformed, and ambiguous cases.
- [x] Preserve tracked attachments, direct legacy attachments, and new-window behavior. Verify the desktop suite and native checks.
- [x] A failed connection lookup shows an error and does not open another window. Verify reducer checks and a native failure/recovery test.
- [x] Install the corrected signed build on Pro and Air. Verify checksums, running executable paths, and permission status.

## Verification Evidence

- `.codex/evidence/desktop-notification-duplicate/baseline.json` records the missed original attachment and the existing duplicate marker.
- The corrected lookup finds the original Air terminals for two interactive sessions and the existing direct attachment. See `air-discovery.json`.
- All 254 desktop checks pass on both Macs, including 12 matching cases and three lookup-result cases.
- A native notification click selected the existing disposable interactive terminal from another window. The remote tmux client stayed PID 50190; no attachment was added.
- Native screenshots, activation results, and client counts are in `.codex/evidence/desktop-notification-duplicate/`.
- The independent native audit passed existing-window, missing-window, tracked-window reuse, lookup-failure, and recovery checks. See `audit/evidence.md`.
- Air's installed app opened a real Pro session through the notification callback. Its three existing tmux clients remained unchanged. See `air-real-open.json`.
- Both installed apps have SHA-256 `761ca96c1a0d7a4d416eb5f8de6b38e95b331c07ae0188cb6a777f8dcd31c976` and valid signatures. Running paths and authorization status 2 are recorded in `pro-installation.json` and `air-installation.json`.
- Both apps run with their normal host configuration. Pro visibly shows Pro and Air connected. The disposable session, terminal, and fixture listener are removed.
- Air's native banner was not clicked remotely because SSH lacks Accessibility. Its installed callback and unchanged client count were verified directly.

## Investigation Log

### Attempt 1

**Hypothesis:** Existing interactive Mosh shells cannot be found through their command arguments.

**Result:** Confirmed with live Pro tmux clients, Mosh server sockets, and Air bridge processes. No user session was altered.

**Plan:** Follow the remote client's process ancestry to its Mosh server. Match that server's UDP port to a live bridge on the same configured host.

**Changes:** Added bounded process ancestry discovery and exact host/port matching. Added a read-only diagnostic command for inspecting live attachments without opening a window.

**Verification:** Development checks, native clicks, independent audit, and installation passed.

### Attempt 2: Remove a notification test collision

The first independent minimized-window check reached the old installed app, which did not know the isolated fixture host.
That run is invalid as a test of the fix. Its error evidence is preserved.
The candidate release now runs from `/Applications/lfg.app` with the isolated fixture configuration, so macOS routes alerts to the correct process.
Both Pro and Air passed all 251 candidate checks. Native re-verification then passed against the installed app.

### Attempt 3: Fail safely when lookup fails

An Air lookup returned no identifiers, although the original clients remained alive. A repeat returned the correct original terminal.
That observation does not establish an SSH failure: the diagnostic does not expose whether the snapshot included a tmux name.
Separately, source inspection found that a nonzero SSH lookup status was treated as an absent terminal.
Lookup errors now stop window creation and ask the user to reconnect and retry.
The independent native failure and recovery checks passed against the final build. No client or window was added during the failure.
