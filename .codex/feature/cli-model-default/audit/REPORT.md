# Independent audit of CLI defaults

Result: PASS for host behavior and core selection policy. Native visual verification and deployment of this policy are outside this audit.

## Independent checks

- Existing targeted host regressions independently rerun: 58 tests pass with 202 assertions. Evidence: regression-output.txt.

- Host adversarial suite: nineteen tests pass with 115 assertions after the repairs. Evidence: independent.test.ts and independent-output.txt.
- Claude actual resume/fork helper code was extracted from serve.ts, transpiled, and executed with mocked effects. Empty Default omits the override; omission preserves the prior transcript model; explicit choices remain pinned. Both keep the transcript directory.
- Fresh Claude and Codex argv retain their directory and omit --model for empty or unspecified models. Explicit model flags survive fresh launch and fork.
- A fake read-only Codex app-server verifies config/read receives each target directory. Each directory's configured model beats the provider recommendation. No configuration write occurs.
- Configured model metadata survives a persisted catalog round-trip even when the configured ID is absent from the visible list.
- Independent Swift core suite: four tests pass. It uses exact copies of the production policy sources; hashes are stored in CoreAudit/source-hashes.json. SessionFixture.swift supplies only the four data fields consumed by directory inference.
- Swift checks cover Default across repeated catalog changes and persistence, directory changes without pinning, explicit choices remaining pinned, and hidden configured defaults and labels.

## Findings and repair status

- Fixed during audit: TypeScript saved-catalog sanitation and Swift defaultModel(for:) originally replaced an unadvertised configured model with the first visible model. The configured model now survives; independent tests pass.
- Fixed during audit: Codex native and external forks originally treated empty Default like omission. Both now resolve the project CLI setting before fork effects. Omitted models retain native inheritance; explicit choices stay pinned. Four independent tests cover both branches and failed resolution with zero fork effects. Evidence: fork-red.txt and independent-output.txt.
- Fixed during audit: config/read JSON-RPC errors originally fell through to the provider recommendation. Resolution now returns null; the Default operation can fail before effects. An independent fake-protocol test reproduces the original failure and passes after repair. Evidence: config-error-red.txt and independent-output.txt.
- Independently executed the actual model endpoint block with mocked effects. Empty Default survives JSON parsing, Codex resolves the session directory, Claude relaunch omits a model pin, explicit choices stay explicit, and absent model is rejected before effects.

## Limits

- Native UI is assigned to a separate audit. This report does not claim visual verification.
- No live sessions were started, changed, stopped, or restarted by this audit. Effects in host helper tests are mocks.
- Codex resume intentionally starts without --model. The client follows a closed-session model selection with setModel, including Default; this wiring was inspected.
- This audit has not verified a deployed host containing the current policy changes.
