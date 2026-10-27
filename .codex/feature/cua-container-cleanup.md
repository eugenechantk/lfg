# CUA container cleanup

## User story

LFG should release memory after local desktop work ends. Docker Desktop should remain available and use Resource Saver when idle.

## Flow

Turn Space off to stop its container. LFG also stops a Space after five minutes of confirmed inactivity. Starting it again preserves its files and starts a fresh agent run with saved conversation context.

## Success criteria

- [x] SC1: Docker Desktop is running with Resource Saver enabled and a 60-second timeout. Verify loaded settings and idle VM shutdown.
- [x] SC2: Off stops running and legacy paused containers without deleting files or briefly resuming paused agents. Verify unit tests and a real disposable container.
- [x] SC3: The host automatically stops only its own inactive local Spaces. Active agents, viewers, pending sends, operations and unknown states remain protected. Verify deterministic lifecycle tests.
- [x] SC4: Finished replies survive stop and reload. A restarted Space accepts follow-ups through a fresh run. Verify route regression tests.
- [x] SC5: The isolated CUA host loads the cleanup policy. Verify its live API and an independent audit. Production port 8766 remains untouched.

## Platform

Bun and TypeScript host code in the existing cua-message worktree. No native UI changes.

## Decisions

- Preserve existing dirty work. Do not commit or push.
- Keep files, images and stopped containers. This work does not prune caches or delete desktops.
- Default Space idle timeout is five minutes. Poll sequentially with a self-scheduling timer to avoid subprocess storms.
- Only explicit terminal agent states count as inactivity. Failed status checks never justify stopping a running container.
- Preserve filtered conversation events before automatic stop. True stop ends agent processes; follow-ups start a new run with saved context.
- Docker's Resource Saver was already enabled by default. Persist it explicitly with a 60-second idle timeout.
- Profile containers publish an ephemeral loopback port. Inspect and re-register their current endpoint after restart, using the existing guest credential internally. Prefer an exact saved endpoint ID when Cua lists older entries with the same name.

## Verification evidence

- SC1: `resource-saver.json` records loaded settings, Desktop process 18251, no running containers, no Linux VM process and normal memory pressure. The auditor repeated this after a disposable container test while both cleanup timers remained active: `audit/idle-after-probe.json`.
- SC2: `bun .codex/evidence/cua-container-cleanup-20261023/live-docker.ts` passed against real HTTP routes and real Docker. It verified running off, paused off without unpause, file retention after restart, automatic background stop and the saved stopped state. It removed only its own disposable fixtures. See `live-docker.json` and `live-docker.log`.
- SC3 and SC4: `bun test src/cua-container.test.ts src/cua-message.test.ts src/cua-stream.test.ts src/cua-lifecycle.test.ts` passed 41 tests and 180 assertions. See `tests.log`. Coverage includes active and unknown status, pending delivery, live viewers, active requests, idle timing, history failure, saved replies and fresh follow-up runs.
- Restart endpoint: a real profile fixture changed port 60784 to 60791. `resume` registered the current endpoint and reused its fixture credential without returning it. The auditor independently reproduced the defect and its unchanged regression passed after the fix. A route regression also verifies list refresh keeps the new endpoint when an older same-name entry appears first.
- Full `./node_modules/.bin/tsc --noEmit` and `git diff --check` passed. Logs: `typecheck.log`, `diff-check.log`.
- SC5: Both isolated hosts loaded final source: port 18967 PID 44928 and port 18968 PID 44938. See `host-restart-final.json` and `live-hosts-final.json`. Both APIs returned 200 with all six recorded Spaces stopped. The original unconfirmed send remains protected. Production port 8766 remains PID 65278.
- Final independent audit: PASS with no open blocking findings. The auditor repeated all 41 tests, 180 assertions, its own unchanged restart regression and full typecheck. It verified final live hosts and Resource Saver with cleanup timers active. See `audit/REPORT.md` and `audit/live-readonly-final.json`.
- `resource-saver-final.json` confirms Desktop stays open while its VM is absent and memory pressure is normal after final host reloads.

## Bugs

- Resolved: off previously called Docker pause and retained memory.
- Resolved: no background idle cleanup existed.
- Resolved during audit: profile restart reused an obsolete ephemeral port.

## Verification limits

No original container was restarted, no real agent task was submitted and no paid provider call was made. Agent history and follow-up continuity use deterministic route tests. Manual off still proceeds if final history is unreachable; automatic stop of a running Space requires successful history capture. Legacy history may be unavailable after its old process was already stopped. The pending delivery flag in the original test Space remains unchanged.
