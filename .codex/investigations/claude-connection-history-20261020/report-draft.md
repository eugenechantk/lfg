---
title: Claude connection interruptions
subtitle: Local history audit on 20 October 2026
template: doc
---

## Findings
Scanned 3,337 Claude transcript files on this Mac. Found 11 distinct connection interruptions in 11 original sessions.

One error also appears in a fork. It counts once. Eight original transcripts contain a later Claude response. Three do not.


## Every interruption
Times use Hong Kong time. A later response shows activity resumed; it does not prove the task finished.


| Date and time | Session | Project | Failure | Later response |
|---|---|---|---|---|
| 09-23 11:02 | 3e037df2 | fiftyworkout | Connection lost during response | Yes |
| 09-23 16:31 | 63da2ce2 | fiftyworkout | Connection lost during response | Yes |
| 09-24 18:01 | 9aba1886 | fiftyworkout | Connection lost during response | Yes |
| 09-28 17:11 | 516ffc45 | ai-weather-girl | Connection lost during response | Yes |
| 09-29 23:40 | f8bdbca5 | apple-wallet-card-art-ios | Connection lost during response | Yes |
| 10-07 22:56 | 787a2e54 | SleepingBeauty | Connection reset | Not observed |
| 10-07 23:00 | ab09cd87 | SleepingBeauty | Connection reset | Not observed |
| 10-09 14:23 | 6d840502 | lfg | Connection reset | Not observed |
| 10-15 16:26 | 59836304 | lfg | Connection lost during response | Yes |
| 10-17 00:05 | 9302d813 | fiftyworkout | Connection lost during response | Yes |
| 10-20 20:52 | b7c3ad00 | fiftyworkout | Stream stalled | Yes |

## What Autopilot does today
The current Autopilot registry contains one step: retitle-sessions. The local persisted state also lists only that step.

Its default loop runs every ten minutes. No registered step detects connection errors or continues interrupted sessions.


## Recommended recovery step
Add connection recovery to Autopilot. Start with explicit Claude connection errors only.

On each tick, inspect new transcript records. Consider only sessions whose current stopping point is a connection error.

Skip errors followed by newer activity, intentional stops, pending user messages, or running child agents.

Persist one recovery attempt per error ID. Recheck ownership and delivery before sending a continuation.

Ask Claude to check completed tool results and external actions before continuing. Increase delays after repeated failures.

Notify the user when the retry budget runs out. Do not revive every historical interrupted session.


## Scope and evidence
This audit covers retained Claude transcripts under /Users/eugenechan/.claude/projects. It includes subagent files; none contained matching structured connection errors.

It excludes account limits, authentication failures, invalid requests, and errors quoted in normal conversation.

Other Macs, deleted transcripts, and Codex history were not audited. Connection messages do not prove whether the network or Anthropic caused the failure.

The events.json file stores all matches with exact transcript paths and line numbers. The unique-events.json file removes the inherited fork duplicate.

The source registry is src/autopilot/tick.ts. The runtime state is /Users/eugenechan/.lfg/autopilot-state.json.

This audit did not resume, interrupt, or send instructions to any session.

