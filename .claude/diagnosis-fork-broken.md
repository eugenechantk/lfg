# Fork is broken — diagnosis

**Date:** 2026-07-10
**Reported:** fork from iOS client is slow, the fork can't receive messages, and the fork
appears "still connected" to the host session.

---

## TL;DR

Three independent defects, all confirmed against the live host. Two are real bugs in
`lfg`; one is a hazardous interaction between `--fork-session` and a *busy* source session.

| # | Defect | Status | Symptom it explains |
|---|---|---|---|
| A | Forking a **busy** session makes the fork resume the source's in-flight background work | Confirmed | "activities from the host session are streamed to the fork" |
| B | A `codex` **descendant** of a claude pane is listed as its own session, colliding on the pane target → guard nulls `tmuxTarget` on **both** → `/send` returns 409 | Confirmed | "can't send messages into the forked session" |
| C | `POST /api/sessions/fork` blocks 0.5–6 s polling for the pidfile, and on timeout returns `sessionId: null`, which the client swallows silently | Confirmed (code) | "takes a long time"; no navigation, no error |

---

## The session IDs in the report are inverted

This matters — acting on the reported labels would kill the wrong session.

Ground truth from process argv (`ps -eo pid,lstart,command`):

```
lfg-371f32  pid 67397  started Jul 10 03:28:42
            claude --resume f688108c… --fork-session      → live sessionId eb7d6e12
lfg-9c394e  pid 66934  started Jul 10 11:13:05
            claude --resume eb7d6e12… --fork-session      → live sessionId f95e468a
```

So:

- **`eb7d6e12` / `lfg-371f32` is the SOURCE** (the host session).
- **`f95e468a` / `lfg-9c394e` is the FORK**, created at 11:13:05.

The report has these swapped. The reason is defect A + the fact that a fork copies the
source's history verbatim, so `firstPromptTitle` gives both rows the **identical title**
("ok start phase 1"). Two rows, same title, same project, and the new one immediately
starts doing the old one's work — they are indistinguishable in the list.

---

## Defect A — forking a busy session duplicates its in-flight work

`--fork-session` copies the transcript. If the source has **unfinished background shell
tasks**, that state is copied too. On boot the fork notices the orphaned tasks, enqueues a
notification, and starts an assistant turn to deal with them — i.e. it **continues the
source's work without the user typing anything**.

Evidence — the fork's own first entries, 1 second after boot:

```json
{"type":"queue-operation","operation":"enqueue","timestamp":"2026-07-10T03:13:06.205Z",
 "sessionId":"f95e468a-…",
 "content":"<task-notification><task-id>btqdyi9sn</task-id>…<status>stopped</status>
 <summary>No completion record was found for this background shell command from the
 previous session…"}
```

And 13 minutes later both panes are running the same build, in the same worktree:

```
lfg-371f32 (source)  ✽ Waddling… (28m 20s)   curl … /api/sessions/…/send  (coordinating)
lfg-9c394e (fork)    · Churning… (13m 35s)   cd …/worktrees/multihost-rearchitecture/ios
                                              flowdeck build --workspace LFG.xcodeproj …
```

The fork was never given a prompt (`managedSessionArgv` appends no prompt when forking).
It picked the work up on its own, from the copied transcript.

**Consequence:** two agents concurrently building and editing the same worktree. This is a
correctness hazard, not just a UI annoyance.

**Fix options**

1. *(recommended)* Refuse to fork a `busy` source, or require an explicit confirm in the
   client ("this session is mid-turn; the fork will resume its work"). Cheapest and safest.
2. Strip `queue-operation` and orphaned background-task state from the forked transcript
   before launching. Fragile — depends on Claude Code's on-disk format.
3. Fork from the last *completed* turn rather than the tail. Most correct, most work.

---

## Defect B — a `codex` child of a claude pane makes that session unsendable

`listSessions` enumerates every process whose argv[0] basename is `codex` and gives each
one a `Session` row, resolving `tmuxTarget` via `tmuxTargetForPid`, which **walks up the
ppid chain until it finds a pane pid**. A `codex` process spawned *inside* a claude pane
(exactly what the `codex-delegate` skill does) therefore resolves to that claude pane.

Live ancestry on the host right now:

