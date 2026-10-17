# Model provider icons

## Request

Use the Claude and Codex icons beside models in the session More menu. Check mobile task views and fix any missing provider icons.

## Success Criteria

- [x] The session More model row uses the actual Claude logo instead of the letter C. Verify with an iPhone screenshot.
- [x] The session More model row still uses the actual Codex logo. Verify with an iPhone screenshot.
- [x] Mobile task headers show the matching Claude or Codex logo beside their model. Verify both providers with screenshots.
- [x] Both logos remain legible in light and dark appearance. Verify with screenshots.

## Decisions

- Reuse the existing vector assets; do not create new brand images.
- Task headers already use both vector assets through TaskAgentMark. Preserve that implementation and verify its rendering.
- This is a reversible visual-only change. Do not add tests that merely check image names; verify the rendered icons.
- Preserve the session-to-task feature and unrelated working-tree edits. Do not commit or release.

## Verification Evidence

- `flowdeck build --json`: passed at 16:17:00 UTC. Log: `.codex/feature/model-provider-icons-build.jsonl`.
- `swift test --package-path ios/LFGCore --filter SessionSheetModelTests`: 6 tests passed. Log: `.codex/feature/model-provider-icons-tests.log`.
- Synthetic fixture returns Claude/Opus on Pro and Codex/GPT-6.1 Sol on Air, for both sessions and tasks. No production API is used for verification.
- Independent iPhone 17 Pro inspection passed for both providers in light and dark mode. Evidence: `.codex/evidence/model-provider-icons-20261017/ios-audit/light/` and `dark/`.
- Parent inspected the Claude More row in both appearances, Claude task chip, Codex More row in dark mode, and Codex task chip in light mode. All use the matching bundled logo.
- Independent audit: PASS for all eight provider/surface/appearance combinations. Report: `.codex/evidence/model-provider-icons-20261017/ios-audit/evidence.md`.
- Cleanup: the auditor restored light appearance and stopped capture. Parent verified/stopped synthetic fixture PID 11880; ports 18891 and 18892 have no listeners. `git diff --check` passed. No commit or release was made.

## Residual Risks

Verification used an iPhone 17 Pro simulator and synthetic hosts. Physical devices and production sessions were not exercised.
