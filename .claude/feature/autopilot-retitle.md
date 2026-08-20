# Feature: autopilot — periodic maintenance tick, first task = session retitle

## User Story

As Eugene, running many long-lived Claude Code sessions, I want a background
autopilot that periodically re-reads what each session is *actually* working on
and renames its title accordingly, so that when I change subject mid-conversation
(which I do constantly) the session list and search stay indicative of the real
work instead of frozen on whatever I happened to type first.

Secondarily: I want that autopilot to be a **registry of maintenance tasks**, not
a one-off script, so future janitor work (pruning stale state, and beyond) drops
into the same tick without new plumbing.

## User Flow

1. `lfg serve` boots and starts the autopilot alongside the existing auto-agent
   scheduler.
2. Every `LFG_AUTOPILOT_TICK_MS` (default 10 min) the autopilot runs, performing
   every step in order. There is ONE cadence: steps are pieces of a run, not
   separately scheduled jobs.
3. The `retitle-sessions` step:
   a. Enumerates candidate sessions — live on this host, plus sessions whose
      transcript was touched in the last 7 days **and whose lease names this
      host** (so the two machines don't fight over one synced transcript; a
      session with no lease at all is skipped, since "unclaimed here" is equally
      unclaimed on the peer and both boxes would take it).
   b. Drops any session whose title Eugene set by hand, and any whose transcript
      has not grown since the last time autopilot looked at it.
   c. Takes the N least-recently-checked survivors (default 12), live first.
   d. Builds one compact digest per session (current title, project, and every
      genuine human turn in chronological order) and makes **one** batched LLM
      call. Already-scanned user history is cached in the retitle checkpoint so
      later runs read only appended transcript bytes.
   e. For each session the model says has drifted, writes the new title via
      `setSessionTitle(..., { source: "auto" })`.
4. Eugene opens the iOS client / desktop app and the session list shows titles
   that describe the current work. Every rename is auditable in
   `~/.lfg/autopilot.log`.
5. If Eugene renames a session himself, autopilot never touches it again.

## Success Criteria

- [x] SC1: A title override records its provenance (`user` vs `auto`) and old
      string-valued `session-titles.json` files still load — **Verify by:** unit
      tests in `src/autopilot/titles.test.ts` covering legacy-string read,
      record read, and round-trip write; plus reading the real
      `~/.lfg/session-titles.json` through the new reader.
- [x] SC2: The autopilot never overwrites a human-set title — **Verify by:** unit
      test `retitle skips user-set titles` in `src/autopilot/retitle.test.ts`.
- [x] SC3: Candidate selection is scoped to this host and to recently-active
      sessions, and is capped per tick — **Verify by:** unit tests over
      `selectRetitleCandidates` with a fixture of live/stale/foreign-host rows.
- [x] SC4: A session whose transcript has not changed since its last check is not
      re-examined — **Verify by:** unit test `skips sessions with no new
      transcript bytes`.
- [x] SC5: The model's batch response is parsed tolerantly and a `null` title
      means "leave it alone" — **Verify by:** unit tests over `parseRetitleBatch`
      with fenced JSON, bare JSON, prose-wrapped JSON, unknown ids, and nulls.
- [x] SC6: The task registry runs due tasks and skips undue ones, persisting
      `lastRunAt` across restarts — **Verify by:** unit tests over `dueTasks` +
      a state round-trip test.
- [x] SC7: End-to-end on the real corpus, a dry run proposes sensible new titles
      for genuinely drifted sessions and leaves good titles alone —
      **Verify by:** `lfg autopilot retitle --dry` against real sessions,
      output recorded in the evidence section.
- [x] SC8: A live (non-dry) run actually changes the title returned by
      `GET /api/sessions` for a drifted session — **Verify by:** capture the
      title before, run `lfg autopilot retitle`, capture after, diff recorded.
- [x] SC9: The tick is safe on the single Bun event loop — one LLM call per tick,
      no per-session fan-out — **Verify by:** code review against the repo's
      "no bare setInterval fan-out" rule + the batched-call test.
- [x] SC10: The retitle call authenticates via the Claude Code subscription, never
      an API key — **Verify by:** `scrubbedEnv` unit tests proving the three
      Anthropic env vars are stripped, plus a live run whose envelope reports
      `provider: "firstParty"`.

## Architecture

Four layers, so a second task adds a file and a registry entry — nothing else:

