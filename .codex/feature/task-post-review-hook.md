# Automatic post-session outcome reconciliation

Tier: Product. Backend TypeScript/Bun and installed Python lifecycle hook.

## User story and flow

Eugene wants scheduled runs reviewed automatically when their session finishes, including later corrected verdicts.

1. The existing UserPromptSubmit hook records the current turn's start time.
2. Stop queues a durable review event. SessionEnd provides a fallback for normal process exit.
3. A host worker waits for the final transcript and an idle, finalized run.
4. It validates the exact-run verdict and applies the existing audited review operation.
5. A durable receipt records applied, unchanged, or needs-review. No agent or phone task restarts.

## Success criteria

- [x] SC1: Real hook execution queues Stop/SessionEnd events quickly without network dependence or changing existing lease behavior. Verify with hook script tests and a real Codex CLI probe.
- [x] SC2: The worker automatically applies a corrected terminal verdict and preserves original assessment, all scheduling fields, and unrelated runs. Verify through the real runtime and JSON store.
- [x] SC3: Active/busy sessions, a stale pre-turn verdict, wrong-run blocks, malformed/missing verdicts, duplicates, and queue replay cannot produce premature or duplicate completion. Verify with negative/replay tests.
- [x] SC4: Pending events survive host restarts and retry until the transcript becomes ready. Exhausted retries leave a needs-review receipt. Verify using fake clocks and worker re-instantiation.
- [x] SC5: Install the updated hook, deploy an isolated host release, and verify an installed-hook event drains automatically on the live host without modifying saved task settings or running phone work. Verify with queue/result receipts and whole-store snapshots.

## Decisions

- This performs deterministic validation and synchronization of the session's completion judgment. It does not introduce a second model grader.
- Use Stop for turn completion. SessionEnd can happen much later, so it is only a fallback.
- Hooks write local files and return; they do not wait for HTTP, block the agent, or create continuation prompts.
- Pin the review to the triggering turn's start and any structured verdict supplied by the hook. Never consume an older verdict while the current response is flushing.
- Preserve the existing explicit review API and audit trail. Keep normal scheduled completion polling.
- No database access, changes to completion criteria, new phone work, or re-arming of schedules.

## Verification evidence

- `task-post-review-hook/tests-red.txt`: new behavior failed before implementation (missing module).
- `task-post-review-hook/tests-regression.txt`: 141 tests passed, 693 assertions across scheduler and lifecycle tests.
- `task-post-review-hook/types.txt`: TypeScript check passed with no errors.
- `task-post-review-hook/release-tests.txt`: isolated release passed 67 focused tests, 304 assertions.
- `task-post-review-hook/cli-probe/verification.json`: a real Codex CLI session emitted Stop and SessionEnd with current-turn pins.
- `task-post-review-hook/hook-install.json`: installed the new Python hook; both existing hook configurations stayed byte-identical.
- `task-post-review-hook/hook-speed.json`: installed hook returned silently in 38.65 ms in the measured probe.
- `task-post-review-hook/independent-tests.txt`: 56 independent tests passed, 265 assertions. The independent implementation gate passed after both race fixes. `task-post-review-hook/independent-audit.md` now confirms PASS for SC1–SC5, including live host verification.
- `task-post-review-hook/deployment.json`: activated the isolated host release with no active scheduled runs; the full task store stayed unchanged.
- `task-post-review-hook/live-verification.json`: the installed Stop hook queued an event for an already-completed run. The live worker produced a reviewed, unchanged receipt after 9.8 seconds; no phone actions, new runs, or task-store changes occurred.

## Result and limits

The installed Claude/Codex hooks now queue reconciliation automatically. The host waits for an idle, finalized exact-run transcript. It preserves the previous assessment if a correction changes the outcome. Busy/unflushed events retry for up to ten minutes before leaving a needs-review receipt. Unrelated sessions expire without changing task history.

This validates and synchronizes the source session's structured decision. It does not start another model to re-grade the warm-up or inspect arbitrary report files. Existing explicit review remains available. A real Codex lifecycle was tested; Claude coverage used its supported hook payload through the actual installed Python script, without a separate live Claude task.

## Bugs and blockers

- Independent inspection found an event-loss race when Stop preceded persistence of the session binding. Fixed by retaining unmatched events until the retry limit. A deterministic regression passes.
- Independent inspection found possible starvation behind the first 50 queued files. Fixed by counting only eligible events and persisting retry delays. A 61-event regression passes.

## Debug mode

Inspect the event and receipt under `~/.lfg/task-review-queue/` and `results/`, then compare the source session's final verdict and run outcomeReviews. Receipts contain timing and result metadata, not private reasoning.
