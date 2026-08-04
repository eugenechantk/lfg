# Viewing offline hosts' sessions via an online host

**Date:** 2026-07-29
**Question:** iOS client can't view sessions on an offline host. Since `~/.claude` is
shared across hosts, can an online host serve them read-only?

**Answer:** Yes. The data is already on every host and the server already serves
it. The blocker is entirely **client-side routing**: reads are pinned to the
owner host, and the stale live row suppresses the copy that would route to a
reachable peer.

---

## Finding 1 — ROOT CAUSE: reads are pinned to the dead owner

Three individually-correct decisions collide:

**1. A down host's rows are deliberately kept on screen.**
`SessionStore.applyHostFetch` (SessionStore.swift:1360) assigns
`lastSessionsByHost` **only** when `f.reach == .ok`. A failed fetch leaves the
last-good snapshot untouched — its own comment says *"the cached snapshot keeps
its sessions on screen."* So the Air's sessions persist as rows with
`closed == false` and `owner == Air`.

**2. Those stale rows suppress the peer's good copy.**
`rebuildSessions` (1383) folds them into `perHostLive` → `liveIds`. Closed pages
come only from reachable hosts (`closedPages(for: okHosts)`), and
`MultiHost.reconcileResumable` does `if liveIds.contains(r.sessionId) { continue }`.
So the Pro's copy of that exact transcript — which *would* be host-agnostic and
routable — is **discarded as a duplicate of the stale row**.

**3. Routing then sends the read to the machine that's down.**
`client(forSession:)` → `MultiHost.routeHost(owner:isClosed:reachable:agnostic:)`:

```swift
if let owner {
    if reachable(owner) { return owner }
    if !isClosed { return owner }   // ← owner down + live → owner anyway
}
```

`ensureHistory` (1747) uses that client, `client.messages()` throws, and it falls
back to `hydrateTranscriptFromStoreIfEmpty` — you get only what was already
cached locally. The row is visible; the transcript won't load.

