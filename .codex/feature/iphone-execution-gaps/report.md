---
title: Execution gaps reproduced; transport fix still unresolved
subtitle: 22 October 2026 · Codex CLI 0.163.0 · no candidate activated
template: doc
---

## Result

Local phone work finishes quickly, but Codex sometimes delivers its result much later.
We reproduced that pattern with a fresh image-and-command probe.
The exact transport defect remains unknown.

The shared skill now explains how to resume safely after a gap.
No transport override remains active. We restored the global configuration exactly.

## What the tests showed

| Test | Result | Meaning |
|---|---|---|
| Original production trace | Local work took 1.3 seconds; enclosing result took 900.081 seconds | Delay occurred outside ordinary phone execution |
| Fresh probe with shorter timeout | Local work finished; enclosing result followed 60.544 seconds later | Same delayed-result pattern reproduced |
| Second fresh candidate run | Stopped after 150.023 seconds; one status command completed | Shorter timeout did not solve all gaps |
| Silent-stream fault injection | Reconnected once after about 60 seconds and completed | Idle recovery works for that injected fault |
| Disable code host | Zero commands completed in either probe | This removed tool access and cannot serve as a fix |

Some gaps have no outstanding tool. Those need separate agent-continuation diagnostics.
One fast run does not establish reliability.

## Changes that remain

- iPhone Control checks elapsed time outside routine tool calls.
- After a gap, the agent checks the booking, ownership, and last local receipt.
- The agent takes a fresh observation before another input.
- Expired post timers cannot justify late engagement or playback credit.
- Warm Up Tips points to the same recovery guidance.

The driver code remains unchanged. Its 54 tests pass. All 27 warm-up helper tests also pass.
Both skill validators pass. Independent review accepts the recovery guidance.

## Candidate withdrawn

Codex ignored both attempted project-level provider configurations.
The corrected launcher candidate selected a user-level provider explicitly, but its runtime test still failed.
We removed the candidate provider, launch policy, and source additions.

The global configuration matches its original hash. No host restart or schedule edit occurred.
All phone operations in the tests were read-only status checks. We sent no phone input.
The experiment sources and failed results remain available for review.

The [official OpenAI reference](https://learn.chatgpt.com/docs/config-file/config-reference) defines the idle timeout and project-level provider restrictions.

## Remaining blocker

The independent verdict is PARTIAL. The execution-gap issue is not resolved.
The next useful evidence is Codex's local diagnostic database, filtered to these sessions and transport errors.
We requested approval because Eugene's AGENTS.md requires it before database operations.
No database query has run.

After identifying the responsible component, repair it and repeat the image/status test.
Then verify a controlled warm-up. Keep uncertain phone inputs out of automatic retries.
