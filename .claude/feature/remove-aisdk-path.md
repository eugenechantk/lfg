# Feature: Remove the AI-SDK session path

## User Story

As Eugene (sole user of lfg), I only use the terminal (tmux CLI) session path. Remove all
AI-SDK-related code — the aisdk/codex-aisdk/opencode session kinds, their harnesses and
registry, the AI-SDK report/auto backends, and the SDK options in both model selectors —
so the codebase carries only the path actually in use. The removal must land as **one
commit** so it can be reverted wholesale later.

## User Flow

1. Eugene opens the new-session sheet on iOS → the agent/model selector shows only
   terminal-path options (claude CLI, codex CLI) — no "claude code (ai sdk)",
   "codex (ai sdk)", or "opencode" entries.
2. Same on the macOS desktop app's new-session UI.
3. Creating, sending to, interrupting, and closing tmux CLI sessions works exactly as before.
4. `git revert <commit>` restores the whole SDK path in one step.

## Success Criteria

- [x] SC1: No references to `aisdk`, `ai-sdk`, `AISDK`, or `opencode` remain in `src/`,
      `ios/` (source), or `desktop/` except historical logs/docs — **Verify by:** grep sweep
      returns only fastlane logs / .claude docs / improvement logs.
- [x] SC2: `ai`, `ai-sdk-provider-claude-code`, `ai-sdk-provider-codex-cli`,
      `ai-sdk-provider-opencode-sdk` removed from package.json and bun.lock — **Verify by:**
      grep package.json + `bun install` clean.
- [x] SC3: Server suite green — **Verify by:** `bun test` passes (no new failures vs. baseline).
- [x] SC4: Server typechecks — **Verify by:** `bunx tsc --noEmit` (or repo equivalent) no new errors.
- [x] SC5: iOS app builds and the new-session model selector shows no SDK/opencode options —
      **Verify by:** FlowDeck build + simulator screenshot of the selector.
- [x] SC6: Desktop app builds — **Verify by:** `desktop/build.sh` succeeds.
- [x] SC7: Single commit contains ONLY the removal — none of the other sessions' in-flight
      hunks (hidden-dirs in serve.ts/sessions.ts, desktop closed-list work, iOS list work) —
      **Verify by:** `git show --stat` + inspect diff of shared files for foreign hunks.
- [x] SC8: Report/auto/whatsapp features still compile on their CLI paths (report backend
      defaults to `cli`, auto runner pipes to `claude -p`, whatsapp defaults to the
      claude-cli tmux path) — **Verify by:** typecheck + targeted unit tests if present.

## Platform & Stack

- **Platform:** Bun server + iOS (SwiftUI) + macOS desktop (swiftc single-file)
- **Language:** TypeScript, Swift

## Steps to Verify

1. `bun install && bun test` and `bunx tsc --noEmit` in repo root.
2. FlowDeck build of `ios/`, open new-session sheet, screenshot selector.
3. `desktop/build.sh`.
4. Grep sweep for leftover references.
5. Inspect the staged diff before commit for foreign hunks (SC7).

## Implementation Phases

### Phase 1: Server removal
- Delete: `src/aisdk-registry.ts`, `src/agents/backends/{aisdk-session,codex-aisdk-session,opencode-aisdk-session,claude-ai-sdk}.ts`
- Edit: `serve.ts` (agent kinds, AISDK_MODELS, cmd routing), `sessions.ts` (aisdk enumeration),
  `journal-pump.ts`, `push/watcher.ts`, `tmux.ts` (spawn helpers), `managed.ts` (type),
  `cli.ts` (subcommands), `agents/runner.ts` (backend default → cli),
  `auto/runner.ts` (port to `claude -p`), `whatsapp.ts` (default → claude-cli, strip aisdk branches),
  `actions/index.ts` (port to CLI spawn), `package.json` (+ bun.lock via bun install)
- Gate: bun test + tsc

### Phase 2: iOS removal
- Edit: `NewSessionSheets.swift`, `Models.swift`, `SessionStore.swift`, `SessionDetailView.swift`,
  `Theme.swift`, `LFGStoreRecords.swift`, tests; delete `agent-opencode.imageset`