```
tick.ts        the loop: runs every 10 min, performs every step in order
  registry.ts    what a step IS (name, description, run) + run history
  retitle.ts     ← the only step today
    claude.ts      SERVICE every task uses to ask Claude:
                   ask() / askJson() — subscription auth, retries,
                   serialization, JSON salvage, task-labelled logs
      claude-cli.ts  TRANSPORT: one `claude --print` subprocess,
                     env scrubbed, agent isolation flags
```

**Adding a step** is: write `run(ctx)` returning `{examined, changed, note}`, call
`askJson({ prompt, system, label, validate })` if it needs a model, and add it to
`STEPS` in `tick.ts`. It inherits the cadence, the state file, the dry-run flag,
the JSONL log, and the CLI (`lfg autopilot run <name>`).

**Steps have no interval of their own, deliberately.** An earlier version gave
each step an `intervalMs` and ran only the "due" ones, which meant two schedules
for one loop and a real cadence of whatever the two quantised to. It also put the
rate limit in the wrong place: a step knows better than a timer whether there is
work. `retitle-sessions` keeps a per-session checkpoint and skips anything whose
transcript hasn't grown, so a run with nothing to do costs one ~300 ms filesystem
scan and makes no model call at all. That self-gating is the rate limit. The
contract every step must therefore honour: cheap when idle, idempotent, honest in
its result.

**The split between `claude.ts` and `claude-cli.ts` is deliberate.** Extraction of
JSON from model prose is generic and every task needs it; validating that a
returned id was actually asked about is task-specific and only the task can do it.
So the service extracts and the task validates — `askJson` takes a `validate`
callback and returns null when it rejects. That boundary is what keeps a
hallucinated key from reaching real state.

## Platform & Stack

- **Platform:** Backend (Bun server, part of `lfg serve`) + CLI
- **Language:** TypeScript
- **Key frameworks:** Bun, existing `src/auto/` scheduler patterns, the
  `claude-ai-sdk` backend (`src/agents/backends/claude-ai-sdk.ts`)

## Steps to Verify

1. `bun test src/autopilot/` — all unit tests green.
2. `bun run src/cli.ts autopilot list` — registry lists tasks with due state.
3. `bun run src/cli.ts autopilot retitle --dry` — proposals only, nothing written.
4. `bun run src/cli.ts autopilot retitle` — applies; check
   `~/.lfg/session-titles.json` and `~/.lfg/autopilot.log`.
5. `curl -s localhost:8766/api/sessions | jq '.sessions[].title'` before/after.

## Implementation Phases

### Phase 1: Title provenance

- Scope: `session-titles.json` becomes `Record<id, TitleRecord>` with a lenient
  reader that accepts the legacy `Record<id, string>`. `setSessionTitle` grows an
  options arg carrying `source` and `basis`. Existing consumers keep receiving a
  flat `Record<id, string>` from `readTitleOverrides()` — no call-site churn.
- Success criteria covered: SC1, SC2 (the guard this depends on)
- Verification gate: `bun test src/autopilot/titles.test.ts` + existing
  `session-search.test.ts` still green.

### Phase 2: Task registry + tick

- Scope: `src/autopilot/registry.ts` (task type, `dueTasks`, state persistence in
  `~/.lfg/autopilot-state.json`), `src/autopilot/tick.ts` (`startAutopilot`),
  wired into `serve.ts` next to `startAutoScheduler`. `lfg autopilot` CLI.
- Success criteria covered: SC6, SC9
- Verification gate: registry unit tests + `lfg autopilot list` output.

### Phase 3: The retitle task

- Scope: `src/autopilot/retitle.ts` — candidate selection, digest building,
  batched prompt, tolerant parse, apply. `recentUserTurns()` exported from
  `sessions.ts`.
- Success criteria covered: SC3, SC4, SC5
- Verification gate: retitle unit tests green.

### Phase 4: Live verification

- Scope: no new code; run against the real corpus.
- Success criteria covered: SC7, SC8
- Verification gate: recorded dry-run output + a real before/after title diff.

## Decision Log

- **In-process in `lfg serve`, not a launchd daemon.** Eugene asked for a
  "gbrain autopilot style thing"; gbrain's autopilot is a launchd job because
  gbrain has no other persistent process. lfg already has one, and it already
  owns `~/.lfg/session-titles.json`. A second daemon would mean two writers of
  that file. Reusing the in-process pattern of `src/auto/scheduler.ts` also
  inherits its catch-up and re-entrancy guards. Alternative considered: launchd
  + `lfg autopilot tick`. Rejected for the double-writer reason; the CLI
  subcommand still exists for manual runs.
- **One cadence, not one per step.** See the Architecture section — steps
  self-gate on real state, which is strictly better than a timer, and two
  schedules for one loop made the effective interval hard to reason about.
