# Independent build guard audit

Result: **PASS within the stated CLI scope**. Verified September 24, 2026 (Hong Kong). No Xcode build, simulator boot, full incident-log decompression, or production breaker reset was performed. All supervisor fixtures used temporary state/log directories and allocations below 200 MiB.

Audited source SHA-256: `45a216d1cabe57832ed5a3a3e67a6e5ee89a0979d89995f61623110458a26cf1`. The installed stable copy matched this hash. Installation routes the existing FlowDeck entrypoint through that copy and preserves the vendor executable.

| Criterion | Result | Evidence |
| --- | --- | --- |
| SC1: diagnostic choice and arguments | PASS | Independently reran argument and fake-vendor integration tests. Default `never`, environment `on-failure`, and explicit-option precedence pass. Installed vendor 1.11.1 help confirms the `--xcodebuild-options` interface. |
| SC2: footprint and cleanup | PASS | Native footprint/birth-identity tests and small-limit descendant fixture pass. Additional independent fixture: SIGTERM-resistant parent and child, 60 MiB allocation, 50 MiB budget, 50 ms sampling; exit 75, child no longer exists, persistent breaker created. No large real-world workload was needed. |
| SC3: serialization and breaker | PASS | Competing-job, cancelled-waiter, cancellation/slot-release, breaker, intentional-reset, and unrelated-survivor tests pass. |
| SC4: log limits and preservation | PASS | Preflight and growth fixtures pass. Archived log is 20,209,646,258 bytes, device 16777234, inode 325162067, matching the rename manifest; original collection path is absent. Global DebugLogging reads 0. |
| SC5: installed CLI and evidence | PASS | Installed/source hash equality; real vendor metadata remains available under an isolated breaker. Status and bounded event rotation reviewed. Corrected root-option and metadata routing verified against the installed shim. |
| SC6: skills | PASS | Claude/Codex references resolve to the shared policy. Policy includes agent discretion, both per-run modes, global cleanup, footprint scope, sampled-limit caveat, orphan limitations, and local installation scope. |

## Issues found and resolved during review

The first revision classified only the first argument as the action. Actual vendor execution accepts `-i test ...` and `--changelog test ...`, reaching project discovery; these combinations could therefore bypass the guard. It also incorrectly put `test -e` and `test -j discover` behind the heavy-job slot.

The implementation author corrected option-aware action detection and metadata handling, then reinstalled. Independent final checks with an invalid diagnostic-mode sentinel show both supported root-flag combinations now exit 78 from the guard before vendor execution. Short examples still exit 0, and options-before-discovery reaches vendor project discovery without diagnostic validation. Standalone interactive mode is intentionally refused and documented.

Initial suspicion that root `--json`/`--config` also bypassed protection was withdrawn: the actual vendor rejects those before the action. A successful help invocation alone was not sufficient evidence of supported execution syntax.

Final independent test run: `python3 -m unittest discover -s scripts -p test_build_guard.py -v` — **14 tests passed in 3.233 seconds**. Earlier independent run of the original 13 tests also passed; the additional regression covers the routing issue discovered above.

## Evidence limits

- This is a sampled CLI supervisor, not a machine-wide or kernel-enforced memory ceiling. It excludes shared simulator daemons, direct MCP/vendor launches, already-running jobs, and descendants that fully detach before observation. Supervisor SIGKILL prevents cleanup. These limits are documented.
- `-collect-test-diagnostics never` suppresses Xcode's verbose long-running-test diagnostics. This audit verifies option forwarding, not the absence of every xcresult attachment; no full Xcode failure/result-bundle reproduction was performed.
- Log archival identity was verified using the preserved device/inode/size and manifest, not by rereading/hashing the 20 GB file. No log contents were deleted or truncated during this audit.
- Global logging expiry is a required agent workflow in the skill, not an automatically installed logging-toggle service.

Only this audit report was created by the auditor. Implementation and skill fixes were made by the parent agent.
