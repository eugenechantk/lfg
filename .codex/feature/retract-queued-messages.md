# Edit and remove messages before delivery

## User story

Queued messages remain editable and removable until the provider consumes them.
Provider handoff alone does not resolve the message.

## User flow

1. Queue a message while Claude Code or Codex works.
2. Open that message's menu and choose Edit or Remove.
3. The host retracts it from the provider before confirming removal.
4. Edit restores the text to the composer. Sending submits the revised text.
5. If delivery wins the race, retain the row and report the result.

## Success criteria

- [x] SC1: Native queued rows offer Edit and Remove for both providers.
  Verify with `QueuedStripRowTests` and the simulator menu.
- [x] SC2: Removing a native queued row retracts it from the provider.
  Verify with host integration tests and disposable provider sessions.
- [x] SC3: Editing retracts the original before restoring the draft.
  Verify through the simulator transport and revised provider delivery.
- [x] SC4: Concurrent sends, removal, reconciliation, and delivery do not lose or duplicate other messages.
  Verify with race and multiple-message tests.
- [x] SC5: Failure or confirmed delivery never produces a false cancellation.
  Verify with host integration tests and client resolution tests.

## Platform

SwiftUI client, LFGCore, Bun host, and provider TUIs over tmux.

## Decisions

- Keep the existing Edit interaction: retract, return text to composer, then send again.
- Confirm native retraction before changing the durable queue or optimistic client state.
- Preserve active turns and other queued messages.
- Claude's native Up recalls every queued input. Persist each recalled sibling before clearing the terminal draft, then return it to the normal pump.
- Codex's shared daemon uses WebSocket over its Unix socket. Delete the exact client submission when available; reject ambiguous legacy text matches.
- An Edit request carries its intent to the host. A delivered receipt can be dismissed, but it cannot become an editable duplicate.
- Require Claude's native recall cue before pressing Up, so a delivery race cannot recall command history.
- Serialize native recall against send-now and every active delivery, including another row already typing.

## Verification evidence

Evidence directory: `.codex/evidence/retract-queued-messages/`.

- SC1: `QueuedStripRowTests` pass. `claude-menu.jpg` and `codex-menu.jpg` show all three actions after actual provider handoff.
- SC2: `native-live-results.json` records successful production retraction for Claude Code 2.1.280 and Codex 0.163.0. Each probe retained its other queued entry. `ui-actions.jsonl` records successful native removal from both simulator flows.
- SC3: The simulator's Edit action returned the exact sent text to the composer. `claude-edit-draft.jpg`, `codex-edit-draft.jpg`, `ui-self-check.mov`, and the action log record Edit, resend, and Remove. The revised Claude text reached its native queue before removal.
- SC4: `sendq-retraction.test.ts` covers preserved sibling order, terminal-originated entries, duplicate text, concurrent second removal, send-now, another row already typing, and restart recovery after an unconfirmed composer clear.
- SC5: Tests cover failed retraction, a delivery race, editing a delivered receipt, and native ambiguity. Existing client removal-resolution tests preserve the row on HTTP 409 or failed requests.
- `host-tests.txt`: 80 Bun tests passed across eight relevant files.
- `menu-anchor-tests.txt`: two existing menu wiring tests passed.
- `swift-tests.txt`: 648 XCTest cases ran with one skip and no failures. All 457 Swift Testing cases passed.
- `build.jsonl`: FlowDeck app build succeeded.
- `typecheck.txt`: `bunx tsc --noEmit` passed. `git diff --check` passed.
- Independent visual audit: **PASS**, `.codex/evidence/20261017-115440-ios-visual-audit/evidence.md`. Independent recordings cover both providers, including a two-message Claude recall that preserves its sibling.
- `post-release-verification.json`: after both providers resumed, none of the nine cancelled UI submissions appeared in consumed user turns. Both disposable provider sessions were then closed.

## Residual risks

- The simulator fixture supplies session metadata and a short introduction. Its send and removal paths call production queue code and real provider queues. This proves the app-to-provider action path, not a deployed host or physical iPhone build.
- Older Codex local-TUI recall is conservative: unrecognised or unreadable drafts remain tracked. The current daemon API path was verified live.

## Bugs

No open bugs. Independent review found a race with another row already typing. The mutation lease now waits for the active delivery before native recall; the regression passes.
