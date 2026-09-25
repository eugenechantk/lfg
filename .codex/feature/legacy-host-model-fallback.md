# Feature: Safe Legacy-Host Model Fallback

## User Story

As an LFG user, I can still start and switch chats when the iOS client is newer
than an LFG host, without being offered model IDs that host cannot launch.

## User Flow

1. Open a model selector for a host that lacks `GET /api/models`.
2. LFG falls back to stable Claude aliases and known-working Codex IDs.
3. Start or switch the chat successfully.
4. After the host is updated, reopening the selector replaces compatibility
   choices with its live CLI-discovered catalog.

## Success Criteria

1. A host that returns 404 for `GET /api/models` exposes only compatibility-safe
   fallback choices: Claude aliases and known-working Codex 5.6 IDs.
2. A safe but unsupported persisted model is reconciled again immediately before
   a create request, even when the user never opens the model sheet.
3. A host that implements `GET /api/models` still replaces the fallback with the
   installed Claude Code and Codex catalogs, including newly released IDs.
4. Session model-switch menus use the same safe fallback on legacy hosts.
5. On updated hosts, switching a managed Claude session changes the actual model
   instead of accepting `/model` while retaining the launch-pinned model.

## Test Strategy

- Unit-test the bundled TypeScript catalog independently from discovery parsing.
- Unit-test Swift fallback contents and request-boundary selection reconciliation.
- Keep dynamic-catalog decoding tests to prove new exact IDs still override the
  compatibility catalog.
- Build and run the app against the unchanged September 24 host, whose 404 is the
  real backward-compatibility seam, and inspect both model selector groups.

## Tests

- `bun test src/model-catalog.test.ts`
- `bunx tsc --noEmit`
- `swift test --filter ModelsTests`
- Full Bun and LFGCore suites
- FlowDeck build/run plus Simulator UI evidence against `127.0.0.1:8766`
- Independent iOS visual audit: PASS, with evidence under
  `.codex/evidence/20260925-160942-ios-visual-audit/`

## Implementation Details

- Server-side discovery fallback now uses Claude aliases (`opus`, `fable`,
  `sonnet`, `haiku`) and Codex 5.6 compatibility IDs.
- The iOS bundled fallback mirrors those values. Older exact Claude 5 IDs remain
  accepted for persisted/transcript-derived state but are not advertised.
- `NewSessionView.start` reconciles the selected model with the selected host's
  loaded catalog or compatibility fallback immediately before constructing the
  request.
- Updated hosts relaunch an idle managed Claude pane with `--resume` and the
  requested `--model`, preserving its transcript and pane identity. Busy,
  queued, and prompt-blocked sessions return a retryable 409 instead of losing
  active work.
- Live catalog responses remain authoritative and can contain newer exact model
  IDs without requiring an app update.

## Residual Risks

- A newly installed CLI whose live catalog cannot be queried will use the
  compatibility choices until the host endpoint succeeds; this favors a chat
  that starts over advertising an unverified new ID.
- The long-lived production host must eventually restart onto this source before
  it gains live catalog discovery and reliable relaunch-based Claude switching.
  It was deliberately not restarted while other sessions were active.

## Bugs

- `bug-reports/018-model-selector-advertises-unsupported-fallbacks.md`
