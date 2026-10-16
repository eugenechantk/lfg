# Feature: sim-release-on-turn-end

Code lives in `~/.claude` (its own repo), not in lfg. Canonical reference after this ships:
`~/.claude/scripts/simulator-lifecycle.md` (new "Stage 5b — Release at turn end").

## User Story

As Eugene, running many Claude Code and Codex sessions at once, I want every session,
subagent and Codex thread to shut down the simulators it used as soon as its turn ends,
so that finished sessions never leave booted simulators eating RAM until the Mac panics.

## User Flow

1. An agent drives its simulator (`flowdeck run/test/ui -S <sim>`). The guard stamps it,
   and now also records **who** drove it (main agent, or subagent `<agent_id>`).
2. The agent's turn ends:
   - main agent → Claude `Stop` / Codex `Stop`
   - subagent → Claude `SubagentStop`
   - session exits → `SessionEnd`
3. The hook returns at once and hands off to a detached worker. The worker shuts down the
   booted sims in this session's namespace that this agent owns. It skips a sim that is still
   in use: a command still running against it, a subagent still running, or a command that
   drove it after the turn ended.
4. Next turn, the agent runs a guarded command against the released sim. The guard sees the
   "released" marker, boots the sim (with admission control) and lets the command run.

## Success Criteria

- [x] SC1: Main-agent `Stop` shuts down this session's booted sims within ~20 s (whole namespace once no subagent runs — revised, see Decision Log) — **Verify by:** pipe a real Stop payload for this session into the registered hook command; my booted `cc-59836304` goes `Shutdown`; log line in `~/.claude/scripts/logs/sim-release.log`. Then a real Claude Stop from a live session in the log.
- [x] SC2: `SubagentStop` shuts down only the sim that subagent drove; the parent's sim stays booted — **Verify by:** spawn a real subagent that drives its own sim, observe its sim `Shutdown` after it returns while `cc-59836304` stays `Booted`.
- [x] SC3: Main `Stop` while a subagent of the session is still running releases nothing for main (deferred) — **Verify by:** SubagentStart marker present + piped Stop → log says deferred, sim stays Booted.
- [x] SC4: Main `Stop` while a background command still targets the sim leaves that sim booted — **Verify by:** background process under the session's agent process whose argv holds the UDID + piped Stop → log says in-flight, sim stays Booted.
- [x] SC5: The next guarded command on a released sim boots it and runs — **Verify by:** after SC1, real `flowdeck ui simulator screen -S <udid>` through the Bash tool succeeds and the sim is `Booted`.
- [x] SC6: The hook never delays or fails a turn — **Verify by:** time the hook (< 0.5 s), exit 0 on empty/garbage stdin.
- [x] SC7 (hooks trusted 2026-10-15; Codex subagents covered too): Codex sessions are covered — **Verify by:** `Stop` + `SessionEnd` registered in `~/.codex/hooks.json`; a codex-shaped payload (no `agent_id`) releases main-owned sims; a real Codex Stop line in the log.
- [x] SC8: `SessionEnd` releases every sim in the session namespace, any owner — **Verify by:** piped SessionEnd payload with a booted subagent-owned sim → both shut down.
- [x] SC9: `flowdeck … ui … --help` no longer provisions a sim or evicts peers — **Verify by:** `--guard` on a help command returns 0 with no provisioning output.
- [x] SC10: Unit tests for owner ledger, scope selection, in-flight detection and help exemption pass — **Verify by:** `python3 -m unittest` on the new test file.
- [x] SC11 (committed in ~/.claude, not pushed; ~/.codex edits uncommitted): Docs updated (lifecycle doc, flowdeck SKILL.md) and `~/.claude` changes committed — **Verify by:** `git -C ~/.claude log -1 --stat`.

## Platform & Stack

- **Platform:** macOS host tooling (Claude Code + Codex hooks)
- **Language:** Python 3 (`/usr/bin/python3`), bash
- **Key pieces:** `hooks/flowdeck/flowdeck-sim-session.py` (brain), `settings.json`, `~/.codex/hooks.json`, `scripts/simulator-reaper.sh`

