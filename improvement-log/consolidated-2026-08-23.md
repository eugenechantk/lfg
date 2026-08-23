# Improvement Log Digest — 2026-08-23

**Logs processed:** 5 (sessions 20260822-031302, -040344, -040357, -050000, -163042; three were empty templates)
**Date range:** 2026-08-22 (one day, the iPhone-client bug blitz)
**Observations found:** 20 (all unaddressed at time of writing; actions below)

## Patterns (recurring)

### 1. Instrument the decision point FIRST on state-machine bugs
- **Frequency:** 3 distinct bugs in one session (worker 040357: `isAtBottom` follow-latch, open-pin arrival check, tool-row windowStart walk) + prior sessions
- **Summary:** Gesture/pixel probes and inference repeatedly failed (3 failed probe designs, 2 shipped-then-retracted fixes); in every case 3-4 NSLog lines at the decision point answered it in one run. The one bug where instrumentation came FIRST (juking) was fixed in a single targeted attempt.
- **Root cause:** Habit of inferring internal state from external evidence; instrumentation treated as last resort instead of first move.
- **Current coverage:** memory [[ground-truth-before-hypothesizing]] exists but is framed around "get the error/read the source", not "log the state transition".
- **Recommended fix:** extend that memory with the instrument-first rule for state-machine/UI-movement bugs. **DONE** (memory updated).

### 2. Destructive file/git operations against a shared, uncommitted working tree
- **Frequency:** 3 incidents in one session (worker 040357): `git checkout --` destroyed another agent's uncommitted test work (recovered from a codex rollout); `Write` silently overwrote `TranscriptMerge.swift`; same Write-overwrite again minutes after logging the first.
- **Root cause:** "Restore to clean state" and "create new file" instincts assume a single-owner tree; this repo's normal state is N sessions' uncommitted WIP. The tool signal was even there ("File updated successfully" = existed) and went unread.
- **Current coverage:** repo CLAUDE.md has the concurrency hazard but says nothing about destructive ops; global CLAUDE.md says "look at the target before overwriting".
- **Recommended fix:** add an explicit hazard line to the repo CLAUDE.md: never `git checkout --`/`restore` a file that `git status` shows modified; check existence before `Write` to any unread path; codex rollouts/Claude transcripts are the undo log of last resort. **DONE** (CLAUDE.md updated).

### 3. Verification that skips a named condition hides the bigger defect
- **Frequency:** 2 in worker session (verified keyboard fix on an IDLE session when the report said "while live messages arrive" — the dropped condition carried the largest defect; stopped at one root cause when a second repro path existed), plus my own pre-written bug-010 evidence.
- **Current coverage:** [[verify-the-discriminating-case]], [[verify-real-seam-not-mocks]] — exist, didn't bite.
- **Recommended fix:** extend [[verify-the-discriminating-case]]: reproduce with EVERY condition the report names, together; a fix verified on one repro path is evidence about that path only. **DONE** (memory updated).

## One-off observations worth persisting

- **FlowDeck `type` emits `;` for `:`** (and coordinate-taps drift between keyboard planes) — silently corrupts URLs/ports; reported success. → new memory. **DONE**.
- Headless sim = no software keyboard → **already** memory `sim-keyboard-needs-simulator-app` (written same session).
- LazyVStack onAppear ≠ visibility → **already** memory.
- `lastError` cleared every refresh — check who CLEARS state before rendering it (lifetime is part of the contract). Captured here; no separate memory (repo-specific, now moot after the errorEvent redesign).
- A "safety net" predicate can swallow the case the real fix never covered; a flag's meaning is defined by every writer. Captured in bug-010/SC10 notes and [[verify-the-discriminating-case]] update.
- Mutating real host config to fake "offline" — existing memory [[lfg-stub-host-offline-repro]] covered this and wasn't applied; noted as a recall failure, no new entry.
- My session (050000): zsh eats unquoted bracket globs; `log` is shadowed → use `/usr/bin/log`; sandboxed `tailscale status` lies; never pre-write verification evidence; transport was diagnosed against deprecated Tailscale docs → memory `lfg-client-transport-is-cloudflare` **already written**, repo CLAUDE.md **already corrected**.

## Recommended actions

