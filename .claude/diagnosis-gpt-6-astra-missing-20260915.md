# Diagnosis — gpt-6-astra missing from the Codex model picker (2026-09-15)

## Finding
The option was never committed. It exists only as uncommitted edits in the main working tree:

- `ios/LFGCore/Sources/LFGCore/Models.swift` — committed list is `gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna, gpt-5.3-codex-spark`; the dirty tree prepends `gpt-6-astra` (mtime 09-07).
- `desktop/LFGSessions.swift` — same change, uncommitted (mtime 09-06).
- `ios/LFGCore/Tests/LFGCoreTests/ModelsTests.swift` — asserts the astra default, uncommitted.

## Evidence
Archives probed with `strings <app binary> | grep -c gpt-6-astra`:

| Build | Source tree | astra |
|---|---|---|
| 202609061755 … 202609130248 (all LFG builds) | dirty main tree | present |
| 202609151621 (1.3.0, today) | `.worktrees/ios-terminal` at HEAD 5ec0af1 | absent |

`.worktrees/ios-terminal/ios/fastlane/deploy-202609151620.log` confirms today's archive came from the worktree.

## Fix
Commit the three model-list hunks on main (they are small and self-contained), rebase or merge into whatever tree the next deploy archives from, and redeploy. No code regression exists.
