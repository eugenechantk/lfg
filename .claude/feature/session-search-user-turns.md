# Feature: session search matches every user turn, not just title + last message

## Bug report (2026-09-20)

Eugene: "The search for older, potentially closed sessions are not working beyond the
first few dozen of sessions. For example I can't search for my dictate keyboard session."

## Diagnosis

The theory in the report (search only covers the loaded page) is **not** what is
happening. Both clients fan `?q=` out to every host and the server searches a
metadata index over the whole corpus (11,642 entries on the Pro). Depth is fine.

The actual gap is **which fields are indexed**. `entryHaystack` in
`src/session-index.ts` matches `title`, `project`, `cwd`, `lastUserText`, `sessionId`
only. The session Eugene means is `93f676c1` in `~/dev/inbox` (2026-09-19):

- title: "Custom transcription keyboard" (first prompt: "Is there a way to use the
  action button on iPhone 17 pro to transcribe what I said into text…")
- last user text: "And let's use openrouter's models to test it"
- "dictate" / "dictation" appear only in turns 5–20 ("I want to use the action button
  to kickstart the dictation…", "Can we implement swipe typing on dictate?")

`GET /api/sessions/resumable?q=dictate` → `{"sessions":[]}`; `?q=keyboard` finds it.
Any query for a word the user remembers from the *middle* of a conversation fails
the same way, and it fails equally for recent and old sessions.

## User Story

As Eugene searching the session list, I want a query to match any word I typed to
the agent at any point in a conversation, so that I can find a session by what it
was about rather than by how it happened to start or end.

## User Flow

1. Open the session list, type "dictate" in the bottom search field.
2. Every host answers with closed sessions whose **user turns** contain "dictate".
3. The row for "Custom transcription keyboard" appears; its preview line shows the
   user turn that matched ("…kickstart the dictation, without me switch keyboards…")
   so it is obvious why it matched.
4. Tap it → opens the closed session as before.

## Success Criteria

- [x] SC1: A transcript whose only occurrence of the query term is in a middle user
  turn is returned by `searchResumable` — **Verify by:** `src/session-search.test.ts`
  "matches a term that appears only in a middle user turn" (claude shape, codex shape,
  and a `queue-operation` absorbed message).
- [x] SC2: Meta/system-injected user lines and `<`-prefixed wrappers do not make a
  session match — **Verify by:** test "does not index meta or wrapper user lines".
- [x] SC3: A row matched only through its user turns carries the matching excerpt in
  `lastUserText`, so the SHIPPED iOS/desktop clients (which re-filter server rows on
  title/project/cwd/lastUserText/sessionId) keep the row and show why it matched —
  **Verify by:** test "a user-turn match is previewed by the turn that matched" +
  `SessionSearch.matches` in `ios/LFGCore` run against the returned row shape (Swift
  test `SessionSearchTests`).
- [x] SC4: A row that matches on title/last text keeps its real last user text —
  **Verify by:** test "a title match keeps the real last user text".
- [x] SC5: Indexed user text is bounded (per-transcript char cap + head scan byte cap)
  so a 511 MB Codex rollout cannot blow the read path — **Verify by:** unit test on
  the cap + measured RSS/time of a cold index build over the real corpus
  (`bun scripts/…` one-shot, recorded below).
- [x] SC6: The old on-disk index (version 1) is discarded, not misread — **Verify by:**
  `src/session-index.test.ts` "a version-1 index file is discarded".
- [x] SC7: Live: `curl 'http://127.0.0.1:8766/api/sessions/resumable?q=dictate'` on the
  Pro returns `93f676c1…` with a preview containing "dictat" — **Verify by:** curl
  after restarting the Pro server.

## Platform & Stack

- **Platform:** Backend (Bun server) + read-only contract check on the Swift clients
- **Language:** TypeScript (Bun), Swift (test only)
- **Key files:** `src/session-index.ts`, `src/sessions.ts`, tests beside them

## Steps to Verify

1. `bun test src/session-index.test.ts src/session-search.test.ts src/sessions.test.ts`
2. One-shot cold build over the real corpus: time + peak RSS.
3. Restart the Pro server by port (per project CLAUDE.md), then SC7 curl.
4. `swift test --filter SessionSearchTests` in `ios/LFGCore` for SC3's client half.

## Implementation Phases

### Phase 1: Index the user turns

- Scope: `IndexEntry.userText` (bounded concatenation of genuine user turns),
  `SEARCH_INDEX_VERSION` 1 → 2, `entryHaystack` includes it, streaming bounded reader
  in `sessions.ts`, refresh enrichment fills it.
- Success criteria covered: SC1, SC2, SC5, SC6
- Verification gate: unit tests green, cold build measured.

### Phase 2: Preview the matching turn

- Scope: `searchResumable` sets `lastUserText` to an excerpt around the first term that
  is absent from the classic fields; pure `matchExcerpt` helper in `session-index.ts`.
- Success criteria covered: SC3, SC4
- Verification gate: unit tests + Swift `SessionSearch.matches` check.

### Phase 3: Deploy on the Pro, verify live

- Scope: restart `lfg serve` on the Pro by port; SC7.
- Air deploy needs a commit + push (not done unless asked).

## Decision Log

- **Index text, not a word set.** A deduped word set would be smaller, but the client
  needs an excerpt to show *why* a row matched, and an excerpt needs the original
  text. Capped at 4,096 chars per transcript, worst case ~45 MB for 11.6k entries; the
  real corpus is measured below.
- **Reuse `lastUserText` for the excerpt instead of a new field.** The shipped iOS and
  desktop builds re-filter every server row against title/project/cwd/lastUserText/
  sessionId ("`?q=` is a request, not a guarantee"). A new field would be dropped by
  those builds and the fix would wait on a TestFlight release. On a search page the
  field's job is "the preview line for this hit"; documented on the type. A row that
  already matches on the classic fields is untouched.
- **Head scan bounded to 32 MB and 4,096 chars of user text, stop early.** Same
  budget `lastUserText` uses, for the same reason (511 MB Codex rollouts, 4 GB
  supervisor ceiling). 32 MB covers all but ten of ~10.9k Claude transcripts.
- **Version bump forces one cold rebuild** rather than lazily upgrading v1 entries.
  Simpler, and the rebuild cost is measured before deploy.
- **Prefilter lines by substring before JSON.parse.** Only lines containing `user` or
  `queue-operation` can carry a user turn; parsing the assistant/tool lines (the
  bulk of every transcript) would make the rebuild CPU-bound on the single event loop.

## Verification Evidence

All recorded 2026-09-20 on the Pro.

| Criterion | Command / action | Observed |
|---|---|---|
| SC1 | `bun test src/session-search.test.ts` — "matches a term that appears only in a middle user turn", "matches a middle user turn of a codex rollout", "matches a message that was absorbed mid-turn" | pass |
| SC2 | same file — "does not index meta, wrapper or tool-result user lines" | pass (`marmalade` → `[]`, `genuine` → the row) |
| SC3 | same file — "a user-turn match is previewed by the turn that matched"; `cd ios/LFGCore && swift test --filter SessionSearchTests` (`testKeepsARowTheHostMatchedThroughItsUserTurns`) | pass; `Executed 13 tests, with 0 failures` |
| SC4 | same file — "a title or last-message match keeps the real last user text" | pass |
| SC5 | `src/recent-user-turns.test.ts` "allUserTurns bounds" (3 tests) + one-shot over the real corpus (scratchpad `measure-usertext.ts`): 11,628 transcripts (10,871 claude / 757 codex) | user-text read 6.4 s at concurrency 24, 11.2 MB total, 29 capped, peak RSS 264 MB; index file 19.4 MB |
| SC6 | `src/session-index.test.ts` "a version-1 index file (no user text) is discarded" | pass; live `~/.lfg/session-search-index.json` is `version: 2` |
| SC7 | restarted the Pro server by port (old pid 64600 → new 80997, 23:06:47); `curl '…/resumable?q=dictate&limit=5'` | `93f676c1 claude \| Custom transcription keyboard \| Can we implement swipe typing on dictate?`; `q=dictate keyboard` → `93f676c1`; `q=keyboard` preview stays "And let's use openrouter's models to test it" |
| regression | `bun test` / `bunx tsc --noEmit -p .` | 945 pass, 0 fail / clean |

First search after the restart paid the cold v2 rebuild: 18 s (direct seam run). Subsequent searches ~0.8 s (pre-existing enumerate cost). The wrapper log shows one `[pump] poll sweep took 16167ms` at startup overlapping that rebuild; earlier starts show sweeps of 988 s and 1034 s, so this is not a regression.

**Independent audit: not obtained.** Two `verification-auditor` spawns (default model, then opus) both died before their first tool call with `API Error: 403 authentication_failed`; subagents are blocked in this session. The auditor's brief was run by the implementer instead — a **self-audit**, weaker than an independent one — and recorded under `.claude/evidence/session-search-user-turns-20260920/`:

| Check | Result |
|---|---|
| Adversarial real transcript (`03-adversarial-pick.txt`): `774820bd`, word only in a middle user turn | found by the endpoint (`04-live-endpoint-selfaudit.txt`) — and exposed a wart, see Bugs |
| Word that appears only in assistant text (`abortcontroller`) | 0 hits: assistant text is not indexed |
| Control `q=zzqqxxnotaword` | `{"sessions":[]}` |
| After the interrupt-marker fix and a second restart (pid 99091, 23:42:39; `05-after-interrupt-fix.txt`) | `q=dictate` → `93f676c1` unchanged; `q=interrupted` 82 → 6 hits, all six previewed by the marker as their genuine *last* message (pre-existing tail reader, not the index); index `version: 3`, 11,638 entries, 19.4 MB |
| Regression after the fix | `bun test` 947 pass; `tsc` clean |

## Bugs

- **Found and fixed during verification:** Bun 1.3.14 — `Bun.file(p).slice(0, n).stream()` with `n` short of EOF delivers `n` bytes and never closes. Every one of 10 hung reads out of 217 was a transcript larger than the 32 MB cap. `allUserTurns` now leaves the stream by counting bytes and `break`ing (`src/recent-user-turns.test.ts` "a byte budget short of EOF on a multi-chunk file still terminates"). Pre-existing readers slice to EOF and were never affected.
- **Found in the self-audit and fixed:** Claude Code writes `[Request interrupted by user…]` as a `user` turn when Escape is pressed. `userTurnFromLine` counted it, so `q=interrupted` matched 82 sessions previewed by the marker. Now excluded (regex `INTERRUPT_MARKER`), index version bumped to 3 so every entry was rebuilt; tests in `recent-user-turns.test.ts` and `session-search.test.ts`. Side benefit: the retitler (`allUserTurns`) no longer sees the marker either.
- **Observed, not in scope:** the tail reader `lastUserText` still returns the interrupt marker when it is genuinely the last user line (6 sessions today), so those rows preview as "[Request interrupted by user]" in the plain list too. Same one-line exclusion would fix it; left alone because it changes the plain list's previews and warrants its own look.
- **Observed, not in scope:** `firstPromptTitle` / `lastUserText` accept a stray `text` block on a `tool_result` user row as a human turn (a tool result can become a session title). `userTurnFromLine` already excludes those rows; the head/tail readers do not.

## Not done

- **Air deploy.** Needs a commit + push (not done unless asked) followed by the usual restart-by-port on the Air with `bun install --frozen-lockfile` first. Until then, searches that fan out to the Air return only the Air's classic-field matches for that host; the client merges the Pro's hits, so the dictate session is already findable from the phone.
- (Done after all: the stale `LAST_USER_TEXT_SCAN_BYTES` comment now states the measured 2026-09-20 fact and points at the byte-counting rule.)
