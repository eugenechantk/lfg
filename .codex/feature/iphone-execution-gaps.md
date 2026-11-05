# iPhone execution gaps

Tier: Product. Status: reproduced waiting boundary; fix unresolved; diagnostic approval pending.

## User story and flow

Eugene needs scheduled phone sessions to keep working within their bookings. Reproduce the delays, fix their cause, update iPhone Control, and test again.

1. Correlate local execution with enclosing result delivery.
2. Repeat the tool path with no phone inputs.
3. Test candidate controls without changing active sessions.
4. Deploy only a candidate that passes the runtime checks.
5. Document safe recovery and remaining blockers.

## Success criteria

- [x] SC1: Reproduce or isolate the production delay. Verify with original event timestamps and a controlled Codex CLI probe. Distinguish injected faults from the original defect.
- [ ] SC2: The responsible component avoids the observed long stall. Verify by repeating a failing reproduction after the change. An unrelated timeout test does not satisfy this criterion.
- [x] SC3: iPhone Control describes short calls, independent elapsed-time checks, fresh observations after gaps, and safe recovery without replaying uncertain inputs. Verify by skill validation and independent review.
- [x] SC4: Existing phone behavior remains intact. Verify with existing helper tests and read-only runtime probes; preserve active phone ownership and global Codex configuration.

SC4 covers unchanged phone behavior. It does not claim that the rejected transport candidate passed its runtime test.

## Platform and stack

Codex CLI 0.163.0, gpt-6.1-sol, high reasoning; shared Python phone CLI; LFG task launcher.

## Verification evidence

| Criterion | Action and result | Evidence |
|---|---|---|
| SC1 | Original local work took 1.3 seconds; enclosing output arrived after 900.081 seconds. A fresh candidate reproduced the same shape: local work finished, then output arrived 60.544 seconds later. | Original triage/slow-tool-delivery.json; independent-audit.md; workspace-1-timing.json |
| SC2 | Not met. The 60-second profile recovered one delayed call, but another run stopped after 150.023 seconds with one command completed. | workspace-results.json; workspace-2-events.json |
| SC3 | Both skill validators passed. Independent content review passed. | independent-audit.md; shared skill and timing reference |
| SC4 | 54 driver and 27 helper tests passed. Read-only status probes succeeded. No phone input, host restart, or schedule edit occurred. Global config hash exactly restored. | phone-tests.txt; warm-up-tests.txt; workspace-2-ignored-config.json; withdrawal.json; independent-audit.md |

## Candidate results

| Attempt | Observed result | Decision |
|---|---|---|
| Existing provider versus explicit 60-second SSE overrides | Five image-and-command calls took 117.685 versus 45.646 seconds. Small comparison only. | Continue testing; no causal claim. |
| Project-local provider definitions | Codex ignored them. | Remove. |
| Project-local provider selection | Codex ignored it too. Official documentation confirms both restrictions. | Remove. |
| User-level provider plus explicit LFG launch selection | Injected silent SSE recovered after 60.225 seconds. One live run still lost substantial time. | Reject as a complete fix; do not activate. |
| Disable code_mode_host | Both probes completed zero commands. The wrapper reported that the host was disabled. | Reject. |

## Final changes

- Updated global iPhone Control with short-call and gap-recovery guidance.
- Added references/execution-timing.md with verified findings and safe resumption steps.
- Linked the guidance from Warm Up Tips.
- Withdrew candidate runtime settings and launcher source additions. Retained experiment sources under launcher-candidate for review.
- Restored the global config byte-for-byte. No candidate routing remains active.
- Preserved unrelated dirty files in the LFG checkout. No commit or push.

## Decision log

- Do not treat late result delivery as a failed phone input.
- Do not replay uncertain inputs or count a gap as playback.
- Do not relax task deadlines to hide infrastructure delays.
- Do not activate a candidate whose phone-workspace probe failed.
- Use file-based evidence first. The user's AGENTS.md requires approval before database operations.

## Blocker report: SC2

The original defect remains unresolved. Raw rollouts prove the waiting boundary, but do not expose the underlying transport failure.
The same completed-local/late-result behavior recurred during the fresh test. A shorter SSE timeout bounded one stall but did not remove continuation gaps.
The disabled-host experiment removed tool access, so it cannot serve as a working alternative.

The next useful evidence is Codex's local diagnostic database, /Users/eugenechan/.codex/logs_2.sqlite.
Read-only approval was requested. No database query has run.
The read should filter the affected session IDs and inspect transport, reconnect, and code-tool lifecycle errors without exposing credentials or unrelated content.

After locating the responsible component, test its repair with the same image/status probes, then a controlled warm-up.
Do not call the issue resolved from skill validation, a terminal exit code, or one fast run.