## Steps to Verify

1. `python3 -m unittest ~/.claude/hooks/flowdeck/test_sim_release.py`
2. Pipe payloads into `flowdeck-sim-session.py --turn-end` and watch `flowdeck simulator list` + the log.
3. Spawn a real subagent that drives a sim; watch SubagentStop in the log.
4. Watch the log for real Stop events from other live sessions.

## Implementation Phases

### Phase 1: Owner ledger + release worker + hook entry
- Owner written into `state/sim-activity/<udid>` (content `main` / `agent:<id>`; mtime unchanged in meaning).
- `--turn-end` hook entry (reads stdin, records SubagentStart, spawns detached worker).
- `--release` worker (scope filter, deferral, in-flight check, stop UI capture session, shutdown, released marker).
- Guard: `--help` exemption; allow path reboots a released sim.
- Gate: unit tests + piped-payload runs in dry-run.

### Phase 2: Register hooks (dry-run first), observe real events, then go live
- Claude: Stop, SubagentStart, SubagentStop, SessionEnd. Codex: Stop, SessionEnd.
- Gate: real payload shapes seen in the log before turning shutdown on.

### Phase 3: Docs + commit

## Decision Log

- **Shut down at every turn end, no grace period.** A hook cannot tell "task done" from "turn done"; every Stop means the agent handed back to Eugene. A slim sim boots in ~10–20 s and the guard now reboots it transparently, so the cost of a wrong guess is small. Alternative was a delayed shutdown; rejected as more moving parts for little RAM benefit.
- **Owner = last driver, not the sim's name.** Names don't encode ownership reliably (`cc-<sid>-ipad`, `cc-<sid>-repeat` exist; parents hand sims to subagents). The guard already sees every driving command, so it records who drove.
- **Main Stop defers while any subagent of the session runs.** Background subagents end the parent's turn early, and a handed-off sim may not be touched yet. Background completion always re-invokes the parent, so a later Stop releases it.
- **The reaper stays** as the backstop for killed panes and crashes where no hook fires.
- **Main Stop releases the whole namespace when no subagent runs** (revised mid-build). Owner-scoped Stop missed sims of agents that never fire SubagentStop. With no subagent running, no other agent of the session can be using any sim.
- **Not changed: provisioning for agents without `agent_type`.** Mapping them to the parent's sim is plausible but guesses at Claude Code internals; the namespace release already bounds the cost to one turn.
- **Include the `--help` exemption** (found this session: a help read provisioned a sim and evicted a peer's two idle sims).

## Verification Evidence

_All times 2026-10-15 HKT on Eugenes-MacBook-Pro. Log = `~/.claude/scripts/logs/sim-release.log`._

| SC | What ran | Observed |
|---|---|---|
| SC6 | `--turn-end` with empty, garbage, `[]`, missing/int session_id; `time` on a real Stop payload | rc=0 every time; 0.04–0.05 s wall |
| SC10 | `/usr/bin/python3 -m unittest test_sim_release.py` | 26 tests OK |
| SC9 | unit test `HelpExemption` (`--help`, `-h`, `--examples`, sim_navigate `--help`) | not guarded; real commands still guarded |
| SC3 | piped SubagentStart (fake agent) + Stop | `deferred: 1 subagent(s) still running (afake000)`; all 3 namespace sims stayed Booted |
| SC4 | background `sh -c 'sleep 40; : <UDID>'` under this session's claude + piped Stop | `keep cc-59836304: still in use by pid 28338`; the two finished agents' sims `shut down` (15:16:42–43) |
| SC1 | piped Stop after the background job ended | 15:18:19 `shut down cc-59836304 (… owner main)`; simulator list → Shutdown; released marker written |
| SC5 | released sim, then a real screen command wrapped in `time ( … )` via the Bash tool | first try "not booted" — parser bug (see Bugs). After the fix: screenshot OK (home screen, `scratchpad/after-reboot.png`), sim Booted, marker cleared, owner `main`. Control: same command on a shut-down sim with NO marker → FlowDeck refuses ("as it is not booted"), so the guard's reboot is required |
| — | dry-run phase, real events from other live sessions | `SubagentStop cc-aa2af7c8 agent=a8088c64 not mine, kept: cc-aa2af7c8=main`; `SubagentStop cc-68284ba9 agent=af642652 not mine, kept: cc-68284ba9=agent:a81f85c6…` (a real parent→subagent handoff, kept correctly) |
| SC2 (dry-run) | real haiku subagent drove its own sim | `SubagentStart … agent=a03cbb63`, then `SubagentStop … [dry-run] would shut down cc-59836304-a03cbb63 (owner agent:a03cbb63…)`; parent sim kept |
| SC2 (live) | second real subagent drove its own sim | 15:21:11 `SubagentStop cc-59836304 agent=abec7bf9 shut down cc-59836304-abec7bf9 (owner agent:abec7bf9…)`; parent `cc-59836304` kept (`not mine, kept: cc-59836304=main`) |
| SC7 | 4× real `codex exec` sessions driving a sim | hooks never invoked (Codex skips untrusted hooks; `config.toml` `hooks.state` trust hashes). Same run with `--dangerously-bypass-hook-trust`: Codex `Stop` + `SessionEnd` payloads arrive (`turn_id`, no `agent_id`), 15:34:54 `shut down cc-01a13e7a`. **Persistent trust still needs Eugene.** |
| SC7 bug | that run's sim was Booted again 1 s after the shutdown | simslim watch was mid-slim and re-booted it. Fixed (wait for slim + 5 s post-check). Live re-run: 15:44:27 `waited 6s for simslim to finish cc-e5b44cb5`, then `shut down`, stayed Shutdown |
| SC1/SC8 (real Claude) | headless `claude -p` session drove a sim | 15:42:14 `Stop cc-f6277a9e shut down …` + `SessionEnd …`; `flowdeck simulator list` → Shutdown |
| — | first screenshot after provisioning failed ("no translation object returned") | pre-existing readiness gap on the provisioning path too; `boot_and_wait` (bootstatus) now used for both. Re-run: screenshot succeeded first try |
| SC3 (real) | live session aa2af7c8 ended a turn with 2 background subagents running | 15:44:28 `Stop cc-aa2af7c8 deferred: 2 subagent(s) still running (a2eb86a8, abe69521)`; both transcripts written within 10 s of the check (really running; abe69521 was resumed) |
| SC10 | unit tests after all fixes | 30 tests OK |

### Independent audit (verification-auditor, 15:46–16:13)

Report: `.claude/evidence/sim-release-on-turn-end/audit.md` (25 artifacts). Verdict **PARTIAL**: every criterion it checked passed — SC1, SC3, SC5 (twice + no-marker control), SC6, SC8, SC9, SC10, guard allow-path timing and isolation unchanged. SC2/SC4/SC7/SC11 were outside its brief (SC2 then passed live on the auditor's own SubagentStop, 16:14:03). It found five bugs; all fixed except one recorded as a known gap:

| # | Finding | Resolution | Live re-check |
|---|---|---|---|
| 1 | Codex UUIDv7 ids share `cc-<first8>` within ~65 s, so one session's Stop could kill another's running test | v7 ids use the random last 8 hex | Codex run → `cc-9d6b8fef`, `cc-57a6f18b` (tails), released |
| 2 | One session id with two live processes | Known gap 2a in the lifecycle doc (rare; lfg collapses duplicates) | — |
| 3 | SubagentStop shut down a sim the parent handed over, mid-parent-turn (also seen in production: `cc-68284ba9` 15:48:38) | Ledger line 2 = `home` (first driver); SubagentStop needs owner AND home | 16:17:32 `SubagentStop … not mine, kept: cc-59836304=agent:a069d676… (home main)`, sim stayed Booted |
| 4 | Basename match blocked `ls ~/.claude/hooks/flowdeck test` | Path match only in command position | unit test |
| 5 | Race between in-use check and shutdown (capture-session stop can take seconds) | Re-check the stamp right before shutdown; marker written first, cleared if shutdown fails | unit test |
| — | boot (120 s) + bootstatus (120 s) could exceed the 180 s hook budget | 90 s + 60 s | — |

Post-audit, one more live finding: a Codex session's **first** screenshot after provisioning failed ("No translation object") because the simslim watch agent was still stopping services. `wait_until_usable` (≤ 45 s) on both boot paths; re-run waited 28 s, screenshot succeeded, sim released at Stop (16:21:57). Unit tests: 35 OK.

### Codex trust + Codex subagents (second turn)

- Trusted `stop:0:1`, `session_end:0:1`, `subagent_start:0:0`, `subagent_stop:0:0` through Codex's own "Hooks need review" UI (Eugene asked); `config.toml` diff = exactly those four `trusted_hash` entries. Backup: `scratchpad/config.toml.before-trust`.
- Plain `codex exec` (no bypass): 16:32:37 `Stop cc-ed9fe8a4 shut down …`.
- Codex has subagents (`thread_spawn`, e.g. `ios_visual_evidence_auditor` "Proof"). Payloads match Claude's shape (`session_id` = parent thread, `agent_id` = child thread). Fixed: child suffix uses the v7 tail (`cc-<parent tail>-<child tail>`).
- Real subagent run (no bypass): `SubagentStart cc-25f2dcf6 agent=01a13eb4` → child sim `cc-25f2dcf6-bc2c09a0` → `SubagentStop … waited 121s for simslim …` → `shut down … owner agent:01a13eb4…`, stayed Shutdown. The 2-minute delay and the child's failed first screenshot were the simslim watch timing out on that sim (`launchctl print-disabled: exit status 124`), not this feature.
- SC7 now fully verified.

## Bugs

- **Fixed — subshell-wrapped FlowDeck commands bypassed the guard.** `time ( … )` tokenises to `(flowdeck`, so the segment was not recognised: no isolation, no stamp, no reboot. Now unwrapped (paren strip + basename match); unit test `test_subshell_parens_do_not_hide_flowdeck`. Side effect: heredoc *text* that spells a command that way is now blocked too, like plain command text already was.
- **Fixed — a freshly provisioned sim was invisible to the turn-end hook.** The block path refreshed `.simcache.json` before `ensure_sim` created the sim, and the hook skips sessions with no namespace name in the cache. `ensure_sim` now refreshes after create.
- **Fixed — sim re-booted by simslim right after release.** A short session released its sim while the watch was still slimming it; the slim pass booted it again. Worker now waits (≤120 s) and re-checks state 5 s after shutdown.
- **Fixed (found by the auditor's run) — exited agent fell back to a global "in use" scan.** In `claude -p` mode the agent process is gone by the time the worker looks; the fallback (any non-orphan process naming the sim) matched the shell that *launched* the headless session, so its sim was kept (`cc-290c49ef … still in use by pid 31996`). A known root that has exited now means nothing in flight; unit test `test_exited_agent_has_nothing_in_flight`.
- **Fixed — Codex never ran the hook.** Not a code bug: Codex skips untrusted hooks. Command changed to a plain executable (`sim-turn-end.sh`) and moved into lfg's hook group while diagnosing; trust remains Eugene's call.
- **Fixed — first UI command after reboot failed** ("No translation object returned"): `flowdeck simulator boot` returns before SpringBoard is up. `reboot_released` now waits on `simctl bootstatus`.
- **Found — internal agent provisioning.** An agent with `agent_id` but no `agent_type` (not in any transcript) ran a FlowDeck command during a subagent run; the guard booted `cc-59836304-a1d7dca0` for it, and it never fires SubagentStop. Handled by main Stop releasing the whole namespace once no subagent runs. Not fixed at the source (see Decision Log).
