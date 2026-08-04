# Architecture analysis — (1) messages/transcript, (2) connection/status

2026-08-04. Read of `src/` + `ios/` as they stand on `main` + working tree.

Your instinct is right, but the diagnosis is more specific — and more fixable —
than "hotfixes on hotfixes." In **both** subsystems the actual pattern is the
same, and it is not sloppiness:

> A better architecture was designed and correctly built, the old one was never
> removed, and both are still running. Every subsequent bug then has to be fixed
> twice, in two places with different semantics — and fixing it in one is what
> makes it look like it "came back."

That is why fixes feel like they don't stick. It isn't patch quality. It's that
there are two systems answering the same question, and the client picks a
different one depending on which screen you're on.

---

## Method

Evidence gathered rather than assumed:

- churn per file over 6 months (`git log --name-only`)
- density of *retrospective* comments (`used to` / `no longer` / `instead of` /
  `stranded` / `silently`) — prose that documents a past bug rather than present
  design. This is the most reliable accretion marker in this repo.
- every transcript read site, every route registration, every declared piece of
  connection state.

| File | Lines | Commits/6mo | Retro-comments |
|---|---|---|---|
| `src/commands/serve.ts` | 2822 | 28 | 14 |
| `ios/LFG/SessionStore.swift` | 2499 | 23 | 27 |
| `src/sessions.ts` | 1833 | 20 | 13 |
| `src/tmux.ts` | 1073 | 12 | 18 |
| `src/sendq.ts` | 790 | 6 | 21 |

`sendq.ts` at 2.7% retro-comments and `SessionStore.swift` at 2499 lines are the
two files where the accretion is densest.

---

# Part 1 — Messages & transcript

## 1.1 The load-bearing problem: two live-delivery pipelines, both in production

There are two complete, independent implementations of "push message/busy/prompt
deltas to a client."

**Old — per-connection pump.** `GET /api/live/stream?ids=…`
(`serve.ts:2503`). Every SSE connection runs its *own* transcript-tail loop and
pane poll with private delta maps (`serve.ts:2532, 2623, 2708, 2731`). Cost is
CPU ∝ connections × sessions; all delta state dies on disconnect. There is also
a per-session variant, `GET /api/sessions/:id/stream` (`serve.ts:2680`).