- **One batched LLM call per run, not one per session.** The repo bans
  `setInterval` fan-out over a growing collection on the single Bun event loop.
  A batch of ≤12 session digests in one call is a single bounded request.
- **Scoped to sessions whose lease names this host.** `~/.claude/projects` is
  synced between the Pro and the Air, but `~/.lfg` is deliberately per-machine —
  so both hosts would otherwise independently retitle the same synced transcript
  and disagree. The lease record (written next to the transcript, in the synced
  tree, carrying `hostId`) is the existing host-ownership signal; using it means
  each session is retitled by exactly one host. Known residual limitation:
  titles remain per-host, so a session retitled on the Pro keeps its old title if
  the Air is the one serving it to the client. Out of scope here.
- **Never overwrite a human-set title.** Provenance is stored rather than
  inferred. Today only 2 overrides exist so the blast radius is tiny, but the
  guard is what makes silent auto-renaming acceptable at all.
- **Silent renames, not proposals.** Eugene asked for renaming, not for a review
  queue. Every rename is logged with its basis so it stays auditable and
  reversible; a human rename permanently pins the title.
- **Only `retitle-sessions` ships in this change.** Eugene picked "prune stale
  state" as the next task; the registry is built to take it as a drop-in, but
  shipping a delete-things task in the same change as its own framework is how
  you lose data. It comes next, separately.
- **LLM calls go through the installed `claude` CLI's OAuth session, not an API
  key.** Modelled on gbrain's `claude-cli` provider
  (`gbrain/src/core/ai/providers/claude-cli-language-model.ts`), which exists for
  exactly this reason: a job on a timer should bill the flat-rate subscription.
  The first implementation used `pipeToClaudeAiSdk`, which drives the same binary
  and the same OAuth credentials — so this was never an API-key leak (no
  `ANTHROPIC_API_KEY` is set on this box) — but it routes through the
  `ai-sdk-provider-claude-code` package with `settingSources: ["user","project"]`,
  which loads project settings/CLAUDE.md and boots every configured MCP server on
  each call. Measured: 25-56s per batch with `MCP servers not connected` warnings,
  versus ~6-8s through `src/autopilot/claude-cli.ts`. That module additionally
  makes the subscription unconditional by deleting `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL` from the child env — the
  failure it guards against is silent, since the CLI keeps working and simply
  switches to per-token billing. Isolation flags (`--tools ""`,
  `--strict-mcp-config`, `--disable-slash-commands`, clean tmpdir cwd) are
  gbrain's, verified against claude CLI 2.1.220.
  Not changed here: `src/auto/runner.ts` and `src/agents/runner.ts` still use the
  ai-sdk backend. They are also on the subscription, but carry the same
  contamination cost — a separate change.
- **Cheap model for the batch.** The task is one-line summarisation over short
  digests; `LFG_AUTOPILOT_MODEL` defaults to `haiku`.
- **Conversation-level drift, not latest-request drift.** The original task used
  only the newest six user messages and explicitly asked what the session was
  doing "NOW". That made the latest request disproportionately likely to become
  the title. The retitler now supplies the full chronological user-message
  sequence and requires a sustained semantic shift; related follow-ups, bugs,
  implementation steps, and verification remain part of one workstream. A new
  title summarizes that established workstream instead of restating the newest
  request. See `autopilot-conversation-titles.md` for the change's verification.

## Verification Evidence

All commands run on Eugenes-MacBook-Pro against the real corpus (9,171 transcripts).

| Criterion | How verified | Result |
|---|---|---|
| SC1 | `bun test src/autopilot/titles.test.ts` (18 tests) + reading the real `~/.lfg/session-titles.json` through `parseTitleFile` | Pass. Both pre-existing legacy string entries parsed as `source: "user"`. |
| SC2 | `retitle.test.ts` "never touches a human-set title" + live: after 3 autopilot runs the file held `user: 2, auto: 10` with both human titles byte-identical | Pass. |
| SC3 | `retitle.test.ts` selection suite (12 tests) + live funnel probe: 8,705 gathered → 28 live, 3,784 this-host lease, 54 other-host, 4,839 unleased → 12 picked, all live | Pass. |
| SC4 | `retitle.test.ts` no-new-bytes tests + live: 2nd run picked a completely disjoint batch from the 1st | Pass. |
| SC5 | `parseRetitleBatch` suite — bare/fenced/prose JSON, hallucinated ids, dupes, nulls, non-strings, unparseable | Pass. |
| SC6 | `registry.test.ts` (12 tests) + `lfg autopilot list` showing `DUE` state and last-run note | Pass. |
| SC7 | `lfg autopilot run retitle-sessions --dry` | 10 examined, 8 left alone, 2 flagged. Both flagged were genuine drift. |
| SC8 | Live run + `GET /api/sessions` before/after | `"Compare the app performance between this app and reelly…"` → `"App category research and market localization"`; `"is whatsapp via hermes to work with gbrain wired?…"` → `"Treehole GPT reverse proxy and gbrain MCP access"`. |
| SC9 | One `[claude-cli] haiku via subscription OAuth` line per run; no per-session calls | Pass. |
| SC10 | Subscription auth, not API: `claude --print --output-format json` envelope reports `"provider":"firstParty"`, echoed in the log as `provider=firstParty` on both CLI and in-`serve` runs | Pass. |