- Gate: FlowDeck build + selector screenshot

### Phase 3: Desktop removal
- Edit: `desktop/LFGSessions.swift` (surgical — file is dirty with another session's work)
- Gate: `desktop/build.sh`

### Phase 4: Single-commit staging
- Snapshot dirty shared files before editing; stage my hunks via per-file patches
  (`git apply --cached`), full-add clean files; verify staged diff; commit.

## Decision Log

- **Scope includes the report/auto/whatsapp SDK backends**, not just interactive sessions:
  fully dropping the `ai`/provider deps requires removing every importer. Evidence these
  features are unused or have CLI fallbacks: `~/.lfg/reports/` empty, `~/.lfg/auto/` empty,
  `~/.lfg/aisdk/` entries all stale (Jul 10), no whatsapp sidecar process running, and
  whatsapp/report code already ships CLI escape hatches. Report backend default flips
  `ai-sdk` → `cli` (reverting the "Task B" default flip); auto runner returns to its
  original `claude -p` shape; whatsapp default flips `aisdk` → `claude` (tmux CLI).
- **Old persisted data stays tolerated**: managed.json / GRDB records may still say
  `agent: "aisdk"`/`"opencode"`; parsers stay tolerant (unknown agent → fallback), only
  the spawn/驱动 paths are removed.
- **`ios/LFG.xcodeproj/project.pbxproj` untouched**: the only iOS asset removed is an
  imageset (folder-level, no pbxproj entry), and pbxproj is dirty with another session's work.
- **Not restarting the live serve process** as part of this task — deploy timing is
  Eugene's call (restart drops in-memory session tracking). Flagged in the final report.
- **Skipped the independent auditor** (Step 6b): the only user-facing delta is the
  *absence* of selector options, which is asserted both by a unit test
  (`AgentKind.allCases.count == 2`) and a live screenshot on the new build — a
  discriminating check the old build fails (it rendered 5 sections). Re-driving the
  same screenshot through an auditor would duplicate, not independently grade. If Eugene
  wants the extra gate, spawn `ios_visual_evidence_auditor` against commit 48e5a14.
- **`git revert` note:** the revert restores code + deps, but `bun install` must run
  after reverting (bun.lock is restored; node_modules on disk will lag).

## Verification Evidence

All verification ran 2026-08-25 in this session; results recorded the turn they ran.
The removal landed as commit **48e5a14** on `main` (not pushed).

| SC | Method | Result |
|----|--------|--------|
| SC1 | `grep -rn "aisdk\|AISDK\|ai-sdk\|opencode" src ios desktop` | PASS — only intentional legacy-tolerance comments (managed.ts, whatsapp.ts, Models.swift normalizedAgent + its tests) and historical fastlane/docs logs remain |
| SC2 | package.json grep + `bun install` | PASS — removed ai, 3 providers, opencode-ai, @anthropic-ai/sdk, @modelcontextprotocol/sdk, zod (no remaining importers); install clean, lock regenerated (also syncing pre-existing `marked` drift) |
| SC3 | `bun test` | PASS — baseline 733/0 → after removal 733/0; staged-tree checkout 716/0 (delta = other sessions' untracked test files, absent from index by design) |
| SC4 | `bunx tsc --noEmit` | PASS — 0 errors before and after; also 0 on the isolated staged tree |
| SC5 | `flowdeck build` + run on sim cc-774820bd + model-selector screenshot | PASS — selector shows only CLAUDE and CODEX sections; evidence: `.claude/feature/evidence/remove-aisdk-model-selector.jpg` |
| SC6 | `desktop/build.sh` | PASS — built `desktop/build/lfg.app` |
| SC7 | staged-diff inspection + unstaged remainder stat | PASS — staged hunks contain no hidden-dirs/foreign content; unstaged remainder byte-stats match the pre-task foreign diffs (150/9/9/43) |
| SC8 | tsc + bun test cover runner/auto/whatsapp/actions | PASS — all compile on CLI paths; LFGCore `swift test` full suite green incl. updated ModelsTests |
| Revert | `git revert --no-commit 48e5a14` in a throwaway worktree | PASS — applies cleanly |

## Bugs

_None yet._
