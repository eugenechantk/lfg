# Feature: new-session model default per directory

## User Story

As someone starting a new session from the iOS client, I want the agent/model to
default to whatever the **last session in the directory I picked** was running, so
that I don't have to re-pick "opus" (or codex, or sonnet) every time I start work
in a project whose sessions always run on the same model.

Today the picker defaults to the *globally* last-used pair
(`AppSettings.lastNewSessionModelSelection`), which is wrong the moment you work
across two projects with different runtimes — start a codex session in repo A and
every new session in repo B silently defaults to codex too.

## User Flow

1. Open the new-session screen.
2. The directory resolves (Inbox by default, or the user picks one, or types a path).
3. The model chip shows the agent/model the newest session in **that** directory last
   ran on — live or closed.
4. If the directory has no session history at all (or none with a known model), the
   chip falls back to the previously-remembered global selection, as today.
5. If the user opens the model sheet and picks something, that pick wins — changing
   the directory afterwards does **not** overwrite it, and it is still remembered
   globally for the next new-session screen.

## Success Criteria

- [x] SC1: Given sessions in `/a` (newest = codex/`gpt-5.6-sol`) and `/b` (newest =
  claude/`opus`), selecting `/a` yields agent `codex` + model `gpt-5.6-sol`, and
  selecting `/b` yields `claude` + `opus`. — **Verify by:** LFGCore unit test
  `NewSessionModelDefaultsTests` over `AgentModelSelection.inferred(forCwd:in:fallback:)`.
- [x] SC2: A **closed** session is a valid source — the server reports `model` on
  `/api/sessions/resumable` rows and the client decodes it. — **Verify by:** bun test
  over a transcript fixture, plus an LFGCore decode test for `ResumableSession.model`.
- [x] SC3: A directory with no session history (or only sessions with no model)
  falls back to the remembered global selection. — **Verify by:** LFGCore unit test.
- [x] SC4: An explicit pick in the model sheet is not clobbered by a later directory
  change within the same draft. — **Verify by:** live simulator run: pick model →
  change directory → chip unchanged (screenshot).
- [x] SC5: Selecting a directory in the picker updates the model chip on screen. —
  **Verify by:** live simulator run on iPhone 17 Pro (screenshots before/after).
- [x] SC6: A stale/unknown persisted or inferred model never leaks into a create
  request — everything resolves through `AgentModelSelection.restoring`. —
  **Verify by:** LFGCore unit test with an unknown model string.

## Platform & Stack

- **Platform:** iOS client (`ios/`) + Bun server (`src/`)
- **Language:** Swift 6 (strict concurrency), TypeScript (Bun)
- **Key frameworks:** SwiftUI, `@Observable` `SessionStore`/`AppSettings`

## Steps to Verify

1. `cd ios/LFGCore && swift test`
2. `bun test` over the resumable suites
3. FlowDeck: build + install on `iPhone 17 Pro`, open new-session, switch directory
   between a codex-backed dir and a claude-backed dir, screenshot the model chip.

## Implementation Phases

### Phase 1: Server — model on resumable rows

- Scope: `enrichCandidate` in `src/sessions.ts` reads the transcript's last model
  (claude → `modelAlias(lastAssistantModel)`, codex → raw `lastCodexModel`, mirroring
  what `listSessions` reports for live rows) and adds it to `ResumableSession`.
- Success criteria covered: SC2.
- Verification gate: bun test with a transcript fixture.

### Phase 2: Client — decode + infer + apply

- Scope: `ResumableSession.model` decode/encode; `SessionStore.closedSession(from:)`
  carries it; new pure helper `AgentModelSelection.inferred(forCwd:in:fallback:)` in
  `LFGCore`; `NewSessionView` applies it on directory change unless the user has
  explicitly picked a model in this draft.
- Success criteria covered: SC1, SC3, SC4, SC5, SC6.
- Verification gate: `swift test` + live simulator run.

## Decision Log

