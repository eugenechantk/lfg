# Pro memory exhaustion — 24 September 2026

## Authorized follow-up: global logging disabled

At Eugene's request, set `com.apple.CoreSimulator DebugLogging` to false and verified `defaults read` returns `0`. The original logs were preserved and no shared service was restarted. Updated the global FlowDeck, iOS development testing and performance profiling skills for Claude and Codex: agents may choose targeted logs or temporary global infrastructure diagnostics without asking again, with bounded capture and verified cleanup. Evidence: `logging-change.json`. The 12 GiB build/test guard is now installed; see the implementation follow-up below. The original investigation below records the pre-change state.

Follow-up verification: the final preference readback remained `0`; 3,113 newly appended CoreSimulator log bytes contained zero `<Debug>` entries. All six Claude/Codex skill entrypoints resolve to the same logging-policy reference, and their YAML parses. The strict skill validator passes iOS development testing; it rejects the unchanged `version` / `user_invocable` metadata in the existing FlowDeck and performance skills. Those unrelated metadata fields were preserved.

## Authorized implementation follow-up

Implemented the selected 12 GiB budget in the installed FlowDeck entrypoint. Build/run/test jobs now share a serialized slot and have one-second physical-footprint sampling across their process group and observed descendants. At a limit breach the supervisor stops only the owned job, records a persistent breaker, and refuses subsequent guarded jobs until deliberate inspection/reset. Warning remains 4 GiB. This does not change the existing Bun host limit.

Routine tests now receive Xcode's `-collect-test-diagnostics never`; agents can opt into `on-failure` per invocation with `LFG_TEST_DIAGNOSTICS` or explicit Xcode options. Diagnostics-enabled jobs check the combined current/previous CoreSimulator logs before launch and while running, with a 250 MiB bound. This flag specifically controls verbose long-running test diagnostics; its use is not proof that all xcresult attachments disappear.

The inactive original log was moved to `~/Library/Logs/LFG-DiagnosticArchive/20260924-CoreSimulator.prev.log`, after checking it had no open file handles. The same inode/device and all 20,209,646,258 bytes were preserved; no data was deleted or truncated. `archive-log.json` records identity verification.

Updated FlowDeck, iOS development testing and performance profiling skills for Claude/Codex to document the default, per-run agent discretion, independent global logging choice, cleanup and limits. Global DebugLogging still reads `0`.

Verification: 14 automated unit/integration checks passed, including command/option ordering, native footprint accounting, a 110 MiB child stopped by an 80 MiB test limit, unrelated-process survival, serialization, cancellation, detached observed-child cleanup, breaker/reset, diagnostic log preflight/growth and fake-vendor argument forwarding. Installed copy matches source; actual vendor `--version` works through the shim. See `guard-tests-after.txt` and `installation-verification.json`. Independent review passed and is recorded separately in `independent-audit.md`, including additional forced-termination evidence and the command-routing issues found and fixed during review.

Boundary: these are sampled job limits, not a kernel-enforced or machine-wide memory ceiling. Unrelated processes, CoreSimulator system daemons, direct MCP/vendor jobs and descendants that detach before observation are outside coverage. A supervisor killed with SIGKILL cannot clean up. The original Noto failing suite has not been rerun; real xcresult attachment behavior and representative multi-session performance remain follow-up measurements, not claimed verified fixes. LFG product code was not modified by this task; nothing was committed or pushed.

## Finding

**The strongest evidence identifies Xcode's test-diagnostic collection as the runaway allocation, rather than LFG's desktop UI or Bun host.** A Noto test run's `xcodebuild` reached **31.69 GiB** on this **36 GiB** Mac. Its result writer subsequently compressed one **20,203,424,320-byte (20.2 GB)** object. A bounded decompression of that object identifies it as the accumulated CoreSimulator log, not Noto application data or LFG transcript data.

CoreSimulator's persistent `DebugLogging` preference is **true**. The previous log is **20,209,646,258 bytes**, spans September 20–24, and contains extensive debug output from simulator/device enumeration. The first 65,536 bytes match the giant test-result object exactly. Its slightly larger size is consistent with logging continuing after Xcode collected its snapshot.

**High-confidence causal chain:** verbose simulator logging → enormous accumulated diagnostic file → Noto test diagnostic/result collection → multi-tens-of-GB Xcode allocation → system memory pressure and widespread process termination → shutdown/reboot. The exact allocation stacks inside the large Xcode processes were not retained, so this is not a proven retain-cycle leak. The observed behavior is consistent with a catastrophic temporary allocation while packaging diagnostics.