```
40801  codex --version          ← hung since 11:01:34, 26 min
  └─ 40775  codex
      └─ 40761  node
          └─ 67397  claude      ← this IS the pane pid of lfg-371f32
              └─ 69071  tmux
```

Two rows now claim `lfg-371f32:0.0`, so the pane-collision guard fires
(`src/sessions.ts:1311-1329`) and nulls `tmuxTarget` on **both**:

```
lfg-371f32  pid=67397  sid=eb7d6e12…  tmuxTarget=None   agent=claude
lfg-371f32  pid=40801  sid=None       tmuxTarget=None   agent=codex
```

Note the fingerprint: `tmuxName` is still set, `tmuxTarget` is null — the guard nulls the
target at line 1328 after `tmuxName` was already derived from it at line 1103/1191. Every
healthy `lfg-*` row has both fields.

Then `POST /api/sessions/:id/send` (`src/commands/serve.ts:1694`):

```ts
if (!sess.tmuxTarget)
  return err(409, "session is not in a tmux pane — cannot send");
```

**The source session `eb7d6e12` cannot be sent to, right now, on this host.**

The claude loop already guards against this class of mistake with its `authoritative`
flag; the codex loop (`src/sessions.ts:1149-1206`) has no equivalent check.

**Fix**

Two changes in the codex enumeration loop:

1. Skip codex processes that are **descendants of a claude/codex agent process** — walk
   the ppid chain and bail if an agent pid is hit before the pane pid. A codex *session*
   is the pane's own process; a codex *child* is a tool invocation.
2. Skip transient codex CLI invocations the same way `app-server` is already skipped —
   `--version`, `--help`, `exec`, etc. have no rollout and can never be a session.

Either one alone fixes today's breakage; both together are correct.

---

## Defect C — fork blocks, then fails silently

`forkSession` (`src/commands/serve.ts:180-187`):

```ts
for (let i = 0; i < 12 && !newId; i++) {
  await new Promise((res) => setTimeout(res, 500));   // sleeps BEFORE the first check
  const pid = panePidForSession(tmuxName);
  if (pid) newId = sessionIdForPid(pid);
}
return { ok: true, tmuxName, cwd, newId };            // newId may be null — still ok:true
```

- **Floor 500 ms**, ceiling **6 s**, because the sleep precedes the first probe. Measured
  end-to-end on a small transcript: **1.04 s**.
- On timeout it returns `ok: true, sessionId: null`.

Client side (`SessionDetailView.swift:376-382`):

```swift
let newId = await store.fork(ForkRequest(sessionId: sid))
if let newId { store.requestSelection(newId) }        // nil → no navigation, no error
```

`NewSessionResponse.sessionId` is `String?`, so a null decodes to nil, `store.fork` returns
nil, and the view **does nothing** — no navigation, no `lastError`. The user taps Fork,
waits seconds, and stays exactly where they were.

**Fix**

- Probe first, then sleep (saves the guaranteed 500 ms).
- Treat `newId == null` as a `502` rather than `ok: true`, or return `tmuxName` and let the
  client select by tmux name.
- Client: surface `lastError` when `fork` yields nil instead of silently no-op'ing.

---

## What was ruled out

- **"The pidfile briefly holds the pre-fork session id."** Disconfirmed by experiment:
  forked a small session and polled `~/.claude/sessions/<pid>.json` every 200 ms. The file
  appears at ~1.0 s and already carries the **new** id (`781d185d…`, ≠ source
  `4f640581…`). It never holds the source id.
- **`POST /api/sessions/fork` returning the wrong id.** Tested live against a small
  session: returned `sessionId: 64675218…`, `forkedFrom: 4f640581…`. Correct.
- **`/api/sessions` being slow.** 0.00–0.01 s. Not the source of the perceived latency.
- **Stale `serve` process running old code.** The process on :8766 (pid 17020, started
  03:46:51) is newer than every relevant source file. A second `serve` (pid 64064) runs
  from the `multihost-rearchitecture` worktree on port **8798** — not in the path.

Test artifacts created and removed: tmux `forktest-*`, `lfg-daf29d`; transcripts
`781d185d…`, `64675218…`.

---

## Immediate hazard

`f95e468a` (`lfg-9c394e`) is right now running a build in
`.claude/worktrees/multihost-rearchitecture` that belongs to `eb7d6e12`'s conversation.
Both agents are live in the same worktree. One of them should be stopped before they
clobber each other.
