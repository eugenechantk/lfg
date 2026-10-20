# Account usage limits

Tier: product. Approved design: `.codex/design/account-usage-limits/design.md`, canvas page **Usage limits (Oct 20)**.

## User story and flow

Eugene opens **Usage limits** from the session list menu to compare the signed-in Claude Code and Codex accounts. iPhone and iPad present a sheet; Mac presents a popover. Refresh updates all configured hosts without hiding prior readings. Close returns to the session list.

## Success criteria

- [x] SC1: The host returns real quota windows for both providers without exposing credentials or starting model turns. Verify: provider parser tests and a live read-only probe.
- [x] SC2: Missing windows stay unknown, API billing has no bars, durations determine labels, and only proven account identities merge across hosts. Verify: Bun and Swift tests.
- [x] SC3: Refresh preserves prior values, failed/offline hosts retain dated readings, and account changes do not inherit another account's usage. Verify: cache and aggregation sequence tests.
- [x] SC4: The menu entry and approved native presentation work on iPhone, iPad, and Mac, including refresh, scrolling, dismissal, light/dark, and error states. Verify: running app captures and independent visual audit against the approved boards.
- [x] SC5: Code receives three explicit review passes before the visual verifier starts. Verify: review ledger below.

## Implementation

- Add a read-only, bounded host usage service and API. Use current macOS Keychain credentials for Claude; the old credentials file is expired. Keep file fallback for other hosts. Do not explicitly change provider credentials. Codex uses its own account protocol for reads.
- Read Codex account/rate limits through a temporary app-server, without thread operations.
- Share the transport models, account aggregation, formatter, and refresh state between the Apple clients. Share native account cards while adapting presentation and metrics per platform.
- All product numbers come from providers. Sample data is restricted to an explicit development fixture.
- Preserve unrelated dirty files. Do not commit, push, release, or replace the production host during this implementation task.

## Tests and evidence

Bun: 22 tests pass across account usage, app-server and model catalog suites; TypeScript no-emit check passes. Swift: 502 tests pass in 76 suites, including 12 account usage tests. Evidence: `account-usage-host-tests.txt`, `account-usage-types.txt`, `account-usage-swift-full.txt`. Native iPhone/iPad and Mac builds pass. A live read-only probe returned both providers with real windows and proven identities (`account-usage-live-proof.txt`).

## Triple code review

1. PASS: Authentication and protocol review. Read the full host service and API route. Current Claude Keychain takes precedence over an expired legacy file; API contexts have no subscription bars. Codex only proves file identity after reading the active CLI credential-store setting and matching its account. Failed unproved reads leave identity unknown. Token-scoped bounded caches, fixed read methods, process hard deadlines and cleanup were checked. No credentials enter response payloads or errors. Fixed unknown-identity failure attribution and strengthened the Keychain deadline. Relevant Bun and type checks pass.
2. PASS: State review. Read the full shared models/store and sequence tests. Refresh retains numbers, provider errors retain only the same proven account, host failures retain dated snapshots, removed hosts are pruned, and generation/cancellation guards reject late responses. Unknown identities stay separate. Verified tests for parallel cache reads, credential changes, host changes, in-flight values and network failure. Swift tests pass.
3. PASS: UI and integration review. Read the full shared SwiftUI view plus each menu/client/build change and scoped git diff. Checked fitted iPhone/iPad sizing, measured Mac height with 520pt cap, scrolling, unknown windows without bars, warning words, API notices, refreshing values, Dynamic Type, 44pt iOS actions, combined quota labels, identifier containment, Escape and Command-R. Fixed Mac content fitting and warning copy when reset times are absent. Generated iOS project uses project.yml. Unrelated dirty changes are preserved. Native builds and git diff --check pass. Independent visual verification follows these passes.

