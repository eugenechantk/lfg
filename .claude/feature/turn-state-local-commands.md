# Feature: turn-state ignores local slash commands

## User Story

As Eugene watching the session list, I want a session that only ran a local slash
command (`/login`, `/model`, `/chrome`) to read Idle, so that the list tells me
which sessions actually need attention.

## Observed bug (2026-09-22)

`cy-122914-44677` (sessionId `3402b3b2…`, cwd `~/dev/inbox`) sat Working for 8+
minutes after nothing but `/login`. Pane: empty composer. Pidfile
`~/.claude/sessions/46125.json`: `status: idle`. Transcript tail:

```
user  isMeta:true  <local-command-caveat>…
user               <command-name>/login</command-name>…
user               <local-command-stdout>Login successful</local-command-stdout>
```

`classifyTurnLine` (`src/turn-state.ts`) treats every non-meta user row with
content as "running". A local command never invokes the model, so no `assistant`
row and no `turn_duration` ever follows, and the transcript layer answers
`running` until `STALL_MS` (15 min) demotes it. The hook layer had no opinion
(local commands fire no `UserPromptSubmit`; the lease carries no `state`), and the
pane only votes when both layers abstain. Verified with
`sessionTurnState(...)` → `{ state: "running", source: "transcript" }`.

Corpus (500 newest transcripts, 14 days): the only typed slash commands recorded
as `<command-name>` rows were local ones (`/login`, `/model`, `/chrome`); each is
followed by a `<local-command-stdout>` row and never by an assistant row.

## User Flow

1. Open a fresh `cy` session, run `/login`.
2. The list shows the session Idle within one pump tick.
3. Send a real prompt → Working; turn ends → Idle (unchanged behaviour).

## Success Criteria

- [x] SC1: `classifyTurnLine` returns `null` (not decisive) for user rows whose text starts with `<command-name>`, `<local-command-stdout>` or `<local-command-stderr>` — **Verify by:** unit tests in `src/turn-state.test.ts`.
- [x] SC2: A transcript whose only turn-shaped rows are a local command resolves `null` (pane fallback), and a local command after a finished turn resolves `idle` — **Verify by:** `transcriptTurnState` tests on fixtures copied from the real transcript.
- [x] SC3: A local command run mid-turn does not close the turn (scan continues to the tool_result → `running`) — **Verify by:** unit test.
- [x] SC4: The real transcript `3402b3b2….jsonl` resolves idle through `sessionTurnState` on the fixed code — **Verify by:** `bun -e` probe against the live file.
- [x] SC5: After deploy, `GET /api/sessions` reports `busy: false` for `cy-122914-44677` with no message sent to it — **Verify by:** curl against the restarted server.
- [x] SC6: Existing turn-state and session-state suites stay green — **Verify by:** `bun test src/turn-state.test.ts src/session-state.test.ts src/session-state-parity.test.ts`.

## Platform & Stack

- **Platform:** Backend (Bun server)
- **Language:** TypeScript
- **Key frameworks:** bun:test

## Steps to Verify

1. `bun test src/turn-state.test.ts src/session-state.test.ts`
2. `bun -e` probe of `sessionTurnState` on the real transcript.
3. Restart `lfg serve` by port (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t`), confirm the new process answers, curl the session row.

## Implementation Phases

### Phase 1: classifier + tests
- Scope: `classifyTurnLine` user-row branch; tests.
- Success criteria covered: SC1–SC4, SC6.
- Verification gate: suites green + live-file probe.

### Phase 2: deploy
- Scope: restart the server on the Air; no code.
- Success criteria covered: SC5.
- Verification gate: curl shows `busy: false`.

## Decision Log

- **Return `null`, not `idle`, for local-command rows.** A local command can run while a turn is in flight (`/model` mid-turn); `null` keeps scanning back to the real boundary, `idle` would close a live turn. `null` also matches the file's invariant: "null means keep looking, never idle".
- **Match on the row's leading tag, not on `isMeta`.** The caveat row is already `isMeta: true`; the command and stdout rows are not, and that is Claude Code's choice, not ours.
- **Known consequence:** a model-invoking skill typed as a slash command (if Claude Code records it as a `<command-name>` row) reads idle for the sub-second gap before its first assistant row. None appeared in the corpus; the hook layer's `UserPromptSubmit` covers it on hosts with hooks.
- **No auditor.** No UI surface changes; the observable is one boolean on a REST row, verified by curl.

## Verification Evidence

| SC | Command / action | Observed | Artifact |
|----|------------------|----------|----------|
| SC1–SC3 | `bun test src/turn-state.test.ts` | 29 pass, 0 fail (3 new tests were red before the fix, green after) | this doc |
| SC6 | `bun test src/turn-state.test.ts src/session-state.test.ts src/session-state-parity.test.ts`; `bun test src/sessions src/journal-pump src/push` | 62 pass / 0 fail; 272 pass / 0 fail across 28 files; `tsc --noEmit` clean | — |
| SC4 | `bun -e` `sessionTurnState({sessionId:"3402b3b2…", transcriptPath: …})` on the live file | before: `{state:"running",source:"transcript"}`; after: `null` (pane fallback → empty composer → idle) | — |
| SC5 | Air: `bun install --frozen-lockfile`; `kill $(lsof -nP -iTCP:8766 -sTCP:LISTEN -t)` (pid 71553, started Sep 20 22:38); wrapper respawned pid 64710 at 12:41:07; `curl /api/sessions` | `{"tmuxName":"cy-122914-44677","busy":false,"prompt":null,"status":"ok"}`; queue for the session empty (nothing was sent to it) | — |

| Deploy | Air: commit `fc951d4`, pushed to origin/main. Pro (`ssh pro`): `git fetch` + `git reset --mixed origin/main` (HEAD 5b3ffae → fc951d4, working tree untouched; `git status` afterwards shows only the pre-existing pbxproj residue), `bun install --frozen-lockfile` (no changes), killed listener pid 99091 (started Sep 20 23:42), wrapper respawned pid 90347 at 12:58:57 under `serve-forever.sh` | new process answers `/api/sessions`; 3 rows = 3 tmux sessions, 0 null `tmuxTarget`; source on disk has the fix (mtime 12:40, older than the process) | — |

Deploy state: **live on both hosts** as of 2026-09-22 12:59 (Air pid 64710, Pro pid 90347), commit `fc951d4` on `main`.

## Bugs

_None yet._
