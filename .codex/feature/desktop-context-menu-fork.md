# Desktop conversation fork to iTerm

## User story and flow

Right-click a Claude Code or Codex conversation in the desktop client, choose **Fork session**, and continue a separate branch in a new iTerm window attached to an LFG-managed tmux session. The original conversation remains available.

## Success criteria

- [x] Eligible conversation rows expose the fork action, including closed and externally owned conversations. **Verify:** desktop feature test and live accessibility menu inspection.
- [x] The action sends the source session ID to its owning host's fork endpoint, then opens the returned tmux session in iTerm. **Verify:** desktop feature test plus live flow with a safe mock host and disposable tmux session.
- [x] A pending fork cannot be started twice, and errors are shown without opening an invalid session. **Verify:** desktop feature test and mock host error response.

## Decision log

- Use the existing `/api/sessions/fork` endpoint and `Opener.open` path. This preserves the server's Claude/Codex fork semantics and local or remote iTerm transport.
- Permit live, closed, and external rows when they have a Claude/Codex session ID. The server remains responsible for transcript and ownership checks.

## Verification evidence

- `desktop/build/lfg.app/Contents/MacOS/lfg --desktop-feature-test` → `{"ok":true,"tests":161}`. Covers eligibility, owner-host request URL/body, returned tmux target, duplicate pending guard, and Claude's valid temporarily unbound branch ID.
- `bun test src/commands/serve-fork.test.ts src/tmux-argv.test.ts src/codex-app-server.test.ts` → 20 pass, 0 fail. Covers the existing server fork lineage, agent argv, and Codex app-server fork contract.
- AX on a running mock-host desktop client: a live Codex row with a session ID and no tmux exposed the enabled **Fork session** menu item. Pressing it sent `{"sessionId":"test-external-id"}` to the mock host. A 502 response displayed `Fork failed: intentional mock fork failure` in the app.
- With the same mock host returning a valid branch, pressing **Fork session** opened a fifth iTerm window and `tmux list-clients -t lfg-branch-ui-smoke` reported an attached client. The disposable tmux session and test window were removed afterward. This verifies desktop request-to-iTerm wiring; it does not create a real agent fork.
- `/Applications/lfg.app` was replaced and relaunched. Installed and build executable SHA-256 hashes match (`df0a90fd612b7ba978e68fcbc510a2a0dbe412f5951a67a816868ea24734d9ab`); the installed signature verifies and the running binary is `/Applications/lfg.app/Contents/MacOS/lfg`.

## Residual limit

The live success check used a mock fork response and disposable tmux session. The server's actual agent-native fork is covered by its existing tests, but no real user conversation was branched during verification.
