# Feature: transcript-derived busy

## User Story

As someone watching many concurrent agent sessions from the iOS client, I want a
session's "running" state derived from its transcript rather than scraped off its
terminal, so that an agent can't pin itself running by writing about the UI it
runs in, and so sessions on the *other* host report state at all.

## Background

`busy` is currently `delegated || (paneBusy ?? transcriptRecent)`:

- `paneBusy` — `isBusy(pane)` regex over a `tmux capture-pane` dump.
- `transcriptRecent` — "was the transcript written to in the last 12 s".

The pane is the primary signal and it is untrustworthy: agent output and TUI
chrome are the same string, so a session that printed `esc to interrupt` read busy
forever (`.claude/diagnosis-session-stuck-running.md`). The transcript already
carries a real turn boundary that lfg ignores: `{"type":"system",
"subtype":"turn_duration"}`, present since at least Claude Code 2.1.170.

## Approach

Scan the transcript **newest-first** and let the first *decisive* record win:

| First decisive record (scanning back) | Verdict |
| --- | --- |
| `system` / `turn_duration` | idle |
| `user` whose text is `[Request interrupted…]` | idle |
| any `assistant` record, or a `user` message/tool_result | running |
| anything else (meta, `away_summary`, `stop_hook_summary`, codex lines) | keep scanning |

Ordering decides, not timestamps — transcripts are synced between two hosts, so
comparing `lastMessageTs > lastTurnEndTs` would import clock skew for no benefit.

The interrupt row is load-bearing: **an interrupted turn never writes
`turn_duration`**. Measured on the real transcript corpus — session `82dedc0e`
has 1 prompt, 0 turn-end records, and ends on `[Request interrupted by user]`.
lfg interrupts on every steering `send`, so without that row the new signal would
latch busy more often than the bug it replaces.

Unknown/codex transcripts yield `null` → callers keep their existing pane
fallback, so this is additive, never a downgrade.

## Success Criteria

- [x] SC1: A finished turn reads idle from the transcript alone — **Verify by:** unit test `turn-state.test.ts` on a finished-turn fixture.
- [x] SC2: An interrupted turn with no `turn_duration` reads idle — **Verify by:** unit test on the `82dedc0e` record shape, plus reading the real file.
- [x] SC3: A turn in flight reads running — **Verify by:** unit test; plus live probe against a genuinely busy session.
- [x] SC4: A codex/unrecognized transcript returns `null` so the pane fallback is preserved — **Verify by:** unit test.
- [x] SC5: Agent prose containing `esc to interrupt` / a quoted meter cannot move the signal — **Verify by:** unit test embedding both strings in message content.
- [x] SC6: Derived busy agrees with pane ground truth on every live session — **Verify by:** live probe over all driveable sessions, printing both.
- [x] SC7: Re-querying an unchanged transcript does no rescan — **Verify by:** unit test counting scans through an injected reader.
- [x] SC8: After deploy, `GET /api/sessions` reports correct `busy` for both a running and an idle session — **Verify by:** live curl + pane capture after restarting `serve`.
- [x] SC9 *(added during Step 6)*: A pane-less session whose transcript ends mid-turn must NOT read running — **Verify by:** live check of `lfg-5c7ed4`.

## Platform & Stack

- **Platform:** Backend (Bun server, single process)
- **Language:** TypeScript
- **Key modules:** `src/turn-state.ts` (new), `src/transcript.ts` (`scanBack`), `src/journal-pump.ts`, `src/sessions.ts`

## Steps to Verify

1. `bun test src/turn-state.test.ts` — unit tier.
2. `bun test` — full regression (baseline 206 pass).
3. `npx tsc --noEmit`.
4. Live probe: for every driveable session, print transcript verdict beside `isBusy(pane)`.
5. Restart `serve` (kill by port), then `curl /api/sessions` and compare against fresh pane captures.

## Implementation Phases

### Phase 1: the signal

- Scope: `src/turn-state.ts` + tests. Pure, no callers changed.
- Success criteria covered: SC1, SC2, SC3, SC4, SC5, SC7
- Verification gate: unit tests green, `tsc` clean.

