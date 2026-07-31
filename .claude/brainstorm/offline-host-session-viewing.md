# Viewing offline hosts' sessions via an online host

**Date:** 2026-07-29
**Question:** iOS client can't view sessions on an offline host. Since `~/.claude` is
shared across hosts, can an online host serve them read-only?

**Answer:** Yes — the server-side read path is *already* host-agnostic. But the
premise is currently broken: the `~/.claude` Syncthing sync has been dead since
2026-07-25. Fix that first; the feature is small after.

---

## Finding 1 — the sync is dead (blocker)

| Evidence | Value |
| --- | --- |
| `which syncthing` | not found (binary gone) |
| `~/Library/Application Support/Syncthing/syncthing.log` mtime | **2026-07-25 22:37** |
| Last log line | `Folder failed to sync, will be retried (wait=32m1s ... folder.id=mgwa7-zewio)` |
| Launch agent in `~/Library/LaunchAgents` | none |
| Newest `.claude` sync-conflict file | 2026-07-16 |
| Transcript mtimes clustering at `Jul 25 22:37` | last sync write |

So today an online host holds a **4-day-stale** copy of the other host's
transcripts. Any "view the offline host's session" feature built now would show
stale conversations with no signal that they're stale.

Root cause of the stop looks like the `dot-codex` folder wedging on
`Codex Computer Use.app` (`chmod ... operation not permitted` — TCC/quarantined
app bundle) in a retry loop, then the binary disappearing (brew cleanup?).

**Fix:** reinstall Syncthing, add `computer-use/` to `~/.codex/.stignore` so a
signed .app bundle can't wedge the folder again, and put it under launchd so it
survives reboots.

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

## Recommendation

1. **Repair + harden the sync** (reinstall Syncthing, stignore `computer-use/`,
   launchd). Everything below is built on it, including the safety guard.
2. **Widen lease coverage.** Small, self-contained, and it closes a real
   split-brain hole that exists today whether or not step 3 ships.
3. **`/api/sessions/foreign` + owner-attributed read-only rows.**

Step 2 is the one I'd do regardless. Step 3 without step 1 ships stale data
that looks live.

## Rejected alternative

*Proxy the offline host's API through the online host* — pointless. The offline
host isn't answering anything; there is nothing to proxy. The synced transcript
is the only available source of truth, which is why the read-only mirror is the
whole design space.