| # | Action | Mechanism | Status |
|---|--------|-----------|--------|
| 1 | Destructive-ops hazard (checkout --, Write-to-unread-path, rollout-as-undo-log) | repo `.claude/CLAUDE.md` | DONE |
| 2 | Instrument-first rule | memory `ground-truth-before-hypothesizing` | DONE |
| 3 | Every-named-condition rule | memory `verify-the-discriminating-case` | DONE |
| 4 | FlowDeck `type` punctuation trap | new memory `flowdeck-type-punctuation` | DONE |
| 5 | Historical backlog: ~190 tracked logs from Jul–Aug remain unconsolidated | run `/consolidate-improvement-logs` in a dedicated session | OPEN |

## Logs deleted after processing

All five 2026-08-22 logs (three empty; two fully captured above and in the memories/CLAUDE.md edits listed).

## Post-digest addendum (same session, Phase-1 scroll debugging)

- Coordination gap: my "stand by, don't edit" message caused the worker to
  silently REVERT its in-flight instrumentation between my file-read and my
  build — I then drove a full simulator debug cycle against an app with no
  writer logs and burned ~20 min on a phantom "logs don't emit" mystery.
  Lesson: a stand-down instruction to a concurrent session must say what to do
  with in-flight edits (keep/commit/hand over), and after ANY "file changed on
  disk" note during shared-tree work, re-grep the assumptions before building.

- Outbox drain: per-call-site policy gating missed a replay path TWICE in
  independent re-verification (stub down->up shape passed while the field shape
  — cold launch, host live from t0 — kept re-sending stale rows). Lesson
  pattern: an invariant ("never auto-send past the retry cap") belongs at the
  single choke point that performs the action, not sprinkled on callers; and a
  verifier's rig must replicate the FIELD shape, not the convenient shape —
  re-confirms [[verify-against-real-session-population]] for a non-pane domain.

## Second addendum — logs processed at 2026-08-23 cleanup (5 files, sessions 20260822-184635/-184653, 20260823-074941, ff4c4e3c, 21123b4f)

**Patterns → actions taken:**

1. **Call-site gating failed a THIRD round** (ff4c4e3c: `resendFailedSends` →
   `retryPending` bypassed every outbox gate; Eugene had to name the boundary).
   → new memory `enforce-at-the-boundary` (HIGH; graduated from the addendum
   above after the third recurrence).
2. **All-negative verification passed under a rig that could not fail, twice in
   one session** (rows seeded under the wrong key — `Host.id` is the URL, not
   the JSON `hostId`; a refuse-everything boundary check would also have gone
   green). The hand-tapped Retry control exposed both. → extended
   [[verify-the-discriminating-case]]: every "X must not happen" needs a paired
   "Y must happen" through the same path, control checked FIRST.
3. **A behavioral fix was deleted by a refactor that also rewrote its test to
   pin the regression** (21123b4f: end-debounce added in `17afb13`, deleted by
   `5d93e63` Aug 17; green tests + a "fixed" memory hid it for 6 days; found
   via `git log -S`). → [[live-activity-end-is-not-free]] updated with history
   warning; reinstated tests carry the WHY in comments. Rule worth keeping in
   mind: on a "previously-fixed" bug that's back, `git log -S <fix-constant>`
   before re-diagnosing — the deploy-gap hazard has a regression-by-refactor
   sibling.
4. **Known-good escape hatch recalled only after the failure it prevents**
   (184653: two 45s stalls before `FLOWDECK_UI_SKIP_LOCK_CHECK=1`). → memory
   updated to say export it pre-emptively in the first UI-automation command.

**One-offs captured, no new mechanism:** proxy rigs must handle connection
reuse (URLSession pools TCP; inspecting only the first request per connection
verifies nothing); `flowdeck run` relocates the sim data container so plist
seeding is structurally impossible (drive the real UI or seed sqlite);
`settleSendFailure` had flattened `URLError` to a string one layer down —
preserve typed errors across layers that later need to discriminate them;
editing a host's Address creates a NEW host (`Host.id` IS the URL) — verify
restores against full prior state (count + contents), not the edited field;
TDD red step skipped and a TDZ bug in a first edit pass (21123b4f, minor).

**Already addressed in-session:** iPad verification carve-out written into
`ios/CLAUDE.md` (184653); Live Activity server fixes + audit (21123b4f).

**Logs deleted after processing:** all five (two were empty templates); content
captured here and in the memory edits above.