- **Inference source is `store.sessions`, not a new endpoint.** The list already
  merges live + closed across every host and carries `cwd`, `agent`, `model`,
  `lastActivityAt`. No new network call, and it works offline from the persisted store.
- **Explicit pick beats directory inference, for the current draft only.** Tracked
  with a `modelPickedExplicitly` flag in the view. The alternative (always re-infer on
  directory change) would silently undo a deliberate choice, which is worse than a
  slightly stale chip.
- **Directory inference beats the remembered global pair, and does not overwrite it.**
  `noteNewSessionModelSelection` still only fires when the model *sheet* closes, so the
  global memory keeps meaning "what the user last chose", not "what was inferred".
- **Exact `cwd` match, no ancestor walk.** A session in `~/dev/foo/sub` does not seed
  the default for `~/dev/foo` — different directory, possibly different runtime, and
  the fallback is already sensible.
- **The codex model is passed through raw, claude's is aliased** — that is exactly
  what `listSessions` does for live rows (`src/sessions.ts:2615`), and both forms are
  present in `AgentKind.models`, so `restoring` validates them.

## Verification Evidence

All paths below are relative to `.claude/evidence/new-session-model-default/`.

| Criterion | Command / action | Result | Artifact |
| --- | --- | --- | --- |
| SC1, SC3, SC6 | `cd ios/LFGCore && swift test --filter NewSessionModelDefaultsTests` | 11 tests, 0 failures | — |
| regression | `cd ios/LFGCore && swift test` | 344 XCTest + 84 swift-testing, 0 failures | `swift-test-full.txt` |
| SC2 (server) | `bun test src/sessions-resumable-model.test.ts` | 3 pass — claude transcript → `opus` (newest assistant turn wins), codex rollout → raw `gpt-5.6-sol`, no-assistant-turn → `null` | `bun-test-resumable-model.txt` |
| SC2 (server regression) | `bun test src/sessions-resumable.test.ts src/sessions-resumable-closed.test.ts src/session-search.test.ts` + `bunx tsc --noEmit` | 21 pass, 0 fail; typecheck clean | `bun-test-resumable-regression.txt` |
| SC2 (real corpus) | one-off `listResumable({limit:12})` against the live `~/.claude/projects` corpus | every row now reports a model (`sonnet`); the running server's HTTP endpoint still returns `null` because it predates this change | `api-resumable-model.txt` |
| SC5 | Sim `cc-3ad32b0c` (iPhone 17 Pro, 26.3), app pointed at `http://127.0.0.1:8766`: open new session → Inbox, chip `opus` | baseline | `01-inbox-opus.jpg` |
| SC5 | pick directory `fiftyworkout` (newest session there is codex/`gpt-5.6-sol`) | chip changed `opus` → `gpt-5.6-sol` | `02-fiftyworkout-codex.jpg` |
| SC5 | pick directory `lfg` (newest session there is claude/`opus`) | chip changed `gpt-5.6-sol` → `opus` | `03-lfg-claude-opus.jpg` |
| SC4 | open model sheet → pick `claude-haiku-4-5` → Done | chip `claude-haiku-4-5` | `04-explicit-haiku.jpg` |
| SC4 | then switch directory to `fiftyworkout` (which infers codex) | directory chip `fiftyworkout`, model chip **still** `claude-haiku-4-5` | `05-explicit-survives-dir-change.jpg` |

The SC5/SC4 runs are discriminating: the pre-change build had no directory→model
path at all, so both directories would have shown the same remembered pair.

**Not verified live:** the closed-session half of SC2 end-to-end through HTTP. The
`lfg serve` process on this host is long-lived and predates the change (this repo
defers restarts because they drop in-memory session tracking), so its
`/api/sessions/resumable` still omits `model`. Server-side behaviour is proven by
the bun tests and the real-corpus probe; the client's decode of the field is
proven by `testResumableSessionDecodesModel`. The live wiring was exercised
through live rows, which carry `model` on the running server today.

## Bugs

_None open._