## Evidence and timeline

Times are Hong Kong time, 24 September 2026 unless otherwise indicated.

| Evidence | Observation |
|---|---|
| 00:03:21 Noto agent transcript | Started sequential isolated reruns, beginning with `flowdeck test -s Noto -S CC08DBB1-A2C2-44FE-8D68-CA7381A64EC2 --only NotoTests/EditorFindTests --json`. |
| 00:03:36 unified log, PID 34240 | Xcode discovers Noto test products under `FlowDeck/DerivedData/Noto-28a2c7716246`; 00:03:58 identifies `EditorFindTests`. This directly links the large PID to the Noto run. |
| Jetsam report timestamp 00:12:43 | `largestProcess: xcodebuild`, PID 90615, 1,433,973 pages = **21.88 GiB**. This is a different process; its exact command was not recovered. |
| Jetsam report timestamp 00:14:01 | `largestProcess: xcodebuild`, PID 34240, 2,076,904 pages = **31.69 GiB / 34.03 decimal GB**. |
| Same 00:14 report | Desktop `lfg` PID 97454: **21.2 MiB**. Largest Bun PID 14943: **815 MiB**, recorded lifetime maximum **1.56 GiB**. Two `LFG` processes: **118 and 84 MiB**. |
| Both Jetsam reports | Numerous termination records, including `vm-compressor-space-shortage`. The 9,000 entries in the first report include already-jettisoned processes: they are not evidence of 9,000 simultaneous live processes. Do not sum all historical entries as current RAM use. |
| 00:16:21–00:16:31, same PID 34240 | XCResultKit logs compression of a **20,203,424,320-byte** object to **267,618,350 bytes**. The matching object survives inside the Noto `.xcresult`. |
| 00:16:38 Noto agent transcript | First isolated suite finally returns: 12 passed, 2 failures reported. The seven-suite shell loop did not fail fast on a nonzero test exit. |
| 00:17:33 shutdown report | A later FlowDeck-owned `xcodebuild` PID 85384 was waiting on CoreSimulator; footprint only 147 MB. The two giant PIDs are no longer present in this later report. |
| After reboot | Host PID 1097: approximately **834 MB physical footprint**, despite roughly 2 GB RSS. No 37 GB LFG process observed during this investigation. |

Calculations use each report's `rpages × pageSize`, with `pageSize = 16,384`, following [Apple's Jetsam interpretation](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports). The exact user-observed 37 GB figure was not captured. A process-family display could explain the LFG label, but the UI grouping was not verified.

## Why the existing protection missed it

[`scripts/serve-forever.sh`](../../../scripts/serve-forever.sh) already caps the Bun host at 4,096 MB physical footprint, sampled every 30 seconds. It calls `supervise "$child"` on that one PID. It does not protect independent agent tools, tmux-owned processes, Xcode test runners, or the desktop process.

Raising or lowering the Bun ceiling would not stop this failure. The previous August host-allocation incident documented in `.claude/feature/host-memory-ceiling-disconnects.md` involved different read paths and does not establish the cause of this incident.

## Recommended fixes, in order

### 1. Remove the immediate diagnostic hazard

- Disable persistent CoreSimulator debug logging. Current source is `~/Library/Preferences/com.apple.CoreSimulator.plist`, key `DebugLogging = true`. Proposed setting: `defaults write com.apple.CoreSimulator DebugLogging -bool NO`. Verify that new simulator activity stops producing pervasive Debug-level entries; do not assume preference changes affect an already-running service immediately.
- Preserve the compressed failing `.xcresult` and this evidence, then rotate/archive the oversized CoreSimulator log files during an idle simulator window. Deletion or truncation needs explicit approval. The reboot rotated the file to `CoreSimulator.prev.log`; it did not remove it.
- For routine test runs, propose FlowDeck's `--xcodebuild-options='-collect-test-diagnostics never'`. The installed Xcode manual documents this as disabling verbose, long-running diagnostics. Re-enable only for a deliberate diagnostic run after checking log sizes. **Verify whether the CoreSimulator attachment is actually omitted before treating this flag as a complete fix.**

These measures preserve test assertions and failure reporting while reducing diagnostic volume. Apple's [test-plan documentation](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback) exposes diagnostic collection as a configurable policy.

### 2. Add a memory circuit breaker for agent build/test jobs

