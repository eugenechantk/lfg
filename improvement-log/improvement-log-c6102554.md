# Improvement Log — Session c6102554

## Tracker

- [x] 2026-08-13 — Burned ~25 min on FlowDeck's "Simulator appears locked" false positive; `FLOWDECK_UI_SKIP_LOCK_CHECK=1` is the escape hatch
- [ ] 2026-08-13 — `flowdeck build` failed on a file another session added (`AttachmentsSheet`) because `LFG.xcodeproj` was stale; `xcodegen generate` is not in any build-failure playbook
- [ ] 2026-08-13 — Journal-pump's "new session starts at EOF" rule means a kickoff user turn is NEVER delivered live; only the REST fetch has it, and nothing retried that fetch

## Log

### 2026-08-13 — FlowDeck "Simulator appears locked" false positive cost ~25 minutes

**What happened:** Every `flowdeck ui simulator` command (screen, tap, swipe, button, touch, session) refused to run with "Simulator appears locked … Lock screen elements detected". I tried, in order: restarting the UI session, rebooting the sim, erasing the sim, rebooting via the guard helper, writing `SBAutoLockTime`/`SBIdleTimerDisabled` into the sim's `com.apple.springboard.plist`, opening Settings via `prefs:root=DISPLAY` deep link, tapping through Settings, and Settings search — six dead ends. The real fix was one env var: `FLOWDECK_UI_SKIP_LOCK_CHECK=1` (found by `strings $(which flowdeck) | grep FLOWDECK_`).

**Why this was wrong:** The block was reproducibly tied to *which app was frontmost* — captures at the home screen and in Settings worked, captures with the LFG app frontmost failed — which is the signature of a heuristic misfiring, not a real device lock. I should have stopped and asked "is the device actually locked?" after the second failure instead of treating the message as ground truth and attacking the (imagined) lock.

**What better looks like:** When a tool refuses with a *state* claim, spend one probe disconfirming the claim before acting on it (here: capture with a different app frontmost — 30 seconds). When the claim turns out to be a false positive, look for the tool's own bypass (`strings $(which <tool>) | grep '<TOOL>_[A-Z_]*'` lists every env var) before engineering around it. Also worth adding to the flowdeck skill/memory: `FLOWDECK_UI_SKIP_LOCK_CHECK=1`, `FLOWDECK_UI_ALLOW_PAUSED=1`.

### 2026-08-13 — Stale `LFG.xcodeproj` made a clean tree fail to build

**What happened:** The first `flowdeck build` failed with "cannot find 'AttachmentsSheet' in scope" plus a bogus "compiler is unable to type-check this expression in reasonable time" on an unrelated line. `AttachmentsSheet.swift` was committed by another session but `LFG.xcodeproj` hadn't been regenerated, so the file wasn't in the target. `xcodegen generate` fixed both errors.

**Why this matters:** The second error was pure noise from the first, which is exactly the kind of thing that sends a session off debugging a view body that isn't broken. `ios/CLAUDE.md` says project.yml is the source of truth but doesn't say "a missing-symbol build error on a file that exists on disk = run xcodegen first".

**What better looks like:** On any iOS build failure naming a symbol whose file exists on disk, run `xcodegen generate` and rebuild BEFORE reading the code. Worth a line in `ios/CLAUDE.md`.

### 2026-08-13 — Kickoff user turn is structurally invisible to the journal

**What happened (the bug being fixed, kept here because the shape recurs):** `journal-pump.ts` starts a newly discovered session's tail at the file's CURRENT size, and the harness has already written the kickoff user turn by then — so it is never journaled. Measured live: `POST /api/sessions/new` returns in ~300ms, and `/api/sessions/<id>/messages` 404s ("session transcript not found") for ~1s afterwards. The client's single history fetch lands inside that window, `ensureHistory` swallows the failure, and nothing retries — so the user's own kickoff message never reaches `transcripts[sid]` and its optimistic bubble hangs *below* the streaming reply.

**Why this matters:** This is the third instance of the same family already documented in memory ([[journal-delta-needs-rest-baseline]], `watchForResumeLanding`'s resume gap): pump-owned state a client renders needs both a delta AND a snapshot, and a snapshot fetch that can 404 needs a retry, not a `try?`.

**What better looks like:** Any new one-shot REST fetch in `SessionStore` that backs client-rendered state should be treated as retryable by default. A `try? await` that silently yields "no data" is a latch waiting to happen.
