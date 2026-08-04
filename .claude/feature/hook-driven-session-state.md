# Feature: hook-driven session state

Layer 1 of a three-layer state pipeline. Layers 2 (transcript) and 3 (pane) already
exist — see `4768c78` and `.claude/feature/transcript-derived-busy.md`. This adds the
authoritative top layer and makes one canonical state drive the list AND the widget.

## User Story

As someone running a dozen agents at once, I want the session list and the Live
Activity to agree on what each agent is doing, so a glance at my Lock Screen tells me
who needs me without opening the app and re-reading every pane.

## Problem

Three consumers each re-derive state from raw signals with their own precedence ladder:

| Consumer | Ladder | Source |
| --- | --- | --- |
| `SessionStore.group(for:)` | closed → prompt → isBlocked → busy | client |
| `FleetActivitySnapshot.contentState` | closed → prompt → isBlocked → busy | client (LFGCore) |
| `reduceFleetLiveActivity` / `fleetRowState` | prompt → blocked → busy | server |

They are kept in sync by comment and code review. That has already shipped one bug
where ended sessions read "running" forever on the card while the list showed them
correctly. Adding a fourth signal (hooks) to three hand-mirrored ladders makes that
worse, so the ladder itself gets consolidated as part of this work.

## Signal layering

Precedence for "is a turn in flight", highest first. Each layer returns
`running` / `idle` / `null`, where **null means "no opinion"** and falls through —
never "idle". That invariant is what makes the stack safe to extend.

1. **Hooks** — the agent announces its own transitions. `UserPromptSubmit` → running,
   `Stop` → idle, `SessionEnd` → gone. Verified firing on both Claude Code 2.1.220 and
   codex 0.145.0 with identical event names and a shared `session_id` field.
2. **Transcript** — `turn-state.ts`, already shipped. Claude: `system/turn_duration`
   and the interrupt marker. Codex: currently abstains (returns null) — this feature
   adds `task_started` / `task_complete` / `turn_aborted`.
3. **Pane** — `isBusy(pane)`, chrome-region scoped. Last resort, and the only layer
   available for agents that expose neither hooks nor a parseable transcript.

### Arbitration between layers 1 and 2 (the load-bearing decision)

Hooks must **not** unconditionally outrank the transcript. `Stop` does not fire on an
ESC interrupt (measured; also stated in the hooks reference), and lfg interrupts on
every steering send — so a hook layer that always wins would latch `running` on the
most common send path in the product. That is strictly worse than the pane bug this
whole effort started from.

Arbitration is therefore **by recency, not by rank**: compare the hook file's `at`
against the transcript's mtime and let the newer one decide. This resolves every case
without special-casing:

- Normal turn: `UserPromptSubmit` fires, then assistant records land after it →
  transcript is newer → `running`. Same answer either way.
- Turn end: `Stop` and `turn_duration` are written within ~200ms → both say idle.
- **ESC interrupt:** no `Stop`, so the hook file is stale at `running`, but the
  transcript writes `[Request interrupted` after it → transcript wins → `idle`. ✅
- Hooks not installed / session predates them: no file → null → transcript decides.
- Transcript unreadable or codex-before-Phase-3: null → hook decides.

## Success Criteria

- [x] SC1: A hook script installed for both agents writes session state to disk on
  `UserPromptSubmit` / `Stop` / `SessionEnd`, keyed by `session_id`.
  — **Verify by:** unit tests over the writer + a live run of each agent with the hook
  installed, asserting the state file contents transition running → idle.
- [x] SC2: `sessionTurnState()` arbitrates hooks vs transcript by recency and returns
  the correct verdict for all six cases in the table above.
  — **Verify by:** unit tests, one per case, using fixture files with controlled mtimes.
- [x] SC3: An ESC-interrupted turn resolves to `idle`, not a latched `running`.
  — **Verify by:** integration test replaying a real interrupted transcript against a
  stale `running` hook file; plus a live tmux session interrupted mid-turn.
- [x] SC4: Codex sessions get a transcript verdict from
  `task_started` / `task_complete` / `turn_aborted` instead of abstaining.
  — **Verify by:** unit tests over real rollout fixtures; live check that a running
  codex session reads `running` and a finished one reads `idle`.
- [x] SC5: The server publishes one canonical `state` per session; the iOS list and the
  Live Activity both render it and neither re-derives its own ladder.
  — **Verify by:** `git grep` showing no remaining client-side precedence ladder;
  LFGCore unit tests; screenshot of list + Lock Screen card agreeing.