**New — journal + one global pump.** `src/journal.ts` + `src/journal-pump.ts`,
read via `GET /api/events?since=<seq>` (`serve.ts:1541`) and
`/api/events/page` (`serve.ts:1512`). One loop per host observes every session
and appends *state changes* to a bun:sqlite journal with a monotonic `seq`.
Clients are just cursors: disconnecting and reconnecting costs nothing and loses
nothing. It is explicitly designed against
`.claude/brainstorm/multihost-first-rearchitecture.md §6.1`, has a retention
policy, and has a correct cross-host rule (a host journals only sessions it
executes, so two hosts can't double-deliver).

The new one is genuinely good. The problem is `serve.ts:891-893` says the quiet
part out loud:

```
// Event journal + the one global session pump (replaces per-connection pump
// loops for /api/events consumers; /api/live/stream keeps its own for
// back-compat until old clients are gone).
```

"Until old clients are gone" never happened, because the old client is **your
web UI**: `web/src/App.tsx:783` still opens
`new EventSource('/api/live/stream?ids=…')`.

So today:

| Client | Delivery path | Pump |
|---|---|---|
| iOS | `/api/events` (cursor) | journal pump |
| Web | `/api/live/stream?ids=` | per-connection pump |

**This is the root of "fixed bugs come back."** A message-normalisation, busy-
detection or prompt-detection fix applied in `journal-pump.ts` does not reach the
web UI, and vice versa. They share `normalizeLineMessages` (good) but *not* the
surrounding busy/prompt/queue logic, which is reimplemented on both sides.

Corroborating detail: `LFGClient.liveStream(ids:)` (`LFGClient.swift:366`) is now
**dead code on iOS** — `SessionStore` moved to `HostLink`/`/api/events`. The
comment at `SessionStore.swift:163-164` still describes the old
`/api/live/stream` + "24-id cap" model and is contradicted by the comment
immediately below it at 165-168. Two adjacent comments, two architectures.

## 1.2 No transcript abstraction — the tail-read is copy-pasted 6×

Every question about a transcript re-opens the file, picks its own byte window,
re-splits and re-scans. In `sessions.ts` alone:

| Function | Line | Window |
|---|---|---|
| `lastUserText` | 922 | last 256 KB |
| (second reverse-scan) | 957 | last 256 KB |
| `lastAssistantModel` | 1014 | last 256 KB |
| `previewLast` | 1041 | last 32 KB |
| `recentMessages` | 1684 | last 256 KB (configurable) |
| `pendingToolPrompt` | 1759 | last 128 KB |
| `snapshotMessages` | 1706 | head cap |
| `cwdForTranscript` | 1539 | first 64 KB |
| `firstUserTextFromTop` | 397 | first `CODEX_PROMPT_READ_BYTES` |
| `modelAliasForTranscript` | 1042 | last 256 KB |

All share the identical idiom — `Bun.file(p)` → `size` → `Math.max(0, size - N)`
→ `.slice(start).text()` → `split("\n").filter(Boolean)` → reverse scan — with
**six different values of N**.

Two consequences, both of which you have already felt:

1. **Window misses are silent.** If the thing being looked for falls outside the
   hand-picked window (one long tool output will do it), the function returns
   `null` and the caller renders "no model" / "no last message" / no prompt. The
   natural fix is to bump the constant — which is exactly the hotfix-on-hotfix
   shape, and it fixes one call site out of ten.
2. **Cost.** `listSessions()` performs **4 independent tail reads per session per
   pass** (`previewLast`, `lastUserText`, `lastAssistantModel`, plus
   `firstPromptTitle` reading the *head*). At ~15 live sessions that is ~60 file
   slices per pass, up to 256 KB each, on the single Bun event loop — the same
   loop the project CLAUDE.md already flags as saturable. Transcripts here reach
   18 MB.

## 1.3 Accretion artifacts (concrete, small)

- **`GET /api/sessions/:id/messages` is registered twice** — `serve.ts:2289` and
  `serve.ts:2484` — with byte-identical bodies (`messagesResponseForSession(m[1],
  url)`). The second is unreachable dead code. Two people (or two sessions)
  added the same route.
- `sendq.ts` carries 21 retrospective comments in 790 lines. Each documents a
  real trap (rating overlay swallows Enter; question selectors need Escape;
  don't gate Enter on re-finding your needle). They are *correct*, but they are a
  changelog embedded in control flow — the function has become a list of
  historical exceptions rather than a model of the interaction.

## 1.4 What to do (subsystem 1)

**Do first — retire the second pipeline.** Port `web/src/App.tsx` to
`/api/events` (+ `/api/events/page` for backfill), then delete
`/api/live/stream`, `/api/sessions/:id/stream`, their per-connection tail loops,
and `LFGClient.liveStream(ids:)`. This is the single highest-value change in
either subsystem: it removes an entire duplicate implementation, deletes the
"fixed it but it came back" class outright, and drops server CPU from
O(connections × sessions) to O(sessions). The journal side is already built,
tested and shipping to iOS — this is finishing a migration, not starting one.

**Do second — one transcript reader.** Introduce a `Transcript` module owning
*all* file access, with one API (`tail(n)`, `head(n)`, `page(before, limit)`,
`scanBack(predicate)`) and one window policy that **grows until it finds the
answer or hits the file head**, instead of ten fixed constants that fail
silently. Then make `listSessions()` do **one** read per session and derive
last/lastUser/model/title from that single pass. Fixes the silent-miss class and
the per-poll cost together.

**Do third (cheap).** Delete the duplicate `/messages` route; fix the stale
`SessionStore.swift:163` comment.

---

# Part 2 — Connection & status

## 2.1 The problem: ~8 representations of "is this host up", no state machine

There is no single owner of host health. Instead, spread over three files:

| # | Signal | Where | Meaning |
|---|---|---|---|
| 1 | `reachabilityByHost` | `SessionStore` | what the UI renders |
| 2 | `failuresByHost` + `failureThreshold = 3` | `SessionStore:34,40` | display debounce |
| 3 | `HostProbePolicy.failureThreshold = 4` | `HostHealth:32` | probe backoff |
| 4 | `coldProbeEveryNTicks = 5` | `HostHealth:32` | cold retry cadence |
| 5 | `HostLink.isHealthy` / `unhealthySince` | `HostLink:70` | link-level health |
| 6 | `unhealthySinceByHost` | `SessionStore:177` | **duplicate** of 5 that outlives link teardown |
| 7 | `networkPathSatisfied` (NWPathMonitor) | `SessionStore:184` | device network |
| 8 | `lastElementAt` + `quietRedialAfter` | `HostLink:118` | stream-quiet detector |

Plus `bannerRecheck` timers (`:173`), `catchUpBuffers` (`:180`),
`reconnectBurstTask` (`:190`), `backgroundStopTask` (`:187`) — and, server-side,
a per-session `status`/`statusReason`/`statusDetail` triple *and* a separate
`busy` boolean.

Number 6 is the tell. Its own comment:

```
/// Unlike `HostLink.unhealthySince`, this survives link teardown/rebuild
/// while the app remains alive.
```

That is a second clock added because the first one was in an object with the
wrong lifetime. The correct fix is to move health ownership out of the
per-connection object; the shipped fix was to mirror it upward. Now two clocks
must agree, and the banner is a function of both.

This matches the standing memory note that the Pro-disconnect banner is a
*client recovery* bug, not a server or network one — with this many
representations, "recovered" is not a single transition anyone can assert.

## 2.2 Constants coupled by prose across files — one already stale

`HostHealth.swift` documents its own landmines:

- `HostProbePolicy.failureThreshold` **must stay strictly greater than**
  `SessionStore.failureThreshold`, or a host freezes one short of "offline" and
  the banner never appears. Today: 4 vs 3. Enforced by a comment in a different
  module from the value it constrains. Nothing fails if someone changes 3 to 4.
- `coldProbeEveryNTicks` is a **tick count**, so its meaning depends on the poll
  interval in `SessionStore.start()`. The comment warns this was once 10 ticks =
  10 minutes. The loop is now 60s (`SessionStore.swift:392`) and the value is 5 —
  so a cold host is still retried only every **5 minutes**.
- `pollTimeout: 4` is justified as "the next tick is 3s away"
  (`HostHealth.swift:28-30`). **The tick is 60 seconds.** This comment is stale
  by 20×, and it is the stated rationale for the constant.

Three constants, two files, coupled by English, one rationale already false.
This is precisely the machinery that produces "we fixed the banner and it broke
again."

## 2.3 Session status is a prose classifier

`computeStatus()` (`sessions.ts:120`) decides whether a session is `blocked` by
**regex-matching the English text of the last assistant message**:

```
/issue with the selected model|may not have access to it\.?\s*run \/model|
 claude[\w.\s-]*is (currently )?unavailable|\bis no longer (available|supported)\b/i
```

The comments show it has already been hotfixed twice: first gated on
`last.apiError` so a session *debugging* a credit error stops tripping "build
paused", then narrowed so "a normal sentence containing model + unavailable
can't trip it." Both fixes are correct. The design is the problem: every new
upstream error wording is a new regex, and every session that *discusses* errors
is a false positive waiting to happen.

## 2.4 What to do (subsystem 2)

**Do first — one host health state machine.** A single `HostState` enum
(`connecting / live / degraded(since:) / offline(since:) / noNetwork`) owned by
`SessionStore`, with `HostLink` reporting *events* (`connected`,
`elementReceived`, `failed(error)`, `closed`) and holding **no** health opinion
of its own. Every current signal becomes either an input event or a derived
property. The banner reads one value. This deletes #5/#6's dual clock and makes
"recovered" a single, assertable transition — which is what the current banner
bug actually needs.

**Do second — one policy struct, derived not duplicated.** Put the thresholds in
one place, express cadence in **seconds not ticks**, and derive the probe
threshold from the display threshold (`probeThreshold = displayThreshold + 1`)
so the invariant is code, not a comment. Add the test that fails when they
cross. Fix `pollTimeout`'s stale rationale while you're there.

**Do third — stop classifying prose.** `status` should come from structured
signal only: the transcript's `isApiErrorMessage` flag plus the error `type`/
`code` Claude Code already emits. If a needed field isn't in the transcript,
treat "unknown blocked reason" as a first-class state and show the raw error,
rather than pattern-matching sentences. Keep the regexes only as a
last-resort labeller for display text, never as the gate.

---

# Sequencing

If only one thing gets done: **retire `/api/live/stream`** (port the web UI,
delete the old pump). It is the largest single source of duplicated behaviour,
the migration is already 80% done, and it directly causes the "we fixed this
already" pattern.

Then, in order of value per unit of risk:

1. Retire the second delivery pipeline (Part 1.4).
2. One host health state machine (Part 2.4) — this is what the disconnect banner
   is waiting on.
3. One transcript reader with a growing window (Part 1.4) — kills the silent-miss
   class and the per-poll read storm together.
4. Structured session status (Part 2.4).
5. Housekeeping: duplicate `/messages` route, stale comments, coupled constants.

**What is *not* wrong:** `normalizeLineMessages` as the single line parser, the
journal design itself (seq cursors, retention, the one-host-journals-what-it-
executes rule), `HostLink`'s reconnect/backoff loop, and the `sendq` confirm
strategy (transcript growth for idle, composer-cleared for busy). These are
sound. The problem is uniformly that their predecessors are still running
alongside them.
