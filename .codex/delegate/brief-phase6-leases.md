# Delegation Brief: phase6 — session leases (single-execution enforcement)

**Goal:** a session can execute on only one host at a time. A lease file lives BESIDE the
session's transcript (so Syncthing carries it between hosts exactly like the transcript);
resume/fork/auto-resume against a session freshly leased by ANOTHER host returns
`409 {error, liveOn: <hostId>}` instead of silently forking the conversation; stale leases
are taken over; `listResumable` hides freshly-foreign-leased sessions. Design pinned in
`.claude/brainstorm/multihost-first-rearchitecture.md` §6.4 — read it.

**Repo:** worktree of `lfg`. Work ONLY in `src/` (+ tests). No `ios/` changes (the client
treats 409 as a normal send/resume error today, which is acceptable this phase).

## Context (read first)

- `src/commands/serve.ts` — `resumeClosedSession` (explicit resume + auto-resume-on-send
  both call it), the fork handler near it, `/api/sessions/resumable`, and where sessions
  close (`/close`). `cmdServe` for wiring style.
- `src/managed.ts` — `addManaged`/`removeManaged` lifecycle.
- `src/sessions.ts` — `listSessions` (live sessions incl. tmuxName + sessionId),
  `resolveTranscript(sessionId)` (transcript path — the lease sits beside it).
- `src/hostinfo.ts` — persisted `hostId` reader (use it; never mint your own).
- Repo hazard (root CLAUDE.md): NO bare `setInterval` fan-out over a collection — the
  heartbeat loop must be a serialized self-scheduling loop (see `src/journal-pump.ts`
  for the house pattern).

## Spec (per §6.4, pinned — flag disagreement in your report, don't re-derive)

1. **`src/leases.ts`** (new, unit-tested pure core + thin fs shell):
   - Lease path: `<transcript dir>/<sessionId>.lease.json` — derive from
     `resolveTranscript`'s path (same directory, sessionId stem).
   - Shape: `{hostId, pid, acquiredAt, heartbeatAt}` (ms epochs).
   - `readLease(sessionId)`, `acquireLease(sessionId, pid)` (write ours),
     `renewLease(sessionId)` (bump heartbeatAt if ours), `releaseLease(sessionId)`
     (delete if ours).
   - Freshness rule: `fresh = now - heartbeatAt < 90_000`. Foreign = `hostId !== ours`.
     `foreignFresh(sessionId)` helper returning the foreign hostId or null.
   - All fs ops tolerate missing/corrupt files (corrupt = no lease). Writes atomic
     (tmp + rename) — Syncthing watches these files.
2. **Acquire/renew/release wiring:**
   - Acquire on every managed spawn that EXECUTES a session: resume (after the new
     sessionId resolves — lease the NEW id), and new sessions once their sessionId is
     known (the pidfile resolution paths). Best-effort: a failed lease write must never
     fail the spawn.
   - Heartbeat: one serialized self-scheduling loop (30s cadence) over CURRENT live
     sessions (`listSessions` result or managed set) renewing OUR leases. Start it in
     `cmdServe` alongside the other loops.
   - Release on `/close` and when a managed pane is reaped/removed (find the reap path;
     if none is discrete, releasing on close + letting staleness handle crashes is
     acceptable — note it in the report).
3. **409 enforcement** in `resumeClosedSession` AND the fork handler, BEFORE spawning:
   `foreignFresh(sessionId)` → return `{ok:false, status:409, error:"session is live on
   another host", liveOn:<hostId>}` and have the HTTP layer include `liveOn` in the JSON
   error body. The existing same-host already-live dedupe stays first (it's cheaper and
   correct).
4. **`listResumable` exclusion:** sessions with a fresh foreign lease drop out of the
   resumable listing (they're LIVE elsewhere, not resumable). Keep the response shape.
5. **Takeover:** stale lease (≥90s) → acquire overwrites. No extra ceremony.

## Verification (run all you can; paste output)

1. Unit tests: lease round-trip, freshness/foreign logic, corrupt-file tolerance,
   takeover, atomic write (tmp cleanup).
2. **Two-host simulation test** (this is the gate, sandbox-friendly): two lease modules
   with different injected hostIds + data dirs sharing ONE fake projects dir — host A
   acquires; host B's `foreignFresh` names A; after clock-forwarding heartbeatAt beyond
   90s, B takes over. (Inject `now` or the clock for determinism.)
3. `bun test` — all suites green.
4. If you can bind ports, boot a scratch serve and curl a resume of a leased session to
   show the 409 body; if not, say so — the delegator runs the live double-resume gate.

## Definition of done
- [ ] Lease lifecycle (acquire/renew via serialized loop/release/takeover) wired.
- [ ] Double-resume across hosts → clean `409 {liveOn}` (fork too); same-host dedupe
      unchanged.
- [ ] Resumable listing hides fresh-foreign-leased sessions.
- [ ] All suites green; no client changes; no new intervals violating the fan-out hazard.

**Report back:** files changed, test output, the reap/release decision, any deviation
from §6.4.
