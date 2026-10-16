# Forked sessions start idle

Tier: product. Platforms: TypeScript host and Swift iOS client.

## User story

After a successful fork on the phone, Eugene can send a follow-up immediately.
The branch shows idle until it receives its own message.

## User flow

1. Open a Claude or Codex conversation.
2. Choose Fork session.
3. Open the successful branch with an idle status and a writable composer.
4. Send a follow-up. The branch runs the message and returns to idle.

## Success criteria

- [x] SC1: Successful fork navigation clears stale activity and source work in the phone's state. Verify with Swift regression tests and a simulator recording.
- [x] SC2: A fresh Codex branch reports idle before its first turn, including REST and journal consumers. Verify with turn-state tests and a disposable real fork.
- [x] SC3: The branch accepts its first follow-up and reports real activity normally. Verify with lifecycle regression tests and a recorded simulator flow through the real host.
- [x] SC4: The source keeps its state and history. Verify with regression tests and source/branch API snapshots.
- [x] SC5: Relevant tests and independent verification pass. Verify with Bun, Swift package tests, the iOS build, and the visual auditor.

## Test strategy

Cover stale activity after fork success, inherited child work, prompt clearing,
fresh Codex metadata without a turn, and the first real branch turn.
Use a disposable source and branch for runtime checks.

## Decision log

- Keep the existing fork API and provider fork behavior.
- Do not change active user conversations or deploy a release without authorization.
- Save this task's evidence under `.codex/evidence/fork-session-idle/`.
- Keep separate state for the test host, with this Mac's real host identity. A new identity on the same Mac conflicts with the production lease heartbeat.

## Verification evidence

- Before the fix, a disposable Codex fork returned success but three consecutive real API snapshots reported `busy: true`. Its rollout contained only `session_meta` and `thread_settings_applied`.
- After the fix, the same disposable source produced a distinct fork. Three consecutive snapshots from the isolated real host reported `busy: false` and a usable tmux target.
- `bun test` on nine focused suites: 133 passed, zero failed. The two new fork cases failed before the implementation. The shared journal and push observation test also proves idle, running, then idle on the branch's own lifecycle.
- `swift test --package-path ios/LFGCore`: 645 XCTest cases, one skipped, zero failures; 426 Swift Testing cases passed. The inherited-work regression failed before the implementation.
- `bunx tsc --noEmit`: passed.
- `flowdeck build`: passed. A previous build guard stopped on a process-monitor timeout; process enumeration recovered and a deliberate guard reset allowed the build.
- Runtime and test outputs: `.codex/evidence/fork-session-idle/`.
- A disposable Claude fork reported idle, accepted one follow-up, ran it, replied `CLAUDE_FORK_IDLE_OK`, and returned to idle. Evidence: `claude-fork.json`, `claude-idle.json`, `claude-send.json`, `claude-after.json`, and `claude-messages.json`.
- The first simulator fork attempt returned 409 because the test host used a different machine identity. The test state's `host-id` now matches this Mac. Both `/api/info` responses agree; production state and code were not changed. Evidence: `harness-identity-alignment.json`.
- Independent iOS auditor: PASS. The simulator opened a distinct Codex branch, stayed idle across three reads, accepted its first follow-up, replied in 2.143 seconds, and returned to idle. The source transcript's byte count and SHA-256 stayed identical. Report: `audit/evidence.md`; recording: `audit/fork-idle-followup-success.mov`.
- The Codex reply completed before a REST sample could capture busy. Lifecycle tests cover that transition; the Claude live probe captured busy during its turn.
- All disposable branches and the test source were closed. The isolated server was stopped. No production server restart, physical phone install, TestFlight upload, commit, or push occurred.

## Release scope

Verified against the updated source and a simulator build using an isolated local
host. Production hosts and the app installed on the physical phone still need the
updated host code and app build.

## Recheck on 16 October 2026

The requested fix was already present when this turn began. No additional
product code changes were needed.

- Nine focused host suites passed: 128 tests, zero failures. Output:
  `.codex/evidence/fork-session-idle/recheck-bun-20261016-2018.txt`.
- `swift test --package-path ios/LFGCore --filter ModelsTests` passed:
  21 tests, zero failures. This includes both fork regressions. Output:
  `.codex/evidence/fork-session-idle/recheck-swift-20261016-2018.txt`.
- `bunx tsc --noEmit` passed. The relevant source diff has no whitespace errors.
- The fork implementation files predate the existing independent simulator
  audit. Its recorded end-to-end result remains applicable to these files.
- No host deployment, physical phone install, release, commit, or push occurred
  during this recheck.

## Bugs

All identified bugs are resolved:

- The fork success path now clears both the row and the store's separate busy value.
- The immediate branch row clears inherited child agents and background work.
- Codex fork metadata now defines an idle boundary until the first real turn.
