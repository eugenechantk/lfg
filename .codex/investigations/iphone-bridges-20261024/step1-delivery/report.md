---
title: Step 1 — locate the execution gaps
subtitle: Transport failure reproduced · HTTP-only switch failed acceptance · no production change
lang: en
template: doc
theme: shadcn
---

## Decision

```callout warn Keep the transport defect open
A diagnostic fork failed before sending any phone command.
Codex reported a WebSocket broken pipe, then fell back to HTTPS.
The HTTP-only fork also failed acceptance. No transport fix is active.
```

The historical gaps cross several boundaries. Replacing the phone bridge cannot fix all of them.
Continue the independent phone comparison while preserving the original sessions and schedules.

## Historical boundary

The extractor reads timestamps, tool identities and completion metadata. It omits private reasoning and image payloads.
Every nested completion had exactly one outstanding parent candidate. The table includes intervals overlapping the booked phone window.

| Latest run | Outer results delayed above 30 seconds | Longest wait after local completion | Longest gap with no recorded tool outstanding |
|---|---:|---:|---:|
| Toni AM | 0 | None found | 327.221 s |
| Marisol AM | 2 | 532.298 s | 949.103 s |
| Jess AM | 2 | 905.252 s | 91.218 s |
| Toni PM | 4 | 898.927 s | 914.829 s |
| Roxie fitness TikTok | 1 | 898.805 s | 903.070 s |

Five delayed-result intervals exceeded five minutes. Their nested local spans were below two seconds.
Nine intervals exceeded thirty seconds. Some gaps continued after the booking expired.
A gap without a pending tool does not establish a network cause.

Evidence: [timing summary](historical-timing-summary.json), per-session timing JSON files with original paths and line numbers.

## Controlled reproduction

| Diagnostic | Outcome | Duration | Interpretation |
|---|---|---:|---|
| Fresh inherited configuration | Four rounds passed | 40.274 s | Small fresh workload stayed responsive |
| Two concurrent fresh launches | Both passed four rounds | 41.080 / 38.450 s | Small concurrent workload did not reproduce the stall |
| Fresh HTTP-only, inherited idle timeout | Four rounds passed | 46.175 s | One healthy launch cannot establish a fix |
| Fresh launch with an archived phone image | Four rounds passed | 56.634 s | That image alone did not reproduce the stall |
| Jess history fork, inherited configuration | Zero commands; harness stopped | 150.051 s | A large existing history can reproduce a pre-command stall |
| Jess history fork, HTTP-only, 60-second idle timeout | Zero commands; harness stopped | 210.054 s | The proposed switch failed acceptance |
| Jess history fork, retries disabled | Zero commands; harness stopped | 180.098 s | Explicit WebSocket error and HTTPS fallback observed |

The final fork recorded a WebSocket request failure after 108.436 seconds.
At 115.373 seconds, Codex reported “Broken pipe” and fallback to HTTPS.
The harness later stopped the child. Exit code zero after shutdown does not count as a pass.

The forks preserve the original Jess session. None sent phone input.

## What this does and does not establish

The failed fork has about 14 MB of history, including 101 embedded images totaling 11.8 MB.
The original first delayed tool result occurred with only two earlier images totaling about 111 KB.
Therefore, the fork does not prove that history size caused the original early stall.
The archived-image control passed. The control did not establish an image defect.

Historical input context ranged from about 74,000 to 206,000 tokens at the selected delays.
The reported context window was 475,000 tokens. No compaction appeared in those inspected intervals.
That weakens a simple context-window explanation, but does not exclude provider processing or transport delays.

The configured 900-second idle timeout resembles several gaps. That remains a clue, not a root-cause finding.
An idle timeout cannot guarantee a bound on every request phase, including a wait before response streaming begins.

## Approved diagnostics

The user approved all operations. Read-only database queries used mode=ro and query_only.
The retained diagnostic rows start on 23 October at 04:42:31 UTC.
The selected failures occurred on 22 October. No matching historical rows remained.

No database write occurred. [Retention evidence](database-retention.json), [read scope](DATABASE-READ-SCOPE.md).

The selected power-log window, 22 October 14:45–16:10 HKT, contains no Sleep, Wake or DarkWake transition.
That supplies no evidence for host sleep in that window. It does not exclude every host fault.
[Power summary](power-summary.json).

## Verification and next repair

Five fresh launches passed twenty marker rounds and successful commands. The original four also have correlated image-view acceptance checks.
Three history forks failed their bounded acceptance windows.

Every launch retained the original global configuration hash. No schedule, original session or production setting changed.
The collector uses loopback only and retains allowlisted metadata, sanitized error categories and timestamps.
It omits prompts, arguments, outputs, credentials and headers. Batched collector arrival times are separate from original event timestamps.

The next repair must address the measured pre-command or result-delivery boundary.
Capture one natural recurrence with this metadata tracing, then distinguish upload, provider response, reconnect and tool-result delivery.
Keep any timeout or HTTP-only change scoped until the history reproduction and fresh controls both pass.

[CLI configuration reference](https://learn.chatgpt.com/docs/cli/reference), [diagnostics documentation](https://learn.chatgpt.com/docs/config-file/config-advanced).