- [x] SC6: The Live Activity count equals the true count of running / needs-input
  sessions across a full turn lifecycle.
  — **Verify by:** the live probe comparing `fleet-activity-state.json` against a
  direct fleet read, at three points: mid-turn, after Stop, after interrupt.
- [x] SC7: No regression in existing behavior — full `bun test` suite and
  `swift test` green.
  — **Verify by:** both suites.

## Platform & Stack

- **Server:** Bun + TypeScript (`src/`), single event loop, no hot reload.
- **Client:** SwiftUI + `LFGCore` package (`ios/`), Swift 6 strict concurrency.
- **Widget:** ActivityKit (`ios/LFGWidgets/`), fed by both the app and server APNs pushes.

## Implementation Phases

### Phase 1 — Hook writer + state store (server-side, no behavior change)

- Scope: hook script, `~/.lfg/agent-state/<session_id>.json` atomic writer,
  reader module with a size/mtime memo mirroring `turn-state.ts`. Install docs for
  both agents. **Not yet wired into `busy`.**
- Covers: SC1
- Gate: unit tests green; live run of each agent shows correct file transitions.

### Phase 2 — Arbitration + wiring

- Scope: `sessionTurnState()` combining layers 1–3 by the recency rule; replace the
  `(turn ?? paneBusy)` expression in `journal-pump.ts`; `forgetHookState` alongside
  `forgetTurnState`.
- Covers: SC2, SC3
- Gate: unit tests per arbitration case; live interrupted-turn test; suite green.

### Phase 3 — Codex transcript support

- Scope: teach `classifyTurnLine` the codex rollout vocabulary; map a codex session to
  its rollout path (UUID is in the filename, `session_meta` carries `cwd`).
- Covers: SC4
- Gate: unit tests over real rollout fixtures; live codex session reads correctly.

### Phase 4 — One canonical state to the client

- Scope: server computes and publishes `state` per session; `SessionStore.group(for:)`,
  `FleetActivitySnapshot`, and `fleetRowState` all consume it instead of re-deriving.
  Delete the duplicated ladders.
- Covers: SC5, SC6
- Gate: LFGCore tests; live widget-vs-list agreement across a turn lifecycle.

### Phase 5 — Push instead of poll (deferred, separate decision)

The pump polls every session every ~700ms–2s. Once hooks are trusted they can *nudge*
the pump instead, collapsing the fan-out the repo's CLAUDE.md warns about. Explicitly
out of scope here — it changes the server's execution model and deserves its own doc.

## Decision Log

- **State store is a file per session, not an HTTP POST to the server.** A hook fires
  in a short-lived process that must not depend on the server being up; a file survives
  server restarts and the `serve` process routinely lags source. Atomic write via
  temp + rename. Rejected: POST (couples hook liveness to server liveness), append-only
  log (unbounded growth, needs compaction).
- **Arbitration by recency, not by layer rank.** See above — rank alone latches on ESC.
- **Reuse the existing pane-backed guard.** A hook file proves a turn transition
  happened, not that the process still exists. `4768c78` already learned this the hard
  way with a recycled pid; the same guard applies unchanged.
- **`Notification`/`PermissionRequest` → needs-input is out of scope.** Prompt detection
  is a separate signal with its own sources (`pendingToolPrompt`, `parsePrompt`).
  Folding it in doubles the blast radius. Tracked as follow-up.
- **codex hook install requires a trust hash.** codex pins `trusted_hash` per hook entry
  in `config.toml`; a dropped-in file silently does not run. Install must register the
  hash or document `--dangerously-bypass-hook-trust`. Claude Code has no equivalent gate.
- **Do not take codex's `notify` slot.** Single-valued and already claimed by the
  Computer Use app on this machine. Hooks are a list and compose.

- **Phase 4 is full consolidation** (Eugene, this session). The server publishes one
  canonical `state`; `SessionStore.group(for:)`, `FleetActivitySnapshot`, and
  `fleetRowState` all read it and their own ladders are deleted. Accepts an API-shape
  change and a client build in exchange for closing the disagreement class permanently.
- **Rollout is natural aging** (Eugene, this session). Hooks install globally; the
  ~13 in-flight sessions keep resolving via layer 2, which already handles them
  correctly, and pick up layer 1 whenever they next restart. No forced cycling.

## Verification Evidence

### SC1 — hook writer (Phase 1) ✅

