# Multi-host lfg — design

**Goal:** Two Macs (`A`, `B`) on the same Tailscale network, both running `lfg serve`, with `~/.claude` and `~/.codex` synced (iCloud) between them. From the iOS client:

1. **Start** a session on *either* machine.
2. **Transfer** a running session from one machine to the other.

---

## The key realization

The backend needs almost no changes. Two facts make this a mostly client-side feature:

- **Transcripts are synced.** A session started on `A` writes its transcript to `~/.claude/projects/<enc-cwd>/<id>.jsonl`, which iCloud replicates to `B`. So `claude --resume <id>` works on `B` with the *existing* `/api/sessions/resume` endpoint — the history is already there.
- **Session IDs are globally-unique UUIDs.** The iOS client's per-session state (transcripts, busy, queues) is already keyed by `sessionId`. As long as a session is live on **exactly one** host at a time (which "transfer" guarantees), that keying survives multi-host untouched — we only need to track *which host* each session lives on, for routing operations.

So: **the client fans out to N hosts, merges their lists, tags each session with its host, and routes each API call to the owning host.** "Transfer" = `close` on the source host + `resume` on the target host — both endpoints already exist.

### Load-bearing prerequisite (must hold)

`claude --resume <id>` on `B` resolves the transcript by **absolute cwd path** (the path is encoded in the project dir name). So both machines must reach the same session cwd at the **same absolute path**. This holds when: same macOS username (`~` identical) **and** repos live in the synced iCloud tree (as this repo does) — or are otherwise at matching absolute paths. Sessions whose cwd only exists on one machine can't be transferred; that's expected.

---

## Decisions (confirmed with Eugene)

- **Topology → client-side fan-out.** iOS stores a list of host URLs, polls each host, merges results, tags sessions by host, opens one SSE stream per host, and routes each operation to the owning host. Hosts stay independent; no "primary." (Implied by "transfer is done on the iOS client" — the client talks to both hosts directly.) Resilient: one Mac asleep → the other still works fully.
- **List presentation → one unified list, host chip per row** (my call; easy to switch to grouped later). Host becomes an optional filter alongside the existing user filter.
- **Create session → user always picks the host.** The new-session sheet shows a host picker **pre-selected to the default host**; if the default host is offline, it falls back to a reachable host. ("Default host" is a create-time placement default only — in fan-out there is no single connection default.)
- **Transfer → manual, client-orchestrated, from the ⋯ more-options menu** in `SessionDetailView` (next to Fork/Rename). Does `close` on the source host → `resume` on the target host → navigate to the new live id. Reuses existing endpoints; no new backend surface.

### Transfer caveats (handled in UI)

- `resume` mints a *new* sessionId (Claude continues into a fresh transcript) — the client just re-selects the returned id. Same behavior the resume flow already handles today.
- iCloud sync latency: transfer is safest when the session is **idle** (last turn flushed + synced). Offer transfer on idle sessions; show a brief "syncing…" beat if needed.
- Split-brain: if the source host is *unreachable* (not proven dead), resuming on the target could double-run. For two personal Macs this maps to the desired "laptop's closed, continue on desktop" flow; surface a subtle warning rather than block.

---

## Backend changes (small)

1. **`GET /api/info`** → `{ hostId, hostName, version }`.
   - `hostName` = `os.hostname()` (Tailscale MagicDNS name ≈ hostname); friendly display.
   - `hostId` = stable id for **de-duplicating a host reached via two URLs** (Tailscale IP vs MagicDNS). Use `os.hostname()`, or a uuid persisted in `data/host-id`.
   - That's the only required new endpoint. `new`, `resume`, `close`, `sessions`, `resumable`, streams all already exist per-host.

*(No change needed to `/api/sessions/resumable` — the client reconciles the synced-transcript duplication, see below.)*

## Client changes (the bulk)

1. **Host list config** (replaces single `lfg.baseURL`):
   - `AppSettings`: `hosts: [Host]` where `Host = { url, id?, name? }`, persisted to UserDefaults (JSON). Migrate the existing single `lfg.baseURL` into a one-element list on first launch.
   - `SettingsView`: host **list** editor — add / remove / test each host, per-host reachability dot, resolve `id`/`name` via `/api/info` on save.

2. **`SessionStore` becomes host-aware** (evolve, don't rewrite):
   - Hold `[Host]` + one `LFGClient` per host + per-host `reachability`.
   - `refresh()` fans out to all reachable hosts in parallel, tags each returned `Session` with its host, and merges.
   - **Routing table** `sessionId → host` so every op (`send`, `close`, `interrupt`, `answer`, `model`, `rename`, `fork`, …) picks the owning host's client. sessionId-keyed dicts (transcripts/busy/queues) stay as-is.
   - **One SSE `liveStream` per host** (each already caps at 24 ids); merge events by sessionId.
   - Per-host reachability with the existing debounce, surfaced per host in the banner/settings.

3. **Resumable de-duplication (client-side reconciliation):**
   - Merge every host's `/api/sessions/resumable`, **dedupe by sessionId** (same synced transcript listed by both hosts → one entry).
   - Then **subtract any sessionId that is live on *any* host** (kills the "phantom": host B lists host A's live session as resumable because it only sees its own live panes).
   - A resumable session is **host-agnostic** — resume it on whichever host the user picks (this is also the "transfer a closed session" path).

4. **`Session` gains a client-side `host` tag** (display + routing). Not sent by the server; set by the store from the fetching host. `ResumableSession` stays host-agnostic.

5. **New-session host picker:** the `new` flow gains a "Start on…" host selector (default: last-used / a designated primary).

6. **Transfer action:** in `SessionDetailView`, a "Move to <other host>" action (mirrors the Fork action) — `close(sid)` on current host, `resume` on target, `requestSelection(newId)`.

7. **Push registration:** register the APNs token with **every** host (each can push independently).

---

## Rough sequencing (for the build)

1. Backend: `GET /api/info` (+ tiny test).
2. iOS core: `Host` model, `AppSettings` host-list + migration, `LFGClient` unchanged (already URL-injected).
3. iOS store: fan-out refresh + routing table + per-host reachability + per-host SSE + resumable reconciliation.
4. iOS UI: settings host-list editor, host chip in list, host filter, new-session host picker, transfer action.
5. Verify: unit tests for merge/dedupe/reconciliation + routing; live two-host smoke (start on A, transfer to B, send after transfer).

## Out of scope (v1)

- Syncing `data/managed-sessions.json` / `data/aisdk/` across hosts (machine-local control planes stay local; the transcript is the shared truth).
- Auto-discovery of hosts (manual add for now; Tailscale API discovery is a later nicety).
- Simultaneous same-session-live-on-both (transfer is explicit, one-at-a-time).
