# Build/test memory guard and optional diagnostics

## Intent

Protect Eugene's 36 GiB Pro from another Xcode diagnostic collection runaway. Ordinary tests keep assertions and failure results; heavyweight diagnostics default off and agents may enable them per run when useful. Global simulator debug logging stays off outside an explicitly bounded diagnostic window.

## Success criteria

- [x] SC1: Routine FlowDeck tests receive `-collect-test-diagnostics never`; an explicit per-run choice of `on-failure` works and other arguments are preserved. Verify unit tests and a fake-vendor integration run.
- [x] SC2: Build/run/test jobs have a 12 GiB physical-footprint limit covering their process group and observed descendants, sampled every second. Verify native accounting and a small-limit real allocation fixture, including child cleanup and an unrelated survivor.
- [x] SC3: Only one guarded heavy job runs at a time across sessions; memory failure blocks automatic subsequent jobs until reset. Cancellation releases the slot and cleans up owned children. Verify competing processes and cancellation fixtures.
- [x] SC4: Diagnostics-enabled jobs cannot start or continue with oversized CoreSimulator logs; routine tests pass Xcode's `-collect-test-diagnostics never` to disable verbose long-running diagnostics. Verify file-size preflight, growth and argument fixtures. Archive the incident log reversibly outside CoreSimulator collection paths and verify its identity. This option does not establish that every xcresult attachment is omitted.
- [x] SC5: Installed FlowDeck entrypoint runs the guard; non-build commands remain usable; durable bounded status/evidence identifies job ownership. Verify installed entrypoint, status, fake-vendor tests and independent CLI audit.
- [x] SC6: Claude/Codex skills document both diagnostics choices, agent discretion, global logging cleanup, and the guard's limitations. Verify links and review the actual instructions.

## Implementation

Python standard-library supervisor in `scripts/build_guard.py`, tests in `scripts/test_build_guard.py`, installer in `scripts/install-build-guard.py`. Install a stable copy under `~/.local/lib/lfg-build-guard/` and a small shim at the existing `~/.local/bin/flowdeck`; retain the vendor executable at `~/.local/share/flowdeck/flowdeck` and back up the original entrypoint. No changes to LFG server or iOS app code.

Use macOS `proc_pid_rusage` for physical footprint and process birth identity. Run each heavy command in its own process group, track descendants, and only signal owned identities. Serialize jobs via an advisory lock rather than inventing a second aggregate memory threshold. Native simulator daemons and tool jobs launched outside the wrapper are not included; skills must route build/test work through the guarded CLI. Help, discovery, simulator management and log streaming bypass the heavy-job slot.

Resource-limit failures open a persistent circuit breaker: subsequent guarded jobs fail rather than blindly retry. Reset is an intentional agent action after examining the failure. Status and rotating JSONL logs live outside `/tmp`; do not record environment variables or full potentially sensitive arguments.

## Decisions

- Eugene chose 12 GiB per build/test job. Retain a 4 GiB warning.
- Serialize guarded jobs to cap their aggregate footprint at the same budget. Other apps and simulator system processes still need headroom.
- Archive the inactive 20 GB previous log by same-filesystem rename, preserving bytes; do not truncate a live log or delete simulator data.
- Diagnose only when needed: default `never`, per-run `on-failure` via `LFG_TEST_DIAGNOSTICS` or explicit supported Xcode options. Check current/previous simulator logs against 250 MiB before and during diagnostic collection.
- No commit/push or test-failure fixes in Noto are part of this task.

## Verification evidence

- `python3 -m unittest discover -s scripts -p test_build_guard.py -v`: 14 tests passed; evidence `../performance/20260924-memory-incident/guard-tests-after.txt`. Preimplementation import failure preserved in `guard-tests-before.txt`.
- `python3 scripts/install-build-guard.py`: stable supervisor and shims installed; manifest `guard-install.json`. Source/installed byte equality verified, actual vendor version 1.11.1 (397) passes through installed shim.
- `installation-verification.json`: global DebugLogging 0, skill reference paths resolve, original archive identity preserved. Archive is 20,209,646,258 bytes with same device/inode after rename.
- Independent CLI audit: PASS, recorded in `../performance/20260924-memory-incident/independent-audit.md`. The independent agent reran all 14 tests (3.233s), exercised a separate 60 MiB SIGTERM-resistant allocation fixture, verified installed command routing, archive identity and skill references. The dedicated verifier model was unavailable; a separate default agent performed the same audit.

## Verification boundaries

The Xcode option governs verbose long-running diagnostics, not all possible xcresult attachments. No heavy Xcode repro or original Noto failing suite has been launched. The limit is sampled and cannot guarantee memory never briefly exceeds 12 GiB. Direct native/MCP jobs bypass this CLI, and unobserved detached descendants and shared simulator daemons are not counted. Killing the supervisor with SIGKILL prevents cleanup. These limits are explicit in the shared skill policy.


## Review fixes

The independent audit found root mode flags could precede a heavy command and bypass the original first-token classifier. Fixed option-aware action detection, including `-i` and `--changelog` before a test command. Also fixed short examples and options-before-discovery unnecessarily acquiring the heavy slot. Regression coverage passed and the corrected source was reinstalled before the final independent PASS. Standalone interactive mode is refused because diagnostics defaults cannot be injected into later menu-selected tests.

## Files and local installation

- Repository: `scripts/build_guard.py`, `scripts/test_build_guard.py`, `scripts/install-build-guard.py`, this feature doc, and incident report/evidence.
- Installed: `~/.local/bin/flowdeck`, `~/.local/bin/lfg-build-guard`, `~/.local/lib/lfg-build-guard/build_guard.py`, original entrypoint metadata and durable state directory.
- Skills: canonical `~/.claude/skills/{flowdeck,ios-dev-testing,ios-performance-profiling}/SKILL.md`, separate Codex FlowDeck entrypoint, shared FlowDeck `resources/debug-logging.md`, with Codex links resolving to the same policy.
- Log: reversible inactive-log archive; global CoreSimulator DebugLogging off. No original bytes deleted, no shared service restart, no product source changes by this task, no commit/push.
