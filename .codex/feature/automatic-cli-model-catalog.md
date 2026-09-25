# Feature: Automatic CLI Model Catalog

## User Story

As an LFG user, I want the Claude Code and Codex model selectors to reflect the
models offered by the installed CLIs so a CLI update does not require an LFG
code change or release just to expose new models.

## User Flow

1. Update Claude Code or Codex on an LFG host.
2. Open the new-session model selector or a session's Switch model menu.
3. LFG asks the relevant host for its current CLI model catalog.
4. The selector shows the host's currently offered Claude Code and Codex models.
5. Pick a newly discovered model and create, resume, hand off, or switch the
   session normally.

## Success Criteria

- [x] SC1: The host returns the visible model IDs and defaults from the installed
  Claude Code and Codex catalogs, together with their CLI versions. — **Verify
  by:** Bun parser/discovery tests plus a live `GET /api/models` response.
- [x] SC2: Catalog discovery failure never removes the selectors; LFG falls back
  to its bundled safe catalog. — **Verify by:** Bun fallback tests and Swift
  decoding/fallback tests.
- [x] SC3: The new-session selector refreshes from the selected host and the
  in-session selector uses the session-owning host's catalog. — **Verify by:**
  Swift tests for catalog lookup/section ordering and simulator interaction.
- [x] SC4: Newly discovered safe model IDs are accepted by the host and survive
  the app's persisted last-selection restore. — **Verify by:** Bun validation
  tests and Swift selection-restore tests.
- [x] SC5: The running iOS app visibly offers the newly installed Claude Code
  and Codex models without hardcoded client changes. — **Verify by:** FlowDeck
  recording/screenshots and independent iOS visual audit.

## Test Strategy

- Bun unit tests cover Claude cache parsing, Codex app-server JSONL parsing,
  default selection, deduplication, validation, and fallbacks.
- LFGCore Swift tests cover lenient API decoding, host catalog lookup, fallback,
  dynamic handoff sections, and persistence of syntactically safe future IDs.
- A live host probe verifies the real installed Claude Code and Codex versions
  and model response.
- Simulator evidence exercises the real new-session selector and session switch
  menu against that host.

## Tests

- `src/model-catalog.test.ts`
  - parses the Claude Code model-catalog cache's visible main models — SC1
  - parses Codex `model/list` JSONL and keeps provider order/default — SC1
  - rejects unsafe model IDs and supplies bundled fallbacks — SC2, SC4
- `ios/LFGCore/Tests/LFGCoreTests/ModelsTests.swift`
  - decodes current and partial catalog responses leniently — SC2, SC3
  - preserves safe future persisted model IDs until host reconciliation — SC4
- `ios/LFGCore/Tests/LFGCoreTests/SessionHandoffTests.swift`
  - injects host models while preserving current-tool-first grouping — SC3

## Implementation Details

- Add `GET /api/models` on each host.
- Read Claude Code's own freshest account-scoped model-catalog cache, preferring
  its `main` entries and current state default.
- Ask the newest installed Codex binary's app-server for `model/list`; exclude
  hidden models and retain the provider's default/order.
- Cache discovery briefly to avoid subprocess churn on Bun's single event loop;
  opening a selector explicitly refreshes it, so CLI changes become visible
  without an LFG release.
- Keep bundled catalogs in the server and client as compatibility fallbacks for
  old/unreachable hosts and discovery failures.
- Validate all externally supplied model IDs with a strict non-shell model-name
  grammar instead of a release-bound Claude allowlist.

## Residual Risks

- Claude Code does not expose a documented model-list command. Its own
  account-scoped model-catalog cache is the least invasive source of truth; if
  Anthropic changes that cache shape, LFG will safely fall back until adapted.
- Hosts running an older LFG server have no `/api/models`; clients continue to
  show the bundled fallback catalog for those hosts.

## Decision Log

- Use provider-owned catalogs rather than version-to-model tables. Version
  tables would still require an LFG update for every future release.
- Scope Claude choices to the catalog's `main` section, matching Claude Code's
  normal `/model` picker instead of surfacing retired overflow entries.
- Preserve raw model IDs in LFG's existing UI; no model-name redesign is needed
  for automatic updates.

## Verification Evidence

- Live `GET /api/models?refresh=1` on an isolated host returned Claude Code
  `2.1.280` and Codex `0.156.0`, including Opus 5.5, Fable 5.1, GPT-6 Sol, and
  GPT-6 Luna.
- `bun test src/model-catalog.test.ts` passed 4/4 tests; `bunx tsc --noEmit`
  passed; the full Bun suite passed 998 tests across 90 files.
- Focused model/handoff Swift tests passed 21/21; the full LFGCore suite passed
  191 Swift Testing tests plus its XCTest suites.
- `flowdeck build` succeeded on dedicated simulator
  `71442893-3249-4AE6-AE32-7E64D09AB374`.
- FlowDeck runtime inspection showed the live discovered catalog in New Session
  and current Claude/Codex groups in an existing session's Switch model menu.
- Independent iOS visual audit: PASS. Evidence is in
  `.codex/evidence/automatic-cli-model-catalog/`.

## Bugs

- The first audit found `gpt-5.5` missing from the existing-session UIMenu
  because four accepted legacy Claude aliases consumed limited menu slots.
  Fixed by keeping aliases valid for persisted/transcript compatibility while
  excluding them from picker catalogs; the focused re-audit passed.