**Unattended end-to-end.** The decisive check: the in-`serve` tick fired on its own
at `16:15:39Z` with no CLI involved and renamed 7 sessions, including three
fork-siblings that all shared the title
`"based on the artifact we've made about the idea with office-hours, i sh…"`
(now "Director pipeline artifact inspection", "Editing template phase
configuration", "Video director pipeline design") and one reading
`"This session is being continued from a previous conversation that ran o…"`
(now "Campaign funnel dropoff investigation").

Full suite: **560 pass, 0 fail**. `tsc --noEmit` clean.

## Bugs

### FIXED — `bun test` deleted the user's real session titles (pre-existing)

**Symptom:** after a full-suite run, `~/.lfg/session-titles.json` lost every
override; on the next `lfg serve` boot it reappeared holding the stale two-entry
copy from `<repo>/data/`, which is what disguised a deletion as "titles reverted".

**Cause:** `PATHS` is resolved on the FIRST import of `config.ts`, and `PATHS.data`
falls back to `~/.lfg` when `LFG_DATA` is unset. Test files isolate themselves by
setting `LFG_DATA` before their own dynamic import, but only the file that imports
`config.ts` first decides for the process. Under the full suite the winner left the
fallback pointing at the real `~/.lfg`, and `session-search.test.ts`'s
`beforeEach` → `rmSync(sessionTitlesPath)` then deleted live user data.
`config.ts`'s legacy-data migration re-copied `<repo>/data/session-titles.json`
on next boot, restoring the file with 2 stale rows.

**This predates this feature** — the delete has been in `session-search.test.ts`
since it was written; the autopilot only made the loss visible by putting content
in the file worth noticing.

**Fix:** `bunfig.toml` preloads `src/test-preload.ts`, which points `LFG_DATA` at a
throwaway dir before any test file loads. Verified: full suite leaves the real file
byte-identical (same md5 before and after).

### FIXED — both hosts retitled the same live session, to different names

**Symptom:** minutes after deploying to the Air, session `01e32dd7` had been
retitled by the Pro to "GBrain atoms and concepts" and by the Air to "gbrain
atoms indexing".

**Cause:** candidate selection exempted live sessions from the host check,
reasoning that a live session is "on this host by construction". It is not —
`~/.claude` is synced, so one sessionId reads as live on both boxes at once.
`gatherCandidates` compounded it by hardcoding `leaseHost: hostInfo().hostId`
for live rows, so the filter asserted the very fact it needed to test.

**Fix:** every candidate goes through the lease now, live or not, and live rows
CLAIM it via `ensureLease` rather than assuming — that primitive already refuses
when another host holds a fresh lease. Verified in production: the Air now sees 6
live sessions, recognises 2 as the Pro's, and skips them.

**Residual, by design:** a lease is fresh for 90s, so this is one host AT A TIME,
not one host ever. Two hosts that both see a session as live will alternate
ownership, and since `~/.lfg` is per-machine each will still retitle it once and
keep its own title. Duplicate work is bounded; titles diverge per host. Making
them converge means moving title state into the synced tree beside the transcript
— a larger change, not attempted here.

### FIXED — a truncating write could erase every override

Found while investigating the above (and *not* its cause). `updateTitleRecord`
used `Bun.write`, which truncates in place, while `readTitleRecords` degrades any
parse failure to `{}`. Two processes write this file — `lfg serve` and the `lfg
autopilot` CLI — and the in-process promise chain cannot serialize across them, so
a read landing mid-write returns `{}` and the next write persists only its own row.
Now: atomic temp-file + `rename`, and a writer that aborts rather than proceeding
from an unreadable file. Covered by `src/title-write-safety.test.ts` (7 tests).
