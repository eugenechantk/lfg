# Improvement Log — Session 20260729-offline-host-sessions

## Tracker

- [ ] 2026-07-29 — Framed "view offline host's sessions" as missing without first checking the client's closed/resumable path, where most of it already ships
- [ ] 2026-08-01 — Declared Syncthing dead off `which syncthing` (it's a GUI app, not on PATH) and read benign WRN lines as a broken folder
- [ ] 2026-08-01 — Proposed a server endpoint + lease redesign before locating the actual client-side routing bug

## Log

### 2026-07-29 — Answered "what's missing" before reading the client's closed-session path

**What happened:** Eugene asked whether an online host could serve an offline
host's sessions. I traced the *server* read path thoroughly (`resolveTranscript`,
`/api/sessions/<id>/messages`, `listResumable`, `leases.ts`) and concluded the
capability was missing three pieces. Only when Eugene asked me to expand on steps
2 and 3 did I read `SessionStore.fetchResumablePages` and `MultiHost.routeHost` —
which already fan `/api/sessions/resumable` out to every reachable host, dedupe
across them, and carry an explicit design comment: *"A closed session is
host-agnostic: its transcript is synced, so any live machine can revive it."*
Viewing an offline host's sessions largely works today. The real gap is narrower
and more interesting: **attribution and split-brain safety**, not visibility.

**Why this was wrong:** I traced one side of a client/server feature and
generalized to the whole feature. The server having no "foreign sessions"
endpoint did not imply the client had no path to that data — it reached it by a
different route (the resumable list). I also had a direct hint I skipped past:
the fan-out function's own doc comment names the synced-projects overlap.

**What better looks like:** For any question phrased as "can the client do X",
read the client's data path *before* concluding from server code alone. Cheap
check: grep the client for the feature's nouns (here, `resumable`, `closed`,
`byHost`) and read the reconciliation logic. Two greps would have caught this
before the first answer went out.

**Second-order win worth keeping:** verifying the load-bearing premise
("`.claude` is shared across hosts") was right to do — though the conclusion I
drew from it was wrong; see the 08-01 entry.

### 2026-08-01 — Declared Syncthing dead from `which syncthing`

**What happened:** Concluded the `~/.claude` sync was dead and built a whole
recommendation ("repair the sync first — everything depends on it") on two bad
reads: `which syncthing` returning "not found", and `Failed to sync … / Folder
failed to sync, will be retried` WRN lines in the log. Both were wrong.
Syncthing on macOS runs from `/Applications/Syncthing.app/Contents/Resources/`,
which isn't on PATH, and those WRN lines said *"no connected device has the
required version of this file"* — i.e. the only copy is on the peer that's
offline. Entirely benign. `projects/**.jsonl` was syncing the whole time.

**Why this was wrong:** I treated absence-of-binary-on-PATH as
absence-of-process without running `ps`, and read error-shaped log lines as
proof of failure without reading what the error actually said. Both are the
same mistake: taking a proxy signal as ground truth when the direct signal was
one command away. This is precisely what memory `ground-truth-before-hypothesizing`
warns about, on a premise I had flagged as load-bearing.

**What better looks like:** To decide whether a daemon is running, run `ps`, not
`which`. GUI-app-packaged daemons on macOS (Syncthing, Tailscale, Docker) are
never on PATH. And read the error *text* before concluding from the error
*level* — "no connected device has the required version" is expected when a peer
is down and means the opposite of a broken folder.

### 2026-08-01 — Designed the fix before finding the bug

**What happened:** Across two turns I proposed a new server endpoint
(`/api/sessions/foreign`), a lease-coverage redesign, and client work — before
ever tracing what actually happens when you tap an offline host's session. When
Eugene asked the direct question ("what's the problem that makes it not
possible?"), four greps found it in minutes: `applyHostFetch` keeps a down
host's rows, those rows land in `liveIds` and suppress the peer's copy, and
`routeHost` sends the read to the unreachable owner. Client-side, ~one function,
no server change needed.

**Why this was wrong:** I was asked "is it possible?" and answered with an
architecture, skipping the step of reproducing the failure path. Designing
before diagnosing meant two turns of real analysis aimed slightly off-target —
the lease/endpoint work is genuine, but it isn't what blocks viewing.

**What better looks like:** Before proposing any fix for "X doesn't work", trace
the concrete failure path end to end — for a client/server feature that means
following the actual request the UI makes and finding where it dies. State the
root cause in one sentence before writing a single line of design.
