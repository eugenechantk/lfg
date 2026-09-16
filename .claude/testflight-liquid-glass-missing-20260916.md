# TestFlight: Liquid Glass and gradient overlay missing — 2026-09-16

## Root cause

The 1.3.0 build on TestFlight (build `202609151729`, archived 2026-09-15 17:29) was built from the clean
`.worktrees/ios-terminal` checkout at `main` HEAD (`d08593d`). The Liquid Glass nav bar, glass composer
and gradient top fade (`.codex/feature/session-liquid-glass-chrome.md`, Sept 12–15) lived only as
**uncommitted edits in the main tree** (`SessionDetailView.swift`, `MessageComposer.swift`,
`SessionStore.swift`), so the worktree never had them. Same failure class as the gpt-6-astra regression
the day before (memory `clean-worktree-build-drops-dirty-tree-features`).

Evidence: `~/Library/Logs/gym/LFG-LFG.log` names the ios-terminal worktree project path; the archived
binary contains no `topChromeFade`/`SessionNavigationBarBackdropVisibility` symbols; every glass hunk was
in `git diff -- ios` and none in `git log`.

## What was done

1. Verified the dirty tree: LFGCore `swift test` (524 XCTest + 144 Swift Testing, 0 failures); targeted
   `bun test` over the 28 server files covering the changed code (235 pass). The full `bun test` hangs
   after `codex-bin.test.ts` and was killed at 10 min — logged, not fixed.
2. Regenerated `project.pbxproj` with xcodegen so its diff was only the three new source files (the
   Manual/Apple Distribution lines were deploy residue).
3. Committed the whole dirty tree as revert-safe groups, hunk-split by feature (helper:
   scratchpad `stage_hunks.py`, keyed on `-U2` new-file hunk starts):
   - server: hidden dirs, Codex user turns, absorbed-mid-turn sendq, child agents on row, async
     receipts, codex resume fails loudly, offline-host transfer, composer border parse, autopilot env
     scrub, docs
   - ios: attachments, child agents, idle status, codex resume settle, hidden dirs, transfer, background
     crash, send-error relevance, select-text + tables, **Liquid Glass + keyboard-stable transcript +
     scrubber** (one commit; hunks interleave), fixtures + project
   - docs: feature docs/diagnoses, evidence (videos and .log files left untracked per .gitignore), bug
     reports 011–017, improvement logs through 09-15
4. Pushed `main` (`e72b400..319cc71`).
5. Archived from the **main tree** with `bundle exec fastlane ios deploy_testflight` → build
   `202609162032` on the 1.3.0 train.

## Deliberately left uncommitted

- `desktop/LFGSessions.swift`, `desktop/build.sh`, `.claude/diagnosis-desktop-open-bounds-of-missing-value-20260916.md`
  and the matching iTerm hazard line in `.claude/CLAUDE.md`: another live session (tmux
  `cy-000500-3409`) owns them and has "commit the desktop fix" waiting in its composer.
- `.claude/evidence/**/*.mov` (repo convention: no evidence videos tracked) and the two live
  improvement logs from today.
- `ios/LFG.xcodeproj/project.pbxproj` signing residue re-applied by the deploy lane.

## Caveats

- Intermediate commits were not individually built. Two are known not to build the app target alone:
  the select-text commit ships `SelectableProse.swift` before the project commit registers it (an
  `xcodegen generate` at that commit fixes it). HEAD builds and tests green.

## Build verification

`bundle exec fastlane ios verify_testflight_build build_number:202609162032` — DoD PASS:
ipa carries CFBundleVersion=202609162032 v1.3.0; App Store Connect processingState VALID (20:42);
train 1.3.0 is the highest; internalBuildState IN_BETA_TESTING. Logs:
`ios/fastlane/deploy-202609162032.log`, `ios/fastlane/verify-202609162032.log`.

Not yet checked: the glass chrome on a device. The build carries the code (commit `2f087cf`); install
it from TestFlight and open a session to confirm the nav bar and composer render as glass with the
gradient fade.

## Follow-up build

Build `202609162053` (20:53, same iOS code; cut after the desktop and docs commits at Eugene's request) — DoD PASS: VALID on train 1.3.0, IN_BETA_TESTING. Logs: `ios/fastlane/deploy-202609162053.log`, `ios/fastlane/verify-202609162053.log`.
