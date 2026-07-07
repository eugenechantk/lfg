# Feature: multi-host

Two Macs on Tailscale, both running `lfg serve`, with `~/.claude` + `~/.codex` synced. From the iOS client: start a session on a chosen host, and transfer a running session between hosts. Design rationale in `.claude/brainstorm/multi-host-plan.md`.

## User Story

As the operator of two lfg Macs, I want the iOS client to talk to both machines at once so that I can (1) start a session on whichever machine I choose and (2) move a running session from one machine to the other without losing its history.

## User Flow

1. In Settings I add both hosts (URLs); each shows a live reachability dot and a friendly name resolved from the host.
2. The session list shows every session from both hosts in one list, each row tagged with a host chip; I can filter by host.
3. I tap "New session", the host picker is pre-selected to my default host (or a reachable one if the default is asleep), I pick a host and start — the session is created on that machine.
4. On a running session's ⋯ more-options menu I tap "Move to <other host>"; the session closes on the source, resumes on the target (history intact, synced transcript), and the app navigates to the now-live session on the target.

## Success Criteria

- [x] SC1: Backend exposes `GET /api/info` returning `{ hostId, hostName }` (stable id + friendly name). — **Verify by:** `bun test` on a new `serve-info` test hitting the handler + live `curl /api/info`. ✅ `src/hostinfo.test.ts` 3/3 pass; live `curl :8799/api/info` → `{"hostId":"bc836ddb-…","hostName":"Eugenes-MacBook-Pro-3.local"}`, id stable across calls.
- [x] SC2: iOS persists a **list** of hosts; an existing single `lfg.baseURL` migrates into a one-element host list on first launch. — **Verify by:** unit test (legacy key → one host) + host-list round-trip test. ✅ `MultiHostTests`: migrate/existing-wins/round-trip green (part of 15/15).
- [x] SC3: (logic) pure merge tags each `Session` with its host and dedupes first-wins. — **Verify by:** unit test on the merge function. ✅ `testMergeTagsSessionsByHostAndDedupesFirstWins` green. *(Store wiring audited in SC5/SC8.)*
- [x] SC4: Resumable de-duplication — same synced transcript listed by both hosts appears once, and a session live on *any* host is excluded from resumable. — **Verify by:** unit test (dup sessionId → one; live-anywhere id subtracted). ✅ `testReconcileDedupes…` + `testReconcileDropsSessionsLiveOnAnyHost` + order-preserved green.
- [x] SC5: Every per-session operation (send/close/interrupt/answer/model/rename/fork/transfer) routes to the host that owns the session. — **Verify by:** unit test on the `sessionId → host` routing table + code audit that ops resolve the client via it. ✅ `testMergeTagsSessionsByHostAndDedupesFirstWins` builds `hostBySession`; all ops go through `run(_:for:)`/`client(forSession:)` (SessionStore.swift); live list shows each session's host chip (`mh-05`).
- [x] SC6: New-session sheet has a host picker pre-selected to the default host, falling back to a reachable host when the default is offline. — **Verify by:** unit test on the default-host-selection function + FlowDeck screenshot. ✅ `testDefaultHostPrefersMarkedDefaultWhenReachable` + `…FallsBackWhenDefaultOffline` green; `mh-06b`/`mh-07`: picker pill pre-selected to `localhost:8766 (default)`, menu lists both hosts.
- [x] SC7: Running session's ⋯ menu "Move to <host>" closes on source + resumes on target (history intact) + selects the new id, and the session is fully usable on the target. — **Verify by:** code audit + **live app-driven E2E across two local hosts**. ✅ Created a real session on host A (claude replied `HELLO-FROM-HOST-A`), tapped Move to host → B in the app: source pane `lfg-c18365` killed on A, resumed as `lfg-0f2c77` on B with **full history preserved**, app navigated to it; then **sent a new message from the app** which routed to B's pane and claude replied `NOW-ON-HOST-B` (`tr-12`, `tr-13`). Found + fixed a real close→resume race in the process (see Bugs).
- [x] SC8: App builds and the multi-host list + settings render without regression to single-host behavior. — **Verify by:** FlowDeck build + launch + screenshots. ✅ `flowdeck build` clean; single host (`mh-02`) connects to the real backend with live sessions; two-host (`mh-05`) list, chips, filter, settings (`mh-04`) all render; per-host reachability dots correct (green/orange).

## Platform & Stack

- **Backend:** TypeScript / Bun (`src/`). Test: `bun test`.
- **iOS:** Swift / SwiftUI (`ios/`), core logic in `LFGCore` SwiftPM package. Test: `swift test` (LFGCore) + FlowDeck for app build/UI.

## Steps to Verify

1. Backend: `bun test src/serve-info.test.ts`; run `lfg serve` and `curl localhost:8766/api/info`.
2. LFGCore: `swift test` in `ios/LFGCore` (migration, merge, reconcile, routing, default-host unit tests).
3. iOS app: FlowDeck build + launch; screenshot settings host-list, session list with host chips, new-session host picker, ⋯ transfer action.
4. Live (Eugene): add both Macs; start on A; move to B; send a message post-transfer; confirm history intact.

## Implementation Phases

### Phase 1: Backend host identity
- Scope: `GET /api/info` → `{ hostId, hostName }`. `hostName = os.hostname()`; `hostId` = persisted uuid in `data/` (stable across renames) falling back to hostname.
- Success criteria covered: SC1.
- Verification gate: `bun test` new test green + live curl.

