# Where the latest iPhone execution gaps occurred

Research date: 24 October 2026. Read-only file and source review. No phone commands, session creation, database reads, configuration changes, restarts, or product edits.

## Finding

The strongest recent traces show two separate gaps outside phone gesture execution: completed local work whose enclosing result appears late, and silence with no outstanding tool. Replacing the phone bridge cannot, by itself, repair either waiting boundary.

The exact cause within Codex, its tool host, its response connection, or the provider remains unknown. The evidence does not establish that every recent gap has this cause. Navigation accuracy and video-app accessibility hangs are separate concerns worth benchmarking.

## Original production timestamps re-derived

This review parsed the original JSONL records again. It used timestamps, event types, tool status, tool inputs, and explicit outputs. It excluded private reasoning content and image payloads.

### Roxie fitness TikTok, 22 October

Original source:

`/Users/eugenechan/.codex/sessions/2026/10/22/rollout-2026-10-22T14-55-58-01a16265-255d-7252-9efc-9a82253f0c12.jsonl`

| Source line | UTC timestamp | Event |
|---|---|---|
| 1152 | 07:42:15.527 | Enclosing `exec` dispatched |
| 1153 | 07:42:15.538 | Nested ImageView completed |
| 1154 | 07:42:16.803 | Nested CommandExecution completed; duration 0.967445666 seconds |
| 1155 | 07:57:15.608 | Enclosing result recorded; script reports 1.3 seconds |

Total outer interval: **900.081 seconds**. Time after the final local completion: **898.805 seconds**.

The local command records evidence, attempts a tap, and takes a screenshot. The helper refuses the tap before execution because the post budget expired. The screenshot returns locally. There is no fifteen-minute swipe or tap in this interval.

Another gap spans lines 274–275: 07:01:00.993 to 07:16:04.063 UTC, **903.070 seconds**. Tracking tool call IDs and outputs from the start of the original file shows **no outstanding tool** during that interval. The previous enclosing call had already returned at line 273.

### Marisol Instagram, 22 October retry

Original source:

`/Users/eugenechan/.codex/sessions/2026/10/22/rollout-2026-10-22T14-50-40-01a16260-4ce4-7430-b598-5a782b5501f9.jsonl`

The evidence directory retains its earlier `2026-10-21/.../am` path. The production rollout timestamps establish the retry's actual date.

| Source line | UTC timestamp | Event |
|---|---|---|
| 552 | 07:28:27.581 | Enclosing `exec` dispatched |
| 553 | 07:28:27.933 | Nested command failed locally; duration 0.038149250 seconds |
| 555 | 07:37:20.231 | Enclosing failed result recorded; script reports 0.4 seconds |

Total outer interval: **532.650 seconds**. Delay after local command completion: **532.298 seconds**. The helper explicitly reports `Phase changed` and `action_state: not_executed`. The later image read fails because the refused screenshot did not exist. Neither event represents a running phone gesture.

Other original gaps have no outstanding tool:

- Lines 482–483: 07:01:01.551 to 07:16:04.063 UTC, **902.512 seconds**.
- Lines 551–552: 07:18:40.416 to 07:28:27.581 UTC, **587.165 seconds**.
- Lines 623–624: 07:41:34.120 to 07:57:23.223 UTC, **949.103 seconds**.

Both devices' sessions resume recording usage events at **exactly 07:16:04.063 UTC**. This supports a shared response or event-delivery problem. It does not identify the faulty component or prove a provider outage.

## Saved phone request metrics support the distinction

Recomputed from existing local `metrics.jsonl` files for **22 October 06:55–08:00 UTC**. These are completed HTTP requests across the device, rather than an exclusive per-run ledger. Percentiles use sorted observations and the lower rank.

| Device | Requests | Median | 95th percentile | Maximum | Recorded request errors |
|---|---:|---:|---:|---:|---:|
| hihi | 126 | 0.2807 s | 0.8958 s | 1.4724 s | 0 |
| dumb dumb | 328 | 0.2589 s | 0.9050 s | 1.9558 s | 0 |

Sources:

- `/Users/eugenechan/.iphone-control/by-device/9bd15b24af34bf92b8693ec0/metrics.jsonl`, lines 3552–3677: hihi.
- `/Users/eugenechan/.iphone-control/by-device/c4080ea8d06c2ea13f5f6e54/metrics.jsonl`, lines 1778–2105: dumb dumb.

W3C `/actions` maximums were **1.4724 seconds** and **1.4510 seconds**, respectively. Screenshot maximums were **0.5761 seconds** and **0.5272 seconds**.

These metrics measure Appium request completion. They do not prove that every input reached its intended target, that video played continuously, or that unfinished requests were absent. The original nested completion events provide the decisive evidence for the delayed-result intervals.

## Current driver safeguards and limits

Source root: `/Users/eugenechan/.claude/skills/iphone-control/scripts/`.