**The one-line version:** `routeHost` does not distinguish **reads** from
**writes**. A send genuinely must go to the owner — only that machine has the
tmux pane, and the comment defending this rule (*"the op must fail honestly
rather than land somewhere surprising"*) is right *about sends*. A **read** has
no such constraint: the transcript is synced to every host. Both go through one
routing decision, so the correct rule for writes silently breaks reads.

**Minimal fix:** a read-only route that falls back to `agnosticHost` when the
owner is unreachable, used by `ensureHistory` / `messagePage`. Nothing else in
this doc is required to make offline hosts' sessions viewable.

## Finding 1b — the sync is fine (earlier claim retracted)

An earlier pass here called the Syncthing sync dead. That was wrong, twice over:

- On macOS Syncthing runs as `/Applications/Syncthing.app/...`, which is **not on
  PATH** — `which syncthing` returns "not found" while the daemon runs fine.
  Verified running, log written through Aug 1.
- The `dot-claude` folder logs `Failed to sync … no connected device has the
  required version of this file` for 3 files. That's **benign**: the only copy of
  those versions is on the offline Air. `projects/**.jsonl` syncs normally.

There *was* a real outage 07-25 → ~07-31. It is not the current cause.

## Finding 2 — what already works

`~/.claude/.stignore` is deliberately just `/sessions`:

> `// Transcripts live in ~/.claude/projects/ and DO sync — that's all transfer needs.`

So `projects/**.jsonl` is designed to be present on every host, and the server
never assumes locality when reading one:

- `resolveTranscript(sessionId)` (`src/sessions.ts:1377`) scans the local
  `~/.claude/projects/` tree by id. It does not care which machine wrote it.
- `GET /api/sessions/<id>/messages` (`src/commands/serve.ts:2087`) goes straight
  through `resolveTranscript` — no liveness check, no host check.
- `GET /api/sessions/resumable` (`src/sessions.ts:1429`) already enumerates
  *transcripts on disk* rather than live processes, and already dedupes
  Syncthing conflict copies (`UUID_EXACT`) and cross-project duplicates.

**Verified empirically:** hit this host's own server for a non-live transcript —
`curl :8766/api/sessions/4501fc50-…/messages?limit=2` returned full normalized
messages. The same call works for a transcript that arrived over Syncthing.

There is also already a cross-host liveness protocol:

- `src/leases.ts` writes `<sessionId>.lease.json` **next to the transcript**
  (so it syncs), containing `{hostId, pid, acquiredAt, heartbeatAt}`, 90s
  freshness window.
- `foreignFresh()` / `foreignFreshAt()` already answer "is this session live on
  another machine, and which one." Used to 409 sends (`"session is live on
  another host"`) and to exclude live-elsewhere sessions from the resumable list.

## Finding 3 — most of this already ships (correction)

The iOS client **already** shows an offline host's transcripts, served by an
online peer. `fetchResumablePages` fans `/api/sessions/resumable` out to every
reachable host, and its own comment says why:

> *"Because `~/.claude/projects` is synced these lists overlap heavily — the
> cache rebuild path dedupes + drops live ids."*

`MultiHost.reconcileResumable` dedupes by `sessionId` across hosts, and
`routeHost` is explicit that this is intended:

> *"A closed session is host-agnostic: its transcript is synced, so any live
> machine can revive it. This is what lets a closed session restart while the
> marked-default host is down."*

So today, when host B dies, its sessions reappear on host A's list as **closed**
sessions — readable, and offering a Resume button. Viewing is not the gap.

**The gap is attribution and safety.** Three states are conflated:

| State | Today |
| --- | --- |
| (a) live on B, B reachable | correct — B reports it |
| (b) live on B, B unreachable from the phone but its lease is fresh on A | **invisible everywhere** — A excludes it from resumable, B can't answer |
| (c) live on B, B genuinely down (lease stale >90s) | shows as "closed" — viewable, but mislabeled as *ended* when it was *interrupted*, and offers Resume |

(b) is the case the current code handles worst, and it's the one closest to
Eugene's complaint. (c) is viewable but lies about what happened.

## Finding 4 — lease coverage is partial, and that's a split-brain hazard

`acquireLease` is only called on lfg-*created* sessions (serve.ts:170 resume,
225 fork, 1903 new, whatsapp.ts:464). `renewLease` returns false unless a lease
already exists **and** we own it — it never creates one. So a session started by
hand (`claude` in a terminal, tmux, or spawned by another agent) never gets a
lease. Only 5 lease files exist on this machine today.

For a session with no lease, `foreignFresh()` returns null, so:

1. `listResumable` doesn't exclude it → **a session genuinely live on the Air
   shows on the Pro as "closed", with a Resume button.**
2. `resumeClosedSession` (serve.ts:~137) checks only the *local* `listSessions()`
   plus `foreignFresh` — both come back clean — so it spawns
   `claude --resume <id>` on the Pro **while the Air is still driving that same
   conversation.** Split brain: two agents, one lineage, diverging. Claude
   resumes into a *new* sessionId, so there isn't even a sync-conflict file to
   notice it by.

The 409 guard (`"session is live on another host"`) is well-designed; it just
has nothing to read most of the time.

---

## Step 2 — widen lease coverage

**Where:** `startLeaseHeartbeat`, `src/commands/serve.ts:700`. It already walks
every local live session every 30s and calls `renewLease`. Change renew-only to
acquire-or-renew:

- **no lease** → acquire (this is the case that fixes hand-started sessions)
- **ours** → renew (keeps the original `acquiredAt`; `acquireLease` would reset it)
- **foreign + stale** → acquire; the previous owner is gone
- **foreign + fresh** → leave it alone, and log it. Two hosts believing they run
  the same session is a real anomaly, not something to silently overwrite.

**Only claim authoritative sessions.** `listSessionsUncached` distinguishes a
`sessionId` that came from `~/.claude/sessions/<pid>.json` from one *guessed*
via the `--resume` argv or the newest-unclaimed-in-cwd heuristic
(`authoritative`, sessions.ts:1052). A guessed binding can attach a long-lived
bare `claude` to the wrong transcript — stamping ownership on that is **worse
than no lease**, because it would 409 the real owner's sends. `authoritative`
isn't currently on the exported `Session` type, so this needs a new field;
`tmuxTarget != null` is a usable proxy today (it already encodes
`authoritative && !headless`), and excluding headless `claude -p` runs from
lease ownership is fine — they're short-lived.

**Don't re-resolve the transcript.** `readLease(sessionId)` goes through
`resolveTranscript`, which scans the projects tree. The `Session` rows in this
loop already carry `transcriptPath` — use `leasePathForTranscript(id, path)`
directly and the whole loop is one `stat`+read per session.

**Concurrency caveat:** `atomicWriteJson` is atomic per-file but there is no
cross-host CAS, and Syncthing has no locking. Two hosts writing the same lease
inside one sync window yields a `.sync-conflict-` copy. That's tolerable
(last-writer-wins, and the conflict file is itself a detectable signal) — it's
precisely why the *foreign + fresh → don't steal* branch has to exist.

This step is worth doing on its own merits, independent of any UI work: it's
what makes the existing split-brain guard actually load-bearing.

## Step 3 — surface foreign sessions with honest state

With step 2 in place, every live session on every host has a fresh lease, so a
peer can finally answer "what is that machine running?"

**Server — `GET /api/sessions/foreign`**

Walk `~/.claude/projects/*/*.lease.json`; for each lease with
`hostId !== ourHostId`, enrich from the sibling transcript exactly as
`listResumable` does (`cwdForTranscript`, `firstPromptTitle`, `lastUserText`,
`readTitleOverrides`) and reuse its dedupe (`UUID_EXACT` to reject
sync-conflict copies, newest-copy-per-id across duplicated project dirs):

```
{ sessionId, ownerHostId, heartbeatAt, leaseFresh, syncedAt,
  cwd, project, title, lastActivityAt, lastUserText }
```

`syncedAt` = transcript mtime. Report it **alongside** `heartbeatAt`, don't
collapse them into one "stale" boolean — see the caveat below.

Keep this separate from `/api/sessions/resumable` rather than widening that
endpoint. Resumable means "revivable here"; these rows explicitly are not.

**Client**

- `Host.hostId` is already resolved from `/api/info`, so `ownerHostId` → a
  configured `Host` (and its `label`) is free.
- Give these rows an **owner** and `isClosed: false`. That alone makes the
  existing machinery do the right thing: `MultiHost.isOffline` returns true
  (dimmed row, disabled composer), and `routeHost` returns the *unreachable
  owner* rather than a healthy peer — its comment already argues this case
  ("the op must fail honestly rather than land somewhere surprising"). No new
  routing logic.
- Render them in the **owner's section**, not the generic closed list, with a
  "last synced <syncedAt>" caption. Staleness has to be visible: transcript
  content that looks live but is hours old is the actual failure mode of this
  whole feature.
- Tap → transcript via the online host's `/api/sessions/<id>/messages`. Works
  today, unchanged.
- **Suppress Resume when `leaseFresh`.** The server already 409s, but the client
  shouldn't offer a button whose only outcome is an error — and today it offers
  it in exactly the dangerous case.

**Caveat worth designing around:** a lease's freshness travels over the *same*
Syncthing channel as the transcript. If sync lags past the 90s
`LEASE_FRESH_MS`, every foreign lease reads stale and the split-brain guard
silently switches itself off. Reporting `heartbeatAt` and `syncedAt` separately
lets the client tell "the owner stopped heartbeating" (owner really died) from
"we stopped receiving" (sync is broken) — two very different things that
collapse into the same stale flag otherwise.

---

# SCOPED PLAN — read + move only

Eugene's actual requirement: for an offline host's session, **read it** and
**move it to a live host**. No sending to the dead machine, no attribution UI.
That cuts the work to two small client changes plus one small server change.
**`/api/sessions/foreign`, staleness captions and owner-attributed rows are all
dropped.**

## Change 1 — read: fall back to a peer

Add a read-path route beside `MultiHost.routeHost`: when the owner is
unreachable, return `agnosticHost` instead of the owner. Use it in
`ensureHistory` and `messagePage` only. Sends keep `routeHost` unchanged — they
must still fail honestly against the owner.

Server: **no change.** Any host already serves any synced transcript by id
(verified against a non-live transcript).

## Change 2 — move: don't require closing the source

`SessionStore.transfer` (2365) is "close on source → resume on target", and
step 1 is unconditional:

```swift
do { try await sourceClient.close(id) }
catch {
    lastError = "Transfer: closing on \(source.label) failed: …"
    return nil          // ← aborts
}
```

So **transfer is impossible precisely when you need it** — the source is
offline, the close can't land, the move aborts. Same root assumption as
Change 1: always talk to the owner.

Fix: when the source is unreachable, skip the close *and* the
"wait for the pane to die" poll (2381-2385), and go straight to
`targetClient.resume`. For a genuinely down host the pane is already gone, so
there is nothing to close. `canTransfer` (SessionDetailView:486) already allows
this — it only needs `!session.closed` and a known owner, both true for an
offline-host row.

Server: **no change.** `POST /api/sessions/resume` already resolves the synced
transcript locally and spawns on the host you asked.

## Change 3 — lease coverage (the one thing that can't be skipped)

Skipping the close is safe only if the source is *actually* dead. The guard for
that already exists — `resumeClosedSession` calls `foreignFresh()` and 409s
"session is live on another host" — but it has nothing to read:

> **3 of 17 live sessions currently hold a lease.** Even lfg-`managed` ones
> mostly don't, because `acquireLease` fires only at creation and `renewLease`
> refuses to create one.

This matters more for Eugene than for most setups: per memory
[[lfg-pro-host-sleep-disconnects]], *unreachable-but-alive* (Tailscale
NAT-punch flaps) is his **normal** disconnect mode, not a rare one. Moving a
session whose agent is still running on the other machine forks it in two.

The mechanism is already correct — the lease syncs Pro↔Air over the same
Syncthing link, so an alive Air keeps its lease fresh and the move correctly
refuses; a dead Air goes stale in 90s and the move proceeds. It just needs the
acquire-or-renew loop in `startLeaseHeartbeat` (serve.ts:700), claiming only
`authoritative` sessions. See Step 2 above for the detail.

## Also worth a guard while touching move

`resumeClosedSession` does `const cwd = (await cwdForTranscript(transcript)) ?? SELF_REPO`.
If the original cwd doesn't resolve on the target, the session silently resumes
**in the lfg repo** — full conversation context, wrong directory. `~/dev` is a
synced Syncthing folder so it usually resolves, but a move should fail loudly
rather than relocate silently.

## Net

| | Before | Scoped |
| --- | --- | --- |
| New server endpoints | 1 | 0 |
| Server changes | endpoint + lease loop | lease loop only |
| Client changes | routing + new row type + attribution UI + captions | 2 small routing fixes |

## Rejected alternative

*Proxy the offline host's API through the online host* — pointless. The offline
host isn't answering anything; there is nothing to proxy. The synced transcript
is the only available source of truth, which is why the read-only mirror is the
whole design space.