All three passes finished before spawning the independent auditors. A final acceptance check then found that synthetic missing-window placeholders displayed an assumed duration. The formatter now omits the duration only for explicit placeholders; reported durations stay visible. Added a regression test. Repeated passes 1–3 for this correction: confirmed the host placeholder contract, state isolation and missing-value behavior, and shared native/VoiceOver copy. Swift 497-test run and diff check pass before requesting fresh final visual captures. The source snapshot is `account-usage-review-hashes.txt`. Recheck affected passes if an auditor requires a code change.

The independent design reviewer then found Mac quota labels visually heavier than the reference. Explicit regular weight now applies to the label only; percentage weight is unchanged. Repeated pass 3 for this focused text-style change. Passes 1 and 2 are unaffected. The same review found an absent error outline and a plain retry link where the design uses a filled control. Added the red outline and a toned capsule for Try again, with a 44pt iOS target. Notice accessibility containment preserves the button identifier. Repeated the full shared-view pass 3 after the complete correction batch; passes 1 and 2 remain valid. All data, caches, identity and formatting code are unchanged. Fresh native captures are required before clearing these findings.

The reviewer withdrew the label-weight finding after measuring control text: native and browser font rasterization differs throughout. Explicit regular weight remains; no lighter font workaround is used. Error outline and retry surface passed fresh native checks.

An actual stopped-host check found an integration bug missed by direct URLError tests. The iOS client wrapped transport failures as LFGError.notReachable. The scoped accountUsage read now maps network errors for the shared offline classifier, while HTTP/provider errors keep their original type. A URLProtocol test composes the real LFGClient and store, asserting retained values and offline state. The full current package run passes 502 tests in 76 suites. Repeated all affected review passes: transport mapping exposes no diagnostics/credentials; HTTP errors remain distinct; cancellation stays cancellation; retained snapshots and account grouping remain intact; plural offline copy and shared dimming/provenance are checked. Diff check passes before final native re-capture.

## Verification evidence

- Independent iOS visual evidence auditor: PASS, `.codex/evidence/20261020-235132-ios-visual-audit/evidence.md`. Final full-flow recording: `37-core-flow-refresh-retention-ultimate-final.mov`. Covers iPhone/iPad, light/dark, Accessibility XL, refresh retention, unknown/API/error/identity states, actual stopped-host offline data retention and Try again recovery.
- Independent design comparison: PASS, final report at `.codex/evidence/account-usage-design-verifier/evidence.md`; 55 measured component pairs preserve findings, corrections and explicit carryovers. Native Mac normal/error controls and actual stopped-host offline appearance pass fresh checks. No confirmed visual mismatch remains.
- Code: three review passes before visual verification, followed by affected-pass rechecks for findings. Source hashes in `account-usage-review-hashes.txt`.
- Tests/builds: 22 relevant Bun tests, TypeScript no-emit check, 502 current Swift tests in 76 suites, final native iOS and Mac builds, final custom desktop build and diff check pass. Live sanitized provider proof in `account-usage-live-proof.txt`.

The implementation review finished locally. The user then authorized a commit and a new build. Release 1.4.1 (202610210031) reached internal TestFlight, and the Pro desktop app was installed and launched. Both hosts now serve the usage endpoint while preserving their other live changes. The signed Air desktop app is staged but was not installed or launched because its screen is locked and its unlock plug-in is absent. Release evidence and remaining Air limitations are recorded in `.codex/releases/202610210031.md`.

## Residual risks

Live provider endpoints and auth storage can change. The UI reports missing or unavailable data honestly. Command-R injection, full keyboard focus order and spoken VoiceOver output were not verified; they are outside the visual PASS. During the release check, Pro returned successful readings for both providers; Air returned explicit provider read failures. Audit apps/servers are stopped and the Pro screen lock is restored.

## Bugs

Closed during implementation/verification: unproved Codex identity on initial read failure; assumed duration on an absent window; missing error outline/retry surface; iOS transport errors missing the offline classifier. The apparent Mac label weight mismatch was withdrawn after control measurements showed systematic native/browser font rasterization. No remaining confirmed implementation bugs.
