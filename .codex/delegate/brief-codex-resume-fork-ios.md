# Delegation Brief: codex resume + fork (iOS phase)

## Goal

Expose the codex resume/fork support that landed server-side in `47556d0` to the iOS
client. Server work is DONE and verified — do not change anything under `src/`.

Background: `.claude/feature/codex-resume-and-fork.md` in this worktree. Read it for the
semantics; this brief is the acceptance criteria.

## Working directory

`/Users/eugenechan/dev/personal/lfg/.worktrees/codex-resume-fork`, branch
`codex-resume-fork`. Work only here. The main checkout at `~/dev/personal/lfg` has a live
server attached — do not touch it.

## Server contract you are building against (already implemented)

- `POST /api/sessions/fork {sessionId}` → `{ok, tmuxName, cwd, sessionId: <NEW id>,
  forkedFrom, agent: "codex"}`. Source session is unaffected.
- `POST /api/sessions/resume {sessionId, prompt?}` → `{ok, tmuxName, cwd,
  sessionId: <SAME id>, resumedFrom, agent: "codex"}`. **Codex resume is id-stable** —
  unlike claude, the returned id equals the requested one.
- `GET /api/sessions/resumable` rows now carry `agent` (`"claude"`, `"codex"`, …).
  `ResumableSession.agent` already exists in `LFGCore/Models.swift:306`.

## Scope

1. **Enable Fork for codex.** `canFork` (`ios/LFG/SessionDetailView.swift:455`) currently
   allows only `claude`, `aisdk`, and nil. Add the codex CLI agent (`"codex"`).
   Leave `codex-aisdk` and `opencode` out — the server lane implemented is the codex CLI
   one only. **Correct the comment above it**: it currently claims the codex family "isn't
   resume-compatible", which is now false — codex has its own native fork/resume; what is
   true is that it isn't *claude*-resume-compatible.

2. **Closed/resumable browser shows and routes codex.** Rows must render for codex
   sessions (with the same agent badge treatment used elsewhere — see `Theme.agentGlyph`
   / `AgentBadge`) and resuming one must route through the normal resume path. Verify
   nothing filters the closed list to claude-only on the way to the UI.

3. **Handle id-stable resume.** `applyResume` (`ios/LFG/SessionStore.swift:1978`) already
   guards `new != old`, so an unchanged id is a no-op there and the `eff` computations at
   `:785`, `:1950`, `:2134` resolve to the same id — that part looks safe, but **verify it
   rather than assume**, and say what you checked.

   The real gap: when the id does NOT change, none of the carry-forward in `applyResume`
   runs — no `closed = false`, no `deepLinkSession`, no `requestSelection`. So a revived
   codex session can keep rendering as **Closed** for the 1–6s until the pane appears in
   the live list. Make the closed→live flip happen for the id-stable case too, without
   breaking the claude path that relies on the id actually changing.

## Constraints

- Only files under `ios/`. Nothing in `src/`, `web/`, or `desktop/`.
- Do not restart the lfg server, kill tmux sessions, or `git push`.
- A simulator is in use by Claude for verification — do not run or launch the app, and do
  not start a `flowdeck ui simulator` session. Build only.
- Match the surrounding comment density; the resume/fork paths are subtle and this codebase
  documents *why* above such code.

## Verification

1. `cd ios/LFGCore && swift test` — green (145 currently pass).
2. `cd ios && flowdeck build` — succeeds. If `flowdeck` can't acquire its state lock in
   your sandbox, say so explicitly rather than reporting an unverified build.
3. Add unit coverage where the logic is reachable from `LFGCoreTests` (e.g. any pure
   helper you introduce for the closed→live flip). If a change is only reachable from the
   app target, say so rather than inventing a test that doesn't exercise it.

Claude will run the end-to-end check: the app on a simulator against a server built from
this branch, forking a live codex session and reviving a closed one from the UI.

## Definition of done

- [ ] Fork button appears and works for codex CLI sessions; stale comment corrected
- [ ] Closed browser lists codex sessions and resumes them
- [ ] Revived codex session flips out of Closed promptly despite the unchanged id
- [ ] Claude resume/fork behavior unchanged
- [ ] `swift test` green; `flowdeck build` succeeds

## Report back

Files changed, verification output, what you checked for the id-stable assumption, and
anything you could not verify without running the app.