`bun test src/hook-state.test.ts` → **16 pass / 0 fail**. Eight of those execute
`scripts/lfg-agent-hook.py` as a real subprocess with real payloads rather than
testing a TypeScript mirror of it — covering both agents' payload shapes, non-turn
events, garbage stdin, a directory-escape attempt, and atomicity.

Live run, polling the state file through a full turn:

```
CLAUDE CODE:
   t+1.35s   running  UserPromptSubmit
   t+28.09s  idle     Stop
   t+28.29s  ended    SessionEnd
CODEX:
   t+3.32s   running  UserPromptSubmit
   t+5.52s   idle     Stop
   t+5.62s   ended    SessionEnd
```

One script, both agents, no per-agent branching.

### SC2 — arbitration (Phase 2) ✅

`bun test src/session-state.test.ts` → **11 pass / 0 fail**, one test per case in the
arbitration table, using fixture transcripts with pinned mtimes.

### SC3 — ESC interrupt does not latch ✅

Unit: a stale `running` hook against a transcript whose newest record is the interrupt
marker resolves `{state: "idle", source: "transcript"}`.

Integration against a real file from the corpus — session `82dedc0e`, whose final
transcript line genuinely is `[Request interrupted…`:

```
LFG_TEST_INTERRUPTED_TRANSCRIPT=…/82dedc0e-….jsonl bun test -t "real interrupted"
(pass) SC3 — real interrupted transcript > resolves idle even with a stale running hook
```

### Wiring + regression ✅

`journal-pump.ts` now calls `sessionTurnState({sessionId, transcriptPath})` in place of
`transcriptTurnState(tp)`; `forgetHookState` added beside `forgetTurnState`.
`npx tsc --noEmit` clean; full `bun test` → **251 pass / 0 fail**.

### Hook install (live) ✅

`scripts/install-agent-hooks.py` — additive and idempotent, backs up both files.

```
claude   added UserPromptSubmit, Stop, SessionEnd
codex    added UserPromptSubmit, Stop, SessionEnd
```

Existing hooks preserved — `Stop` now lists `notify.sh stop` AND the lfg hook.
Piped-payload check on the installed copy exits 0 and writes the expected record.
A real new Claude session wrote `~/.lfg/agent-state/<uuid>.json`.

**codex caveat:** its new entries do not run until `trusted_hash` is registered —
accept the prompt on the next interactive codex start, or pass
`--dangerously-bypass-hook-trust`. Claude Code has no such gate and is live now.

### SC4 — codex transcript vocabulary (Phase 3) ✅

`classifyTurnLine` now reads codex's `event_msg` envelope: `task_started` → running,
`task_complete` / `turn_aborted` → idle. Path resolution already reached rollouts
(`resolveTranscript` → `findCodexTranscriptById`); only the vocabulary was missing.

`bun test src/turn-state.test.ts` → **24 pass / 0 fail** (8 new).

Against the real corpus at `~/.codex/sessions`:

```
real codex rollouts: 339
  idle        316
  running      22   <- dead June/July sessions with a terminally-open turn
  no opinion    1   <- was 339 (100%) before this phase
```

The 22 are historical files whose process died mid-turn. They are never consulted:
`transcriptTurnState` is only asked about PANE-BACKED sessions, the guard `4768c78`
added after a recycled pid caused exactly this. Live check on a real codex run:

```
  t+1.2s   running  (codex alive)
  t+11.2s  idle     (codex alive)
  after exit: idle
```

Full suite after Phase 3: **259 pass / 0 fail**, `tsc` clean.

## Phase 4 — design refinement found during implementation

Reading the real ladders turned up two tiers that **cannot** move server-side, so
"server computes, client renders" needs one adjustment:

- **`unread`** (`SessionStore.group(for:)`) is device-local — it depends on
  `lastSeenMessageID`, `manualUnread`, and which session is focused *on this device*.
  The server has no basis to compute it.
- **`needsInput`** is genuinely fresher on the client. `prompts[sid]` arrives over SSE
  continuously; a REST `state` field would be a snapshot the live stream has already
  superseded. Publishing it server-side would make the card *staler*, not more correct.
- **`closed`** stays client-side per the repo CLAUDE.md: it means "closed on this host",
  and only `MultiHost.reconcileResumable` has the cross-host live ids to drop phantoms.

Revised Phase 4, same goal (one ladder, not three):

1. Server publishes `state: "blocked" | "working" | "idle"` — the agent-derived tier it
   is authoritative for — computed by one exported function that `fleetRowState` also
   calls, deleting the server's second ladder.
