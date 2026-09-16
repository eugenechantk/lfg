# Improvement Log — Session 20260829-nested-agents

## Tracker

- [ ] 2026-08-29 — A "shape reader" written for one variant swallowed a second variant that shares the shape (`toolUseResult.{agentId,status}`: sync completion vs async launch)
- [ ] 2026-08-29 — The live symptom disappeared mid-investigation; had to reconstruct the discriminating case from a truncated transcript

## Log

### 2026-08-29 — One reader, two payload shapes, no discriminator

**What happened:** `consumeParentEventLine` in `src/subagents.ts` read child lifecycle from
`toolUseResult.{agentId, status}`. That reader was added for *synchronous* subagents. Claude
Code later shipped *background* agents, whose launch receipt has the identical field shape
with `status: "async_launched"` and `isAsync: true`. `mapStatus` mapped the unknown string to
`"unknown"`, so every background agent was recorded terminal at launch —
`runningChildAgentCount: 0`, parent not busy, nothing nested in the iOS client.

**Why this was wrong:** the reader keyed on *field presence* (`agentId` && `status`), not on
what the row means. Any new status string silently becomes "unknown", and "unknown" is not
neutral here — it out-ranks the default `"running"` and erases live work. A discriminator
(`isAsync`) was sitting right there in the payload and went unread.

**What better looks like:** when parsing an upstream tool's payload, enumerate the observed
variants before writing the reader (`grep` the corpus for the field, count distinct values —
39 `async_launched` vs 2 `completed` here, a 20:1 ratio that would have been obvious). And
make unrecognised values *inert*: an unknown status should decline to record a lifecycle, not
record an unknown one. Fixed that way rather than by special-casing the one string.

### 2026-08-29 — The bug healed itself before verification

**What happened:** by the time the fix was ready, the three agents had finished and the real
transcript reported them "completed" under both old and new code — the live check no longer
discriminated.

**Why this matters:** running the fixed code against current state would have "passed" while
proving nothing (memory `verify-the-discriminating-case`).

**What better looks like:** transcripts are append-only, so the failing moment is recoverable
— truncate the parent `.jsonl` to just before the completion rows, copy the real sidecars,
pin the clock, and run HEAD (`git show HEAD:src/…`) against the fix side by side. That gave
`0 running / idle` vs `3 running / busy` on real data. Reach for transcript replay by default
for any transient session-state bug rather than trying to catch it live twice.
