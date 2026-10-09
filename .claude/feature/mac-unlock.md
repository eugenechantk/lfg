# Mac unlock for agents (`lfg-unlock`)

**Goal (Eugene, 2026-10-05):** Claude Code and Codex sessions can unlock the Pro when a task needs the GUI,
with nobody at the Mac, using our own unlock tool — not ChatGPT's. Proof: a Codex session unlocks the Pro and
drives Preview with computer use.

## What we measured (Pro, macOS 26, screen locked, nobody present)

1. A user-activity assertion (`caffeinate -u`) makes loginwindow run `startUnlock` ("start an unlock with
   'active user' as the reason") and raise the lock UI with the password field focused. No rule is evaluated yet.
2. A process with Accessibility/post-event access (`AXIsProcessTrusted` = true from a tmux-hosted shell) can post
   keys into that field. One `a` + Return produced `loginPressed: Attempt #: 1`.
3. The submit makes loginwindow call `AuthorizationCopyRights(system.login.screensaver)`. authd then walks the
   rule's branches in order (`k-of-n = 1`): each non-privileged plug-in mechanism runs in the loginwindow
   SecurityAgent (user `eugenechan`), and only if all branches deny does it fall back to `use-login-window-ui`
   (the real password check).

So an authorization plug-in mechanism placed first in `system.login.screensaver` decides the unlock, and the
trigger is "wake + type a dummy character + Return". The current rule already has OpenAI's branch; we add ours
in front and leave theirs untouched.

## Design

```
agent ──▶ lfg-unlock unlock
            1. already unlocked? exit 0
            2. listen on /tmp/dev.omg.lfg-unlock/unlock.sock (dir 0755, socket 0666: the plug-in runs as another user) — open ONLY for this attempt
            3. declare user activity → lock UI appears
            4. post "a" + Return
                 └▶ loginwindow → authd → LFGUnlockPlugin:allow (in SecurityAgentHelper)
                       └▶ connects to the socket, checks the socket is the console user's,
                          helper checks the peer is Apple's SecurityAgentHelper, replies ALLOW (once)
            5. poll CGSSessionScreenIsLocked → unlocked → exit 0
lfg-unlock lock   → lock the screen again when the task ends
```

- **No secret anywhere.** No password is stored or typed. The plug-in fails closed: no socket, a wrong peer, or
  any error = deny, and the normal password screen still works.
- **One-shot window.** The socket exists only while `lfg-unlock unlock` runs (≤ ~20 s), and it grants one ALLOW.
- **Ownership checks, not signatures** (changed after the first live run). The plug-in runs in
  `SecurityAgentHelper`, sandboxed and as another user; its code-signing lookup of the helper failed with
  status 100013, and a 0700 socket directory gave it EACCES. It now requires the socket, its directory (no
  symlinks) and the serving process to belong to the user whose screen is locked (owner of `/dev/console`,
  else the username loginwindow passed, else — single-user fallback, logged — the socket owner if uid ≥ 501).
  This is the honest boundary anyway: any process running as Eugene can run the helper. The helper answers
  only Apple code (Apple signature, or an executable under SIP-protected `/System/.../Security.framework/`).
- **Install once, with sudo** (`macos/unlock/install.sh`): copies the plug-in to
  `/Library/Security/SecurityAgentPlugins/`, adds right `dev.omg.lfg-unlock.remote`, prepends it to
  `system.login.screensaver`, and saves the old rule to `/Library/Security/lfg-unlock-screensaver-rule.backup.plist`.
  `uninstall.sh` restores it. Recovery if the unlock path ever breaks: `ssh pro` from the Air, `sudo uninstall.sh`.
- **Limits.** After a reboot, FileVault needs the real password; this tool cannot help there.
  Anything running as Eugene can run the helper — that is the point (agents need it), so the trust boundary is
  "code running as Eugene on the Pro", the same boundary that already has full shell access.

## Follow-ups (not in this pass)

- Cover the displays while unlocked and relock on local keyboard/mouse input.
- Optional phone approval before ALLOW (reuse the phone sign-in prompt).
- `unlock_mac` MCP tool for Grok.

## Evidence (2026-10-05, Pro, screen locked, nobody present)

Live run 3 (plug-in v2), `lfg-unlock unlock` from a tmux-hosted agent shell:

```
17:16:02.237 loginwindow  loginPressed: Attempt #: 1
17:16:02.261 authd        * evaluate rule dev.omg.lfg-unlock.remote (1)
17:16:03.348 authd        running mechanism LFGUnlockPlugin:allow (1 of 1)
17:16:03.370 SecurityAgentHelper-arm64 [dev.omg.lfg-unlock:plugin] unlock request answered allowed=1
17:16:03.371 authd        evaluate mechanisms result 0
→ CGSSessionScreenIsLocked absent; helper exit 0 "unlocked". OpenAI's branch never evaluated.
```

`~/.lfg/unlock.log`: `granted to com.apple.SecurityAgentHelper.arm64 ok=true` → `screen unlocked`.
`lfg-unlock lock` relocked it (`screen: locked`).

Runs 1–2 failed closed (normal password screen took over each time): run 1 EACCES on the 0700 socket dir;
run 2 the sandbox refused the plug-in's code-signing lookup (status 100013). Four wrong-password attempts total.

## Codex end-to-end (2026-10-05) and the sealed-data limit

A Codex session (started through lfg's `POST /api/sessions/new`, the same path Grok uses) ran
`~/.lfg/bin/lfg-unlock unlock` itself (`caller=…/codex --cd …`, `granted to com.apple.SecurityAgentHelper.arm64`,
`screen unlocked`), drove Preview with computer use for ~5 minutes (opened blank.pdf, Markup → Sign, Manage
Signatures, restarted Preview), then ran `lfg-unlock lock`.

Preview showed **no saved signature**. Cause, from the logs: at screen lock loginwindow runs
`lockKeybagForScreenLock: immediate lock` (grace period 0). After our unlock it tries the submitted text on the
keybag — `password failed to validate to keybag`, `KeyBagUnlock with data returned err:-3/-14` — so the
data-protection keybag stays locked (`MKBGetDeviceLockState` = 1 while the screen is unlocked). iCloud Keychain
items (Preview signatures, saved passwords) are unreadable until Eugene types his password once.

This is inherent to any password-free unlock: the keybag is derived from the password. Changes made:
- Submit with Return on an empty field (verified live) instead of `a` + Return, so no made-up password is sent.
- `lfg-unlock status` / `unlock` report `protected data: sealed`, and the agent rule says to stop and ask Eugene
  when a task needs that data.
