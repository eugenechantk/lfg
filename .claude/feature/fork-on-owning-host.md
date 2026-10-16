# Feature: fork runs on the session's own host

## User Story

As Eugene, when I fork a session that belongs to another Mac, I want the fork to run on that
Mac and open in an iTerm window attached to it remotely, so the branch lives where the work
lives.

## Background (ground truth, 2026-10-10)

- **Live rows already route correctly in code.** A live row's host is the host that reports
  it. `DesktopSessionCreator.fork` posts to `item.hostURL`, and `Opener.open` attaches over
  ssh or mosh for a non-local host. This path has never been run for real: the Pro has no fork
  of an Air session, and the Air has one fork, from August.
- **Closed rows go to the wrong host.** `~/.claude/projects` and `~/.codex/sessions` are
  synced, so both Macs list every closed transcript. The desktop merge keeps the first host
  in `hosts.json` order, which is the Pro. A session last run on the Air shows as a Pro row,
  and forking it runs on the Pro.
- **Leases cannot answer "who ran it last".** `*.lease.json` is in `~/.claude/.stignore`
  (host-local), and the agent hook deletes a lease when its session genuinely ends — that
  is how `closed` resolves at once. First design (lease `hostId`) was dropped after the live
  test showed the lease gone seconds after the session ended.

## User Flow

1. In the desktop app, right-click a session that belongs to the Air (live, or closed and
   last run on the Air). Choose **Fork session**.
2. The "Forking session" sheet shows. The Air's server forks the session in a new tmux
   session on the Air.
3. An iTerm window opens on this Mac, attached to the fork's tmux session on the Air through
   the Air's configured transport.

## Success Criteria

- [x] SC1: Each host reports when IT last ran a closed session — **Verify by:** `ran-here.test.ts`; `/api/sessions/resumable` on both hosts.
- [x] SC2: The desktop app gives a closed row to its last host, falling back to config order — **Verify by:** `ClosedRowOwner` checks in `--desktop-feature-test`; live: a closed Air session shows under the Air in the real app.
- [x] SC3: Forking a LIVE Air session from the Pro runs the fork on the Air and opens a remote-attached iTerm window — **Verify by:** real app, AX "Fork session" on a throwaway Air session; the Air's `managed-sessions.json` gains the fork; `tmux list-clients` on the Air shows a remote client on the fork.
- [x] SC4: Forking a CLOSED Air session from the Pro does the same — **Verify by:** same rig after the throwaway source ends.
- [x] SC5: Existing tests pass — **Verify by:** `bun test` for leases/sessions files touched; `--desktop-feature-test`.

## Platform & Stack

- Server: Bun/TypeScript (`src/ran-here.ts`, `src/sessions.ts`, heartbeat in `src/commands/serve.ts`).
- Desktop: single-file SwiftUI (`desktop/LFGSessions.swift`).
- Out of scope: the iPhone app has the same first-host rule in `MultiHost.reconcileResumable`;
  it reads the same new field once changed, but shipping it needs a TestFlight build.

## Decision Log

- **A host-local ran-here ledger** (`~/.lfg/ran-here.json`, `src/ran-here.ts`), fed by the
  30 s lease heartbeat. Each host vouches only for its own runs; the client takes the latest.
- **A claude row counts only when its pidfile names the id.** The live test caught the Pro
  binding a bare `claude` (pid 98777, pidfile `d044585b`) to a transcript just synced from the
  Air (newest-unclaimed-in-cwd guess) and writing a lease for it. Codex rows count as listed.
- **Leases dropped as a signal entirely** (deleted on end, polluted by guessed bindings), so
  `leases.ts` is unchanged.
- **Sessions that ended before the ledger existed have no record** and fall back to config
  order (Pro), the old behaviour. The ledger fills as sessions run.
- **Fallback to config order** when the owner is unknown (old transcript, no lease) or does
  not list the row (offline, sync lag), so no closed row disappears.
- **`lfg --fork-session <id> [plan]`** added beside `--open-session`: the real refresh and
  row lookup, then exactly the menu item's action; `plan` prints the owner and fork URL
  with no side effects, for checking a Mac someone is using.
- **Clicking a closed row is unchanged.** It still resumes on this Mac; only the row's host
  label, fork, and tool switch follow the owner.

## Verification Evidence

Run 2026-10-10 against the real Pro + Air (hosts.json unchanged), test build signed with the
Developer ID, driven through AX (`AXShowMenu` on the row → "Fork session").

| SC | Action | Observed |
|---|---|---|
| SC1 | probe 2 (`965a4ef9`) run on the Air, then ended | Air ledger `965a4ef9 → 1791623608331`; `/resumable`: Pro `lastRunHereAt: null`, Air `1791623608331` |
| SC2 | Closed list in the real app | probe 2 shows **Air**; probe 1 (ended before the ledger existed) shows **Pro** — old behaviour side by side (`closed-air2-vs-air1.png`); 7 `ClosedRowOwner` checks in `--desktop-feature-test` |
| SC3 | Fork live Air probe 1 from the Pro | Air `managed-sessions.json`: fork `lfg-290e25` at 17:07:14; Air mosh-server `attach-session -t lfg-290e25` with a client; Pro `mosh-client … air` (`live-air-forking.png`) |
| SC4 | Fork closed probe 2 from the Pro | sheet names "FORKPROBE-AIR2"; Air fork `lfg-eae3fd` at 17:38:10, 0 forks on the Pro; Air mosh-server attached to `lfg-eae3fd` |
| SC5 | Tests | `ran-here.test.ts` 4/4; `sessions-resumable-closed` 3/3 with `--timeout 30000` (its 5 s default times out with or without this change — pre-existing); `--desktop-feature-test` 180/180 |

**Reverse direction (from the Air, whose hosts.json lists the Air FIRST), 2026-10-10 17:46–17:53.**
The Air was in use, so no GUI automation there; each link was run headless instead.

| Step | Action | Observed |
|---|---|---|
| Owner | Pro probe `df87c1c9` run on the Pro, ended, synced to the Air; `lfg --fork-session df87c1c9… plan` on the Air (new hook, test copy) | `{"host":"Pro","closed":true,"forkURL":"https://lfg-pro.eugenechantk.me/api/sessions/fork"}`; Air probe 2 → `"host":"Air"` |
| Fork | Same POST the app sends, from the Air through Cloudflare | fork `lfg-f54a14` created on the Pro |
| Attach | Air runs `lfg --attach-command pro lfg-f54a14 mosh-bridged` in a sized pty | Pro: `lfg-f54a14` client 120×40 whose parent is `mosh-server` |

Two caveats seen on the way: (1) for ~90 s after a Pro session ends, the Pro's outdated hook
keeps its lease fresh, the Pro does not list the row as closed, and the Air (only lister)
briefly owns it; (2) the Air→Pro Cloudflare ssh tunnel stalled past both bootstrap attempts
(2 × 5 s) at 16:48 and again at 17:50 — `mosh-bridged` reports "bootstrap on 'pro' failed".

Cleanup: both forks' tmux sessions killed on the Air (remote attaches and iTerm windows closed).
The four probe transcripts remain as closed rows.

## Bugs

- Pre-existing, not fixed: desktop search returns no rows for "FORKPROBE" although both
  servers' `/api/sessions/search` return them (same on the HEAD build; "Shinkai" works).
