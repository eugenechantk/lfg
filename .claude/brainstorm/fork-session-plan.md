# Fork a session — plan

**Goal:** Branch any Claude-family session into a new session, exactly like
Claude Code's `claude --resume <id> --fork-session`. Original transcript stays
untouched; a new session ID + tmux pane is minted carrying the full history.

**Decisions (confirmed):** whole-history branch from the tip; forkable for both
live and closed sessions.

## Server (`src/`)

1. `tmux.ts › spawnManagedSession` — add `fork?: boolean`. When true (and
   `resume` is set) append `--fork-session` after the `--resume <id>` flag.
   `--fork-session` tells claude to mint a NEW session id from the resumed
   history instead of reusing the original.

2. `commands/serve.ts` — new `forkSession()` helper + `POST /api/sessions/fork`.
   Mirrors `resumeClosedSession` EXCEPT:
   - No "already live? bail" short-circuit — forking a running session is the
     whole point. (Resume dedupes because reviving a live session is a no-op;
     fork always creates a new branch.)
   - Passes `fork: true` to `spawnManagedSession`.
   - Same guard: transcript must resolve under `/.claude/projects/` (claude +
     aisdk). Codex/opencode rollouts → 400 with a clear message.
   - Resolves the new forked id from the pidfile (like resume/new) and returns
     `{ ok, tmuxName, cwd, sessionId: newId, forkedFrom }`.

3. Unit test: assert the fork argv contains `--fork-session` and `--resume <id>`
   (mirrors existing tmux argv tests if any; otherwise a focused spawnManaged
   argv test).

## iOS (`ios/`)

4. `LFGCore/Models.swift` — `ForkRequest` (sessionId, model?, user?) mirroring
   `ResumeRequest`. Response reuses `NewSessionResponse`.
5. `LFGCore/LFGClient.swift` — `fork(_:)` → `POST api/sessions/fork`.
6. `SessionStore.swift` — `fork(_:) async -> String?` mirroring `resume`.
7. `SessionDetailView.swift` — "Fork session" button in the toolbar menu
   (branch icon), gated to claude/aisdk agents. On success, focus the new id.

## Verify — DONE

- ✅ Server unit test `src/tmux-argv.test.ts` (5 pass): fork argv carries
  `--resume <id>` + `--fork-session` in order; resume has resume-only; fresh has
  neither; fork-without-resume is a no-op.
- ✅ Full server suite still green (62 pass).
- ✅ **Real-seam test of the `--fork-session` primitive** (the only genuinely new
  risk — the endpoint wraps the production-tested resume path). Ran
  `claude --resume bf063349… --fork-session` in a throwaway tmux pane exactly as
  `spawnManagedSession` would. Result: full history loaded, empty composer,
  **new id `939945d5…` minted** (pidfile-resolvable — the exact path
  `forkSession` polls), source session `bf063349…` untouched and still live.
  Forked a LIVE session (this one). Threw the pane away after.
- ✅ iOS app builds via FlowDeck (iPhone 17 sim); LFGCore builds.

## Remaining: deploy gap (NOT a code issue)

The running `lfg serve` (pid 780, started 09:21) predates these edits, so
`POST /api/sessions/fork` 404s until the server restarts. Bun has no hot-reload
and a restart drops in-memory session tracking that other live lfg agents rely
on — so I did NOT restart unilaterally. Tapping the Fork button end-to-end in the
sim needs that restart. Recommend restarting at a quiet moment (serve-forever.sh
respawns on exit).

## Notes

- UI gates Fork to claude/aisdk (+unknown) agents; codex family hidden. Server
  guard is path-based (`/.claude/projects/`), matching the existing resume guard,
  so aisdk transcripts are accepted the same way resume already accepts them.
