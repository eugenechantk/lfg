# Fix: move sessions from an offline host

## User story and flow

Move a session from offline Pro to online Air, continue on Air, and clean up the source when it reconnects. Preserve the existing transcript preflight and online close-before-resume behavior.

## Diagnosis

The destination's `/resume` returns `alreadyLive` only for a local session. The iOS client incorrectly retries that successful response eleven times and reports that the source is busy. Separately, merging host snapshots in configured order lets an offline source's cached row override a live destination with the same session ID. Codex resumes preserve IDs; Claude also reports an existing ID when already live.

## Success criteria

- [x] SC1: Offline source skips close, sends force, and accepts both a new resume and an already-live destination. Verified with transport integration tests using real LFGClient requests and a URLProtocol HTTP fixture.
- [x] SC2: Reachable source closes first; transport failure falls back to forced takeover; HTTP refusal aborts. Verified with transfer flow tests.
- [x] SC3: Destination failure does not complete a move. Verified with transfer flow tests; independent source review confirms the app queues cleanup only after completion.
- [x] SC4: Offline cached rows cannot overwrite a reachable target; successful moves remove the old source snapshot and preserve destination state. Verified with merge/snapshot/fence/cleanup-suppression tests and recorded source recovery in Simulator. Exact in-flight race permutations were independently reviewed, not forced in Simulator.
- [x] SC5: Transcript availability/freshness checks and foreign-lease protection remain intact. Verified with Swift preflight regression case and Bun resume/preflight/lease suites.
- [x] SC6: App builds and the Move to host interaction succeeds in Simulator. FlowDeck build and independent recorded UI audit passed on Pro using isolated synthetic hosts.

## Decisions

### Follow-up: inline move status

Product-tier UI change requested after the first audit. Keep the session detail mounted throughout transfer, show a mini spinner and **Moving host…** in the title's existing Running status position, retain the source pill until target acceptance, then show the destination pill. Preserve the draft and transcript when a server returns a new session ID. Failures clear progress and keep the existing error banner. Stale-copy confirmation remains a separate explicit decision.

- [x] UI1: Delayed preflight/resume visibly shows Moving host… beside the source pill; conversation remains open. Recorded on iPhone and iPad with delayed HTTP responses.
- [x] UI2: Successful same-ID and changed-ID moves update the pill in place, preserving draft and transcript; no extra detail screen is pushed. Recorded online and offline; a single Back returns to the list, and iPad retains its selected sidebar row.
- [x] UI3: Failure clears progress, retains the source pill and draft, and reports the error inline. Cancelling stale-copy confirmation leaves the session untouched. The transient 503 banner is verified in a decoded recording frame; dismissing the confirmation sends no resume request.
- [x] UI4: Repeated changed-ID moves preserve the original navigation identity without stale redirects. Both redirect tests and successive in-place moves passed.

Verification: unit coverage for redirect chains and returns to a previous ID; existing transfer transport tests; FlowDeck app build and independent recorded delayed-success/failure/confirmation flows using isolated hosts on Pro. UI rendering and draft preservation require recorded app evidence rather than a pure-state test. No release or live-session move is authorized by this UI request.

Implementation: observable store-owned preflight/transfer progress feeds the existing title status line, with a retained source pill while resume is pending. The composer remains editable but Send waits until the move completes. Changed-ID transfers retain their original navigation alias; redirects are flattened across repeated moves and safely handle a return to an earlier ID. A transfer no longer requests a fresh navigation selection on completion.

Follow-up verification: 162 Swift Testing cases passed locally; the full Pro core run also passed 549 XCTest cases with the same one optional live-terminal skip plus all 162 Swift Testing cases. FlowDeck app build passed. Logs: `inline-ui-core-tests.log`, `inline-ui/core-tests-full.log`, `inline-ui/app-build.json`, `inline-ui/app-build-fix1.json`. Independent recorded UI verification passed after the runtime correction below.

First UI audit found a changed-ID crash after same-ID progress/success passed. The symbolicated crash (`inline-ui/changed-id-crash.ips`, SessionDetailView.swift line 667 in that build) shows a lazy transcript row subscripting `messages` using indices captured before remap removed the old dictionary key. Fix: capture the transcript array and window together for row rendering; lazy closures never index a newly fetched array. The recorded changed-ID regression rerun passed; pure alias tests did not exercise SwiftUI's deferred row evaluation.

The corrected FlowDeck build (`inline-ui/app-build-fix1.json`) passes. Independent rerun completed two successive changed-ID moves while preserving the open detail, typed draft, and transcript; one Back returns to the list. A delayed same-ID move also preserved the detail during the source-close/target-resume gap. The target-failure and stale-warning dismissal flows retained the draft and source pill, with progress cleared. Offline transfer and recovery passed. iPad also passed a changed-ID move with its selected sidebar row and draft retained. Source checksums match the isolated Pro build for all four follow-up Swift files.

Visual evidence under `inline-ui/`: `07-same-preflight.jpg` and `09-same-complete.jpg` show the requested source-pill/loading/destination-pill sequence; `repeat-transition.jpg` proves repeated changed-ID completion on the corrected build; `phone-failure-banner.jpg` proves the inline failure; `61-offline-preflight.jpg` and `62-offline-complete.jpg` prove the offline UI; `ipad-19-preflight.jpg` and `ipad-20-complete.jpg` prove adaptive layout and preserved selection. The first failed recording and crash report remain clearly identified for regression provenance. These are real app interactions against synthetic HTTP hosts, not a physical-device release or real agent migration.