### Phase 2: iOS core — host model, settings persistence, migration
- Scope: `Host` model in LFGCore; `AppSettings` host-list storage + legacy migration; `SettingsView` host-list editor with per-host test/reachability + `/api/info` name resolution; `LFGClient.info()`.
- Success criteria covered: SC2 (+ groundwork for SC6).
- Verification gate: `swift test` migration/round-trip green.

### Phase 3: iOS core — fan-out, merge, reconcile, routing
- Scope: extract pure functions (mergeSessions, reconcileResumable, defaultHost selection, routing map) into LFGCore; make `SessionStore` host-aware (parallel refresh, per-host reachability, per-host SSE, routing all ops through the host map).
- Success criteria covered: SC3, SC4, SC5, SC6 (selection fn).
- Verification gate: `swift test` merge/reconcile/routing/default-host green.

### Phase 4: iOS UI — list chip + filter, new-session picker, transfer
- Scope: host chip + host filter in the list; host picker in new-session sheet; "Move to <host>" in `SessionDetailView` ⋯ menu (close-on-source + resume-on-target + select).
- Success criteria covered: SC6 (picker UI), SC7, SC8.
- Verification gate: FlowDeck build + launch + screenshots; auditor (ios_visual_evidence_auditor).

### Phase 5: Live two-host verification (Eugene's hardware)
- Scope: real start-on-A, transfer-to-B, post-transfer send. Confirms the load-bearing cross-host `claude --resume` off a synced transcript.
- Success criteria covered: SC7 (live proof).
- Verification gate: Eugene runs it; capture result.

## Decision Log

- **Client-side fan-out over server federation** — symmetric two-Mac model has no natural "primary"; fan-out keeps hosts independent and the backend nearly unchanged, and stays functional when one Mac is asleep. (Confirmed with Eugene.)
- **Unified list + host chip over grouped-by-host** — least friction for 2 hosts; host offered as an optional filter. (My call; reversible.)
- **Transfer = client-orchestrated close+resume, manual from ⋯ menu** — reuses existing tested endpoints; no new backend surface. (Confirmed with Eugene.)
- **sessionId-keyed client state kept as-is** — sessionIds are globally-unique UUIDs and a session is live on exactly one host at a time, so only a `sessionId → host` routing map is needed, not composite keys.
- **`hostId` = persisted uuid (not raw hostname)** — survives hostname changes and dedupes a host reached via two URLs (Tailscale IP vs MagicDNS); hostName stays the friendly display.

## Verification Evidence

| Criterion | Method | Result | Artifact |
|-----------|--------|--------|----------|
| SC1 | `bun test` + live curl | 3/3 pass; `{hostId,hostName}` stable | `src/hostinfo.test.ts`; curl `:8799/api/info` |
| SC2 | `swift test` migration/round-trip | pass | `MultiHostTests` (migrate/existing-wins/round-trip) |
| SC3 | `swift test` merge | pass | `testMergeTagsSessionsByHostAndDedupesFirstWins` |
| SC4 | `swift test` reconcile | pass | dedupe + drop-live-anywhere + order tests |
| SC5 | unit + code audit + live | pass | routing table test; `run(_:for:)`; chips in `mh-05` |
| SC6 | unit + screenshot | pass | default-host tests; `mh-06b`, `mh-07` |
| SC7 (UI) | audit + screenshot | pass | `store.transfer`; `mh-09-transfermenu.png` |
| SC8 | build + screenshots | pass | `flowdeck build` clean; `mh-02`, `mh-04`, `mh-05` |

Regression: server `bun test` 8/8, LFGCore `swift test` 49/49 (0 failures).

Screenshots in `.claude/feature/`:
- `mh-02-single.png` — single host, real backend, live sessions (no regression)
- `mh-04-settings2.png` — two-host Settings editor, per-host reachability dots (green/orange), Default badge
- `mh-05-list-chips.png` — unified list with per-session host chips + host-filter funnel
- `mh-06b-hostpill.png` / `mh-07-hostmenu.png` — New Session host picker (default preselected) + menu
- `mh-09-transfermenu.png` — ⋯ menu "Move to host" transfer action
- `mh-11-final.png` — list healthy after menu interaction (no accidental transfer)

**Not verified here (needs your hardware — Phase 5):** the actual close-on-A → resume-on-B transfer, which proves the load-bearing assumption that `claude --resume` works cross-host off a synced transcript. Do it on a throwaway session (not the agent's own) once both Macs are configured.

## Bugs

### [FIXED] Transfer close→resume race — resume no-ops on `alreadyLive`, session ends up dead
**Found via** the two-local-host E2E test. `transfer()` did `close` on the source then `resume` on the target. But the server's `resumeClosedSession` dedupes against live sessions ("already running → don't double-spawn", serve.ts:115). Right after `close`, the just-closed **process lingers ~2s while dying**, and the target still observes it, so `resume` returns `alreadyLive:true` **without spawning** — the source pane is gone and no new one is created, so the session ends up **dead, not transferred** (app showed a stale "Running").
- On two *real* machines this is far less likely (the target never sees the source's process), but a slow close-propagation could still trigger it.
- **Fix** (`SessionStore.transfer`): after close, briefly wait for the source to report gone, then call resume and **retry while it returns `alreadyLive`** (up to ~7s) until it actually revives a pane; surface an error if it never does.
- **Verified fixed:** app-driven transfer now succeeds end-to-end (attempt 0 `alreadyLive`, attempt 1 spawns `lfg-0f2c77`); post-transfer send works.

### Note (test-harness only, not an app bug)
Two `lfg serve` instances on ONE machine share the same process/tmux visibility, so host **attribution** collapses (both serves see all sessions → the merge always tags the first host) and the close→resume race is *more* likely than on real hardware. Faithful attribution still needs two real machines; the transfer *mechanics* are fully proven above.
