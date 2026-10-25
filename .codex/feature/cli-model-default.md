# CLI model defaults

## User story

The CLI owns its default model. LFG offers Default alongside explicit models and preserves that policy until launch.

## Success criteria

- [x] SC1: Default remains selected across catalog refresh, settings restore, and creation. Verify LFGCore tests.
- [x] SC2: Default launches the CLI without a model override; explicit choices remain pinned. Verify host argv/API tests.
- [x] SC3: New-session and session model selectors show Default for each tool. Verify simulator recording and independent audit.
- [x] SC4: The model catalog reports the CLI-configured default rather than a hardcoded preferred model. Verify parser tests and a live read-only discovery.

## Decisions

Use an empty model value for Default, matching the existing scheduled-task selectors. Keep explicit existing model choices intact. Default on an existing session applies the CLI setting when selected; future launches use the current CLI setting.

## Verification evidence

- Model regressions pass: 60 tests and 207 assertions. The isolated host release passes 145 tests and 395 assertions. TypeScript validation passes.
- Independent audit passes 19 adversarial host tests and 115 assertions, plus four independent Swift core tests. Evidence: cli-model-default/audit/REPORT.md.
- The full package passed 649 XCTest cases (one skipped) and 501 Swift Testing checks. The desktop build passed 259 feature checks. Independent iOS visual audit passed every criterion.
- Live read-only discovery returned Codex 0.163.0 and configured default gpt-6.1-sol. This uses config/read, not a hardcoded preference.

## Audit repairs

Preserve a configured model absent from the visible recommendation list through caching and Swift decoding. A failed config/read must not fall back to a guessed provider recommendation during a model switch. Explicit Default on either Codex fork path resolves configuration before creating the fork; a lookup failure creates nothing.

## Runtime

Host support is deployed on Pro and Air. Both verified 278 source files and preserved sessions and schedules. The staged source excludes concurrent account-usage and other unrelated edits. Client binaries are built for verification; they are not installed into the user applications or released to TestFlight. Fixture verification passed.

## Visual correction

The picker uses fixed dark design tokens. Its nested native sheet was resolving a light material. Apply the existing dark appearance to the shared picker scaffold so Default and all other model rows remain readable. No new material or layout was introduced.

## Final evidence

- Independent visual audit: .codex/evidence/cli-model-default-visual/evidence.md. Recorded selecting Codex Default, reopening after catalog refresh, retaining explicit alternatives, and sending empty model values for both new and existing sessions.
- Pro and Air live checks passed: healthy APIs, CLI-reported model, acceptance of empty model requests, and all 278 source files matched. Evidence: cli-model-default/pro-live.json and cli-model-default/air-live.txt.
- No production agent was created or switched for verification. Native UI requests used isolated fixture hosts; host argv/protocol tests and read-only CLI discovery verified the execution boundary.
- No commit, push, installed-client replacement, or TestFlight release occurred.
