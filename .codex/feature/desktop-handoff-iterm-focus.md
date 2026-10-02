# Feature: Open desktop handoffs in iTerm

## User flow

1. Choose **Switch to Codex** or **Switch to Claude Code** from a desktop session.
2. Wait for the destination session to be created and listed.
3. iTerm opens the returned tmux session and brings its window forward without another row click.

The toolbar's Create Session action should have the same final opening behavior.

## Success criteria

- [x] A successful provider switch sends the returned tmux session through the iTerm opener while the list refreshes. **Verify by:** desktop feature suite and `SessionStore.switchTool` path inspection.
- [x] A successful Create Session uses the same immediate background opener while the list refreshes. **Verify by:** desktop feature suite and `SessionStore.createSession` path inspection.
- [x] The opener attaches to an existing local tmux session and brings its new iTerm window forward. **Verify by:** live `--open-session` probe, tmux client state, iTerm window state, and frontmost app check.
- [x] Opening failures still surface in the desktop alert. **Verify by:** existing action-handler and error-return path inspection.

## Decision log

- Start the iTerm opener as soon as the host returns its new session, concurrently with the list refresh. An offline secondary host should not delay the terminal window.
- Use the existing local or remote tmux opener for both actions. The opener will explicitly reactivate iTerm after creating and sizing the window.

## Verification evidence

- `desktop/build.sh` passed and `--desktop-feature-test` returned `{"ok":true,"tests":154}`. `git diff --check` passed.
- The rebuilt binary's `--open-session fbe72676-1283-45bf-bf3e-5e6f1058c797` returned `"result":"opened"` for tmux `lfg-6a41d8`. The tmux attached-client count changed from 0 to 1, iTerm gained a new main window titled `tmux`, and `lsappinfo` reported iTerm2 frontmost. The test client was detached afterward; the tmux session remained running.
- The final signed standalone build was installed at `/Applications/lfg.app`; its binary SHA-256 (`d0e9909709246d8aa5f5d11473597e7b656a7b6f4ce8678a2b3481af2a1e3a6b`) matches the signed copy FlowDeck launched through its macOS launcher project. The installed binary's 154 headless checks passed, code signing verified, and AXDriver observed the relaunched app's menu-bar control.

## Runtime limit

The live probe opened an existing tmux session. It did not create a new AI session or perform a real cross-provider handoff, so the full menu-to-handoff path remains unobserved on a production host.

## Air deployment

- The Pro's signed `/Applications/lfg.app` was transferred to Air and verified before installation. Air's previous binary was `2d721710a608d629ed9a22ceae16cb08847c0ce34c272a323ee25f5734c957bc`; the installed binary is now `d0e9909709246d8aa5f5d11473597e7b656a7b6f4ce8678a2b3481af2a1e3a6b`, matching the Pro.
- Air's previous app is backed up at `/Users/eugenechan/Library/Application Support/lfg-desktop-backups/20260930-before-auto-open/lfg.app`.
- Air relaunched `/Applications/lfg.app` as PID 48526. The installed signature verified, and its `--desktop-feature-test` returned `{"ok":true,"tests":154}`.