Implement a reusable wrapper at the FlowDeck/job-launch boundary, rather than extending the Bun-only watchdog indiscriminately:

1. Register job ID, session ID, command, working directory, process group and PID start time.
2. Sample physical footprint every 1–2 seconds; record a bounded rolling history.
3. Initial budget selected by Eugene for this 36 GiB machine: stop a build/test job at **12 GiB physical footprint**. Keep the proposed 4 GiB warning; tune after ordinary builds are measured. Enforce an aggregate build budget as well, so concurrent jobs cannot each consume 12 GiB unchecked. This is an agreed proposal, not an installed guard.
4. Capture a small diagnostic summary, then terminate only the offending job and its owned descendants. Use a short grace period followed by forced termination if needed. Never kill the shared tmux server or unrelated sessions.
5. Stop the enclosing retry/suite loop after a resource-limit termination. Do not immediately launch the next suite into the same failure mode.

Budget agent tool jobs independently because reparenting through tmux means a simple Bun descendant walk is insufficient. A machine-level memory-pressure backstop is useful, but automatic termination must be limited to jobs whose ownership is known.

### 3. Bound log growth and avoid diagnostic amplification

- Preflight the sizes of current and previous CoreSimulator logs before tests. Propose a 100–250 MB warning/rotation threshold; reject automatic full diagnostic collection above the threshold.
- Limit concurrent heavy build/test jobs across sessions. Disabling parallel tests within one invocation does not constrain other agents.
- Record job start/finish, peak footprint, result size and diagnostic size to rotating files outside `/tmp`. The host's current `/tmp/lfg-serve.log` contains only the post-reboot run.
- Surface the responsible tool and session in LFG's resource status, so an Xcode job is distinguishable from LFG itself.

### 4. Validate under a guard, then consider an Xcode issue report

Run the same isolated Noto suite only after the log hazard and memory guard are addressed. Measure footprint through **result finalization**, not just until the last test assertion. Verify that result attachments stay bounded, the job completes below its budget, and simulated limit breaches stop the job without stopping LFG or unrelated agents. Then repeat under representative multi-session load.

If Xcode still materializes a large diagnostic in memory despite bounded inputs, preserve allocation evidence and file an Apple report. A toolchain update is not yet a verified fix.

## Evidence files and reproducibility

- `jetsam-summary.json`: selected raw process records, page-size conversions, reason counts, original source paths and SHA-256 hashes.
- `xcodebuild-system.log`: saved unified-log records for the two large PIDs, 00:00–00:18. Lines 193–254 link PID 34240 to Noto/EditorFindTests; lines 1991 and 2338 record the huge object's compression.
- `large-result-object-prefix.txt`: first 64 KiB streamed from the largest Zstandard-compressed result object; the decompressor was then stopped. The 20 GB object was **not** fully expanded into RAM or onto disk.
- `coresimulator-log-samples.json`: previous-log size, prefix equality, and five bounded 256 KiB samples across the file.
- `environment.json`: relevant versions, memory capacity, preference and post-reboot host footprint.
- `shutdown-stall-excerpt.txt`: selected portions decoded from the existing shutdown report.

Original result:
`~/Library/Developer/FlowDeck/DerivedData/Noto-28a2c7716246/Logs/Test/Test-Noto-2026.09.24_00-03-30-+0800.xcresult`

Original giant object:
`Data/data.0~IsDcfVgK_BaOmVU0pHpxEBPVYlkB8cBRxyuV8LoGpLBdhuAU3qdss2tRvOtqKplr5_y0wWQyraOX2Rb9FxnZEA==`

Original Noto agent transcript:
`~/.claude/projects/-Users-eugenechan-dev-personal-Noto/56c91326-2c9e-4ac5-8610-8f371398e6b6.jsonl`

## Original investigation scope and verification boundary (before follow-up changes)

Investigation and proposals only. No product code, global preferences, original logs, databases or service configuration changed; no service restart, commit or push. No failing test/build was rerun, because doing so could recollect the same giant log. A local pre-tool hook unexpectedly created and booted a dedicated simulator when a help command contained `flowdeck test`; that simulator was subsequently shut down successfully, and no app or test was launched on it.

Confirmed: process attribution, oversized diagnostic identity, persistent debug preference, system memory-pressure records and watchdog coverage gap. Unconfirmed: exact 37 GB UI display, internal Xcode allocation stack, origin of the debug preference, and effectiveness of the proposed fixes until guarded verification is performed.