- `control_cli.py:42` implements current `status` through `Runtime.alive()`, mode, and startup metadata. The older `phone.py:311` branch is not the entry-point behavior: `phone.py:447–449` delegates to `control_cli.cli()`.
- `control_runtime.py:145–154` checks session health with a **five-second settings GET**. It avoids active-app geometry. A slow connection does not authorize creating another session.
- `control_runtime.py:93–143` uses a **30-second default HTTP timeout**, applies a remaining request budget, records request duration and endpoint, and marks uncertain mutations. The metric is written in `finally`, after the request returns.
- `control_runtime.py:61–76` uses a nonblocking lock per device. Another local operation receives `device_busy`, instead of silently queuing behind it.
- `control_cli.py:115–118` exposes an aggregate metrics summary. The underlying file retains endpoint, duration, bytes, and errors, but **no operation ID or outer call ID**. It cannot directly link each request to its enclosing agent tool call.
- `phone.py:96–115` sets Appium WDA launch and connection timeouts to **1,800,000 ms**. `control_runtime.py:231–252` allows a detached session startup request up to **2,400 seconds**. These startup and upstream limits differ from ordinary request budgets.
- A client timeout does **not** cancel an accepted server action. Lowering every timeout and retrying can duplicate inputs or leave work queued in Appium/WDA.
- `control_runtime.py:203–229` reuses an existing startup job. It does not spawn another on an uncertain connection. `control_cli.py:43–60` bounds a caller's startup poll to 0–60 seconds.

## Video mode: real bridge limitations, already partly avoided

The local skill documents video players blocking active-application accessibility calls for minutes. Setting the idle timeout to zero alone did not prevent that behavior. Source: `/Users/eugenechan/.claude/skills/iphone-control/SKILL.md:91–114`.

Current mitigation:

- `phone.py:413–416` pins WDA to SpringBoard and disables idle and animation waits in video mode.
- `control_cli.py:137–138` rejects ordinary accessibility commands before sending them in video mode.
- `control_workflows.py:101–108` uses SpringBoard geometry and forbids accessibility reads in video mode.
- `phone.py:418–433` sends W3C coordinate gestures. A swipe still includes a geometry GET followed by an action POST.
- `phone.py:434–436` launches an app through FlowDeck outside WDA. `control_cli.py:173–177` deliberately allows that escape outside the WDA operation lock.

Residual limitations: coordinates need fresh screenshots after layout changes; command acceptance does not verify navigation; losing video mode can reintroduce active-app queries. A different wrapper around WDA may retain the same underlying accessibility problem.

## Why the gaps persist

Current configuration was checked again on 24 October, printing only the selected provider and transport settings. `~/.codex/config.toml` selects `openai-long-timeout`, whose `stream_idle_timeout_ms` is **900000** and `supports_websockets` is **true**. Provider-specific request and stream retry overrides are absent.

The configured 900 seconds closely matches the production outer call's **900.081 seconds**. The prior 60-second candidate similarly yielded an outer call of **61.066 seconds**, with **60.544 seconds** after local completion. This is a strong timeout clue, not proof of the root cause: the recorded production events do not show which connection protocol handled the stalled request or an explicit timeout event. The setting describes stream idleness; it must not be relabeled a confirmed phone timeout.

The prior experiment did not yield a verified transport fix. Its shorter idle timeout recovered one fresh delayed-return case, but a second workspace still stopped after 150 seconds with only one successful status command. Disabling the code-mode host removed tool access. The candidate provider and launcher changes were withdrawn.

Evidence: `.codex/feature/iphone-execution-gaps/independent-audit.md:28–57,61–79`; `.codex/feature/iphone-execution-gaps.md:37–53,64–75`.

Skill recovery guidance remains, but guidance cannot resume an agent whose response connection or continuation is suspended. Do not claim an active mitigation from these experiments.

The earlier feature identified local Codex diagnostics as a possible next source. No database query was performed here. Existing approval requirements still apply.

## Benchmark recommendations

Keep phone control speed, navigation correctness, and agent responsiveness as separate measurements.

1. **Transport-only control.** Repeat a tiny local command and image read with no phone input. Record local completion, outer dispatch/result, and next agent action. Test sequential and concurrent sessions. Report every gap over 30 seconds, plus median, p95, and maximum. Verify the effective launch settings rather than assuming a config was loaded.
2. **Driver-only control.** During an explicitly reserved test, run a deterministic local controller against a harmless app. Measure request start/end separately from visible transition completion. Compare the current W3C video path with each candidate bridge on the same phone and OS.
3. **Navigation correctness.** Test repeated tab changes, back navigation, search-field focus, keyboard dismissal, and scrolling. Score intended screen reached, wrong target, no progress, uncertain action, and recovery time. Use fresh screenshots for final state verification.
4. **Video-specific control.** Compare the same actions with a playing video and a static screen. Confirm mode and active target. Avoid accessibility tree calls against a playing video unless this is a bounded, isolated hang test with a known escape.
5. **End-to-end control.** Only after both controls pass, run one controlled representative task. Measure the share of booked time lost to model continuation, outer delivery, local request work, app loading, observation, and intentional waits.

Add correlation IDs and monotonic timestamps to driver receipts, helper receipts, and outer tool lifecycle events. Save local receipts before returning tool output. A watchdog should identify where progress stopped; it must not blindly replay an uncertain input.

Suggested experiment acceptance criteria, to agree before running: zero duplicate inputs; no unexplained interval over 30 seconds; all expected screen transitions observed; no lost result; continued operations after the original image/status trigger. These are diagnostic criteria, not new social-task completion rules.

## Remaining unknowns

- Whether the underlying stall is the provider stream, client connection, code-tool host, image return, or another shared layer.
- Whether concurrency contributes. Synchronized timestamps are a clue, not a controlled experiment.
- Attribution for every Toni, Jess, and other recent session. Their report descriptions alone do not prove the same boundary.
- Comparative reliability of alternate bridges. No alternate bridge was installed or tested in this subtask.
- Navigation accuracy from request latency alone. Fast HTTP responses are not proof of correct taps.