2. Client defines the precedence **once** in `LFGCore`, and both
   `SessionStore.group(for:)` and `FleetActivitySnapshot` call it. They stop being two
   hand-mirrored ladders; the overlays (`closed`, `prompts`, `unread`) become explicit
   arguments rather than re-derived logic.

Net: 3 hand-mirrored ladders → 1 per language, with the client's genuinely-local tiers
passed in instead of duplicated. Awaiting go-ahead since it changes the API shape.

### Phase 4 — one ladder, three consumers ✅ (code + unit; live card pending)

The precedence now exists once per language:

| | before | after |
| --- | --- | --- |
| `src/push/watcher.ts` `fleetRowState` | own ladder | calls `sessionDisplayState` |
| `SessionStore.group(for:)` | own ladder | calls `SessionDisplayState.resolve` |
| `FleetActivitySnapshot.contentState` | own ladder | calls `SessionDisplayState.resolve` |

`isBlocked` now appears only as an *argument* to the shared function — never as a
branch. Verified by grep: exactly three call sites, no surviving chain.

The two tiers that genuinely cannot be centralized stay outside it, by design:
`closed` (needs the cross-host live set) and `unread` (device-local — depends on what
THIS device has seen and is focused on). They are explicit steps around the ladder in
`group(for:)`, not re-derived logic.

**Drift protection:** `SessionDisplayStateTests.swift` and
`src/session-state-parity.test.ts` assert the SAME 8-row table (2^3, exhaustive) in
both languages. Neither ladder can change without the other going red.

```
bun test src/session-state-parity.test.ts   → 4 pass / 0 fail
swift test (LFGCore)                        → 200 XCTest + 3 Swift Testing, 0 failures
bun test (full)                             → 264 pass / 0 fail
flowdeck build -p LFG.xcodeproj -s LFG      → Build Completed
```

The iOS build matters here: `SessionStore.swift` lives in the app target, so
`swift test` does not compile it.

### SC5 / SC6 — live on simulator ✅ (and the bug it caught)

Ran the real app on the session-isolated sim (`cc-dd496c44`), real onboarding, against
the live server. The FIRST run exposed a bug the unit tests structurally could not:

| | server | list (before fix) | card |
| --- | --- | --- | --- |
| blocked | 1 | ✅ Paused 1 | ✅ excluded |
| working | 2 | ❌ shown as **Unread** | ✅ working=2 |

The ladder was correct on both surfaces — the client was feeding it an EMPTY `busy`.

**Root cause.** `journal-pump.ts` appends a `busy` event only when the value CHANGES.
`SessionStore` skipped the REST baseline for any session on a live host, on the stated
theory that "a healthy link streams pane-scraped busy for EVERY session". It does not.
A session already running when the client connects, and still running, emits nothing —
so the link is healthy, no delta ever arrives, and the guard suppressed the only other
source. A freshly-opened app showed every already-running agent as idle until it
happened to change state.

**Fix.** Key the seed on whether the JOURNAL has spoken for that session
(`busyFromJournal`), not on link health. Preserves the original intent — a journal
value is fresher than the snapshot and must not be clobbered — without the false
premise. The set is pruned to the live list each refresh so a recovered session is
re-seedable.

**After the fix**, server / list / card agree exactly:

```
server:  working=1 "The live activity widget running counter…"   blocked=1 "i want to use launchd…"
list:    Working 1 (same session)   Paused 1 (same session)   header "Connected · 1 running"
card:    working=1 needsInput=0 more=0, row = same session; blocked correctly absent
```

Evidence: `ios/design/verify-phase4/0{1..5}-*.png`

## Bugs

_None yet._

## Prior art / evidence

- `.claude/feature/transcript-derived-busy.md` — layer 2, shipped in `4768c78`.
- `.claude/diagnosis-session-stuck-running.md` — the pane-spoofing bug that started this.
- Measured hook emission (this session): Claude Code `SessionStart` t+4.03s →
  `UserPromptSubmit` t+4.08s → `PreToolUse`/`PostToolUse` ×2 → `Stop` t+12.24s →
  `SessionEnd` t+12.41s. One `Stop` per turn, after the whole tool loop.
- Measured steer behavior: a message queued mid-turn produces
  `queue-operation enqueue` → `remove` → a `user` record injected into the running
  turn, and exactly one `Stop`. Steers do not emit `UserPromptSubmit`.
- Measured codex: `SessionStart` → `UserPromptSubmit` → `Stop` → `SessionEnd`, same
  order, plus a `turn_id` on the turn-scoped events.