Final independent verdict: **PASS after fix1**, documented in `inline-ui/evidence.md`. The corrected phone recording is `inline-ui/phone-fix1.mov` (396.840 seconds); iPad is `inline-ui/ipad-flows.mov` (214.067 seconds). Both were finalized, inspected with ffprobe, and decoded for visual review. `inline-ui/request-verification.json` passes all request-ordering and cancellation checks. The test fixture was stopped, ports 18871/18872 have no listeners, and both dedicated simulators were shut down via FlowDeck. No commit, push, or release was performed.

- Product tier; software-development and iOS testing workflows. Extract only the transfer transport sequence into LFGCore to exercise the actual close/resume requests without UIKit. Refactor risk is low (method extraction), with existing plan/preflight tests and new sequence tests.
- Do not restart live hosts, move real working sessions, commit, or publish a build as part of isolated verification.
- Preserve existing dirty Xcode project and mosh wrapper changes.
- Source audit found recovery-during-resume, pre-transfer refresh, and unordered persistence races. Added timestamp fences, source-copy suppression until cleanup confirmation, a fresh post-transfer refresh, ordered write-through tasks, and protection for moves back to a former source. Cleanup is retried on a later recovery/transfer trigger after failure, rather than an unbounded retry loop.
- An unrelated widget change appeared during the task and was preserved.

## Verification evidence

Evidence directory: `.codex/evidence/offline-host-transfer/`.

| Check | Result | Evidence |
| --- | --- | --- |
| Regression before fix | Already-live responses threw `sourceBusy`; offline Pro displaced Air ownership. The baseline also caught a fixture assertion expecting absent rather than null force, corrected before the green run. | `baseline-tests.log` |
| Focused corrected run | 17 Swift Testing tests passed, including actual close/resume HTTP encoding/decoding. | `fixed-tests.log` |
| Final broader run | 160 Swift Testing tests in 22 suites passed, including 16 new transfer tests. XCTest sources compile but their runner is explicitly disabled in this CLT setup; this is not the entire XCTest suite. | `core-tests.log`, reproducible command `bash .codex/evidence/offline-host-transfer/run-core-tests.sh` |
| Backend protections | 26 tests passed, 0 failed; force skips a fresh foreign lease, plain resume still refuses, transcript missing/cwd/freshness preserved. | `backend-tests.log`; command `bun test src/commands/serve-resume-force.test.ts src/commands/serve-transcript-status.test.ts src/leases.test.ts` |
| Independent source and UI review | PASS after fixing all reported races and completing remote UI verification. The dedicated visual auditor could not start (unsupported configured model); a separate default agent performed the independent fallback review and recorded UI verification. | `audit/evidence.md` |
| Initial app build on Air | FlowDeck exited 69 before compilation; build log states Xcode license unaccepted. Superseded by the successful isolated build on Pro below. | `app-build.json`, `xcode-license.log` |
| Diff hygiene | `git diff --check` passed via CLT Git. No commits, pushes, live host restarts, real session moves, or releases. | Final working-tree inspection |
| Full core suite on Pro | 549 XCTest cases: one existing live-terminal test skipped because `LFG_TERM_TEST_URL` is unset, zero failures. All 160 Swift Testing cases passed. | `pro-validation/core-tests-full.log` |
| App build on Pro | FlowDeck build PASS, including SessionStore and the app target. Build completed 2026-09-19 17:20:08 UTC. | `pro-validation/app-build.json` |
| Recorded UI flows on Pro | PASS: offline already-live destination, offline fresh resume, source recovery and deferred closes, online close-before-resume, and normal app relaunch. All three sessions remain on Air; no busy error or duplicate resume. | `pro-validation/request-verification.json`, `pro-validation/transfer-flows.mov`, numbered screenshots and accessibility trees |

## Remote verification after Air became inaccessible to the user

- Air still requires administrator authentication to accept the Xcode license; `sudo -n true` confirms it is unavailable. No license or system settings were changed.
- Pro became remotely reachable, so verification moved there without requiring user access to Air. An isolated copy at `/private/tmp/lfg-transfer-verify.korlBN` contains archived HEAD `08de5d539bd465e662577197c60cd6acfa29d56a` iOS sources plus the three changed Swift source files and new test file. SHA-256 verification confirms those files match the Air working copy (`pro-validation/source.sha256`). Existing unrelated edits, private credentials, and live service state were excluded.
- The isolated project was regenerated using its canonical `ios/project.yml`; no project file in the working checkout was changed. FlowDeck uses a separate derived-data directory.
- Dedicated simulator: iPhone 17 Pro device type, `cc-offline-transfer-20260920`, UDID `8623CBC8-65A3-4008-B038-C2E648100760`. Loopback fixture ports 18871/18872 were checked before use; port 8766 and real sessions are untouched.
- Full package tests, app compilation, and independent visual verification pass on Pro. Parent review of the refreshed list and post-relaunch screenshot confirms the moved rows show Air; request logs confirm forced offline resumes, deferred source closes after recovery, and close-before-unforced-resume online.
- The 230.523-second recording is retained at `pro-validation/transfer-flows.mov`; metadata and decoded storyboard were inspected. After collecting evidence, only the test fixture processes were stopped and the dedicated Simulator was shut down. Ports 18871/18872 are free; the isolated checkout and artifacts remain available for review.
- Runtime evidence uses the real app and real HTTP requests against synthetic hosts, sessions, transcripts, and pane lifecycles. It does not prove physical network partition behavior, Tailscale connectivity, actual agent spawning, or transcript sync. Relaunch was tested with fixture hosts reachable, not as a cache-only hydration test.
- Database crash recovery is not proven by the tests. The fix is not released or installed on a physical device.