### Phase 2: wiring

- Scope: `journal-pump.ts` `pollOne` (both the pane and pane-less branches), `sessions.ts` Claude busy ladder.
- Success criteria covered: SC6, SC8
- Verification gate: full suite green, live probe agreement, post-restart API check.

## Decision Log

- **Ordering, not timestamps.** Transcripts sync between hosts; timestamp comparison would import clock skew. Scanning back for the first decisive record needs no clock.
- **`null` means "can't tell", not "idle".** Keeps every caller's existing fallback intact so a parse gap can never silently mark a running session idle.
- **Cache keyed on file size, not a TTL.** A transcript is append-only; unchanged size ⇒ unchanged verdict. Turns a per-second rescan into a per-second `stat`.
- **Left the codex branch of `sessions.ts` alone.** `classifyTurnLine` returns `null` for codex lines, so wiring it there is a no-op today and `sessions.ts` is being edited by a concurrent session — smaller diff, fewer conflicts.
- **8 KB initial scan window** instead of the 64 KB default: the decisive record is nearly always the last line, and `scanBack` grows on a miss.

## Verification Evidence

| SC | Command / action | Observed |
| --- | --- | --- |
| SC1–SC5, SC7 | `bun test src/turn-state.test.ts` | **16 pass, 0 fail** |
| all | `bun test` | **224 pass, 0 fail** (baseline before this work: 206) |
| all | `npx tsc --noEmit` | clean, no output |
| SC2 (real file) | `transcriptTurnState()` on the real `82dedc0e…jsonl` — 1 prompt, 0 `turn_duration`, ends on the interrupt marker | `idle` |
| SC6 | Live probe, transcript verdict vs `isBusy(pane)` across every driveable session | **10/10 agreement**, 0 abstentions |
| SC8 | Restarted `serve` (pid 28573, 19:27:35 — postdates every edit), then compared `GET /api/sessions` `busy` against the derived rule | **12/12 match** |
| SC3/SC8 | `lfg-b7fee2` mid-turn during the probe | `api.busy=true`, `transcript=running`, `pane=true` |
| SC9 | `lfg-5c7ed4` — pane-less ghost, transcript ends mid-turn | `transcript=running`, `pane=null`, **`api.busy=false`** — guard held |

**Independent-layer proof.** Replaying the exact pane captured while the bug was
live (its prose still contains `esc to interrupt`) against the real transcript:

```
layer 1 (pane regex)  old = true  -> new = false
layer 2 (transcript)  = idle

combined with ONLY layer 1 fixed : idle (fixed)
combined with ONLY layer 2 fixed : idle (fixed)
```

Either layer alone closes the bug; together they are defense in depth.

**Auditor:** not spawned. Subagent delegation is disabled for this session, so
Step 6b's independent grader was unavailable. Substituted the live post-deploy
probe against the running server (SC8, SC9) and the independent-layer replay
above — both exercise the real seam rather than a mock. Flagging the gap rather
than claiming the audit happened.

## Bugs

### Found, not caused by this change: `listSessions` enumerates sessions on recycled PIDs

`lfg-5c7ed4` is a dead aisdk session whose recorded pid `98089` now belongs to an
unrelated simulator process (`WeatherPoster.appex`). `listSessions` still lists
it, so lfg is holding a row for a process that has been gone since July.

This did not come from this change and this change does not fix it — the
pane-backed guard on the transcript signal is what keeps it from getting *worse*
(without it the row would have flipped to a permanent "running").

**Decision (2026-08-05): won't fix.** Eugene deprioritised the aisdk path. The
guard already contains the blast radius, so the ghost is a stale row, not a
wrong state. If aisdk sessions matter again, the fix is small: stamp `procStart`
into the registry entry at spawn and gate `isPidAlive` on `procStartMatches`
(`procinfo.ts`), which is what the Claude path already does at `sessions.ts:233`.
Keep the `procStart &&` guard so pre-existing entries don't all vanish at once.
