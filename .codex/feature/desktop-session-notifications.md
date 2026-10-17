# Desktop session notifications

## User story

Desktop LFG alerts Eugene when a session finishes or needs input, including sessions on other hosts.
Clicking an alert focuses the attached iTerm pane or opens a window attached to that session.

## Success criteria

- [x] SC1: Finished and needs-input alerts match the phone's transition rules. Verified with reducer and store integration tests.
- [x] SC2: Startup, duplicate host aliases, polling, reconnects, and closed history do not produce repeated alerts. Verified with sequence tests.
- [x] SC3: Notification clicks resolve the current session and host. Verified payload round trips, routing tests, and native notification activation.
- [x] SC4: Local attachments focus their existing iTerm pane; missing attachments open one. Verified using disposable tmux sessions.
- [x] SC5: Remote attachments focus their existing local iTerm pane; missing attachments open through the configured transport. Verified on Air with disposable sessions.
- [x] SC6: Permission and opening errors remain visible and recoverable. Verified authorization and offline errors live; reviewed denial recovery in source.

## Decisions

- Reuse the desktop's app-owned live feed and snapshot recovery. No phone or server deployment is required.
- Match the phone's ten-second deduplication window, including delayed needs-input alerts.
- Keep notifications active while LFG runs with its windows closed. macOS notification permission remains required.
- Use live terminal identity, scoped by host, rather than window titles.
- Use the existing standalone Swift build and headless test suite. The saved FlowDeck project targets the separate iOS app.
- Air installation and the commit were authorized in follow-up requests. No push is included.

## Verification evidence

- Development and optimized builds passed. Both passed all 239 checks, including 31 new notification and routing checks.
- Native macOS notification permission was enabled through System Settings. The notification center reports authorization status 2.
- Real banner activation opened a missing local terminal and a missing Air terminal. Air used the configured Mosh bridge.
- Native Air needs-input activation selected the existing terminal GUID `591A9C1E-E891-41A5-A940-0D4E7954A27E` from the local terminal.
- The remote tmux client retains the matching `LFG_ITERM_SESSION_ID`. Legacy Mosh attachment discovery also reused its original terminal.
- Local open probes reused terminal GUID `051645F2-D455-4B78-8D7A-E27BB26876FF` without adding a tmux client.
- Evidence lives in `.codex/evidence/desktop-notifications/`: test output, banner trees, screenshots, activation results, and the reproducible fixture.
- The fixture uses isolated configuration and disposable tmux sessions. It does not start real provider turns.
- The independent native audit passed. It verified exact local and Air terminal selection, minimized-window restoration, unchanged attachment counts, delayed retries, and the offline error modal.
- The optimized app signature verifies. Its binary SHA-256 is recorded in `release-sha256.txt`.
- Installed `/Applications/lfg.app` on Pro. The running executable resolves to that installed path and matches the tested release binary.
- The installed app shows the normal Pro and Air hosts connected. Notification authorization remains enabled.
- The previous app is backed up under `~/Library/Application Support/lfg-desktop-backups/20261017-before-desktop-notifications/`.
- Both disposable tmux sessions and their iTerm windows are removed. The fixture listener is stopped. Production host configuration is unchanged.
- Installed the same signed release on Air. Its running executable resolves to `/Applications/lfg.app/Contents/MacOS/lfg` and matches Pro's SHA-256.
- Air passed all 239 checks and reports notification authorization status 2. Its Air/Pro host configuration is unchanged, and its previous app is backed up.
- Air deployment evidence lives under `.codex/evidence/desktop-notifications/air/`. The SSH session lacks Accessibility and Screen Recording grants, so Air's native click flow was not repeated.

## Residual risks

LFG must remain running to receive events; closing its windows is supported. Quitting the process stops desktop alerts.
Arbitrary nested or ambiguous legacy remote attachments cannot be identified safely. Those open a new attached window.
The temporary remote sessions use Air's real SSH/Mosh transport, with a fixture supplying session metadata and transitions.
The audit did not switch notification permission to denied. Denial recovery was checked in source.
Closed-session resume routing has automated coverage; a real provider resume was not started during verification.

## Follow-up: existing interactive Mosh windows

The notification opener now finds sessions started inside an existing interactive `mosh-bridged` shell.
It matches the remote Mosh server port to a local bridge on the exact configured host.
SSH lookup failures show an error instead of opening another terminal.

The signed fix is installed and running on Pro and Air with normal configuration. Both pass all 254 desktop checks.
Independent native checks passed existing-window selection, missing-window creation, tracked-window reuse, and failure recovery.
Air's installed notification callback also reused a real Pro session without adding a tmux client.
See `bug-reports/021-desktop-notification-duplicate-terminal.md` and `.codex/evidence/desktop-notification-duplicate/audit/evidence.md` for evidence and limits.
