# iPhone Client Issues — Triage (2026-08-22)

Six reported problems, three root causes. Session: 50c624ca.

> **Update (12:0x, after "issues persist on 1.3.0"):** Root cause B is now FIXED,
> verified live, and deployed (server restart 11:49) — see
> `bug-reports/010-delegated-work-busy-regression.md`. Verification surfaced a
> FIFTH defect: a freshly spawned codex session could permanently bind to a
> days-old rollout because codex reads other rollouts at startup and the lsof
> ownership probe ignored access mode — this was the residual form of issue #2
> and is also fixed. New issue #7 (transcript scrolls away while typing) plus
> the surviving client-side items (#3 on device, error surfacing) are with
> worker session `ff4c4e3c` (`lfg-955908`); its fixes will need a new TestFlight
> build.
>
> **Update (14:06):** Worker fixes shipped in **TestFlight 1.3.0 (202608221402)**
> (VALID, IN_BETA_TESTING) — three stacked defects behind #7 (keyboard
> mis-anchor, onAppear follow-latch, bottom-pin drift), sim-verified against a
> live session. Still open: #3's raw device scroll smoothness (leads in
> `.codex/feature/transcript-keyboard-scroll-stability.md`), the ~121pt
> tool-row-collapse shift, and in-app error surfacing.
>
> **Update (15:0x, "transcript still loads slowly"):** measured the remaining
> open-path cost. Server pages are ~5ms even on the 536MB rollout — the real
> costs were (a) **zero compression anywhere on the phone path** (Bun doesn't
> gzip, Tailscale Serve doesn't either: a 74KB page shipped raw; now gzipped to
> 21KB at the serve boundary, deployed 15:03, tests in
> `src/gzip-response.test.ts`) and (b) **the client only paints from its local
> cache when the network is unreachable** — a normal open waits for network
> page 1, and every page merge re-sorts the whole transcript on the MainActor.
> Client fixes (hydrate-first, ~48KiB fast first page, incremental merge)
> delegated to worker `ff4c4e3c` for the next TestFlight.

## TL;DR

| # | Symptom | Status | Root cause |
|---|---------|--------|-----------|
| 1 | Transcript slow to load, late jump-to-end | **Fixed — update TestFlight** | Bug 009 (unbounded 1MB pages, server-side, live since 03:28) + SC5 open-at-latest fix (client-side, in TestFlight 1.3.0) |
| 2 | Codex sessions flap idle/active | **Fixed on Pro server** (03:28 restart) | Wrong rollout binding for long-lived promptless TUIs; verified stable live. Air still runs old code but is offline anyway |
| 3 | Laggy scroll, jumps ahead | **Fixed — update TestFlight** | Delayed programmatic `scrollTo` fighting the user's gesture; identity-anchored fix in TestFlight 1.3.0 |
| 4 | Background shells/agents never finish; sessions stuck "hanging" | **Root-caused, NOT yet fixed** | `busyWithRunningWork` regression from yesterday's delegated-work feature (a7bf99c) — details below |
| 5 | App syncs several times before settling after being away | **Partially structural** | Phone is on a relayed DERP path; Pro fell off the tailnet today 11:25–11:29 (recovered); Air off the tailnet ~2 days |
| 6 | Codex interrupt usually doesn't work | **Root-caused, NOT yet fixed** | Same `busyWithRunningWork` regression: "Stop" is offered on sessions that are actually idle, so Escape lands on an idle composer and does nothing |

**Action for Eugene right now: update to TestFlight 1.3.0 (202608221109)** — built 11:14 today from the working tree, after your "push a TestFlight version" message. That alone addresses #1 and #3.

## Root cause A — stale deploys (issues 1, 2, 3)

All three had fixes already written and verified in this working tree (uncommitted):

- **#1** — bug-reports/009: the 500-message page limit didn't bound bytes; this 1.09MB page crossed the client's 15s timeout, and a failed page restarted paging from the newest cursor. Fixed with a 256KiB page budget + same-cursor retry. Server side live on the Pro since the 03:28 restart; client side in TestFlight 1.3.0. The "jumps to end after some time" part is SC5 of the scroll-anchor work: the open-at-bottom pin now releases as soon as the newest tail renders instead of waiting for full history.
- **#2** — .codex/feature/codex-status-stability.md: one real codex turn emitted 95 alternating busy edges because a long-lived promptless TUI was bound to a stale rollout. Fixed via open-rollout (lsof) binding; live on the Pro since 03:28 and verified over 10 REST scans. If you still see flapping after today, reopen — but see Root cause B, which produces a *different* wrong-status shape (stuck busy, not flapping).
- **#3** — .codex/feature/session-history-scroll-anchor.md: the 50ms delayed `scrollTo(anchor: .top)` on page reveal snapped against continued scrolling. Replaced with an identity-backed scroll position updated atomically with the window expansion. In TestFlight 1.3.0.

**Deploy gap risk:** these fixes are uncommitted, on the Pro only. When the Air comes back it will serve old code (codex flapping included) until: commit + push from the Pro, pull + server restart on the Air.

## Root cause B — the delegated-work busy fold (issues 4 and 6)

Yesterday's `feat: expose delegated session work` (a7bf99c) added `busyWithRunningWork` (src/subagents.ts:20-26): a session is busy if its own turn is running **OR any child agent is "running" OR any background shell is alive**. Two independent investigations both landed on this fold as the defect. Three concrete bugs:

### B1. Synchronous subagents latch "running" forever
The server learns a child agent finished only from a `task-notification` row in the parent transcript — which Claude Code writes **only for async agent launches**. A foreground subagent's completion lands in a `tool_result` row (`toolUseResult.status`), which `readParentEvents` (src/subagents.ts:147-151) filters out entirely. Default at src/subagents.ts:285: `status = lifecycle?.status ?? "running"` → latched forever. Verified on real transcripts: five `Explore` agents finished in July still report "running" today; every test fixture pairs launch with notification, so the default branch was never exercised.

Blast radius: the latch is in the transcript permanently (survives /resume), the row reads "Working" forever, and `reduceTransition` (src/push/watcher.ts:100) returns early while busy — so the session **never fires another finished/needs-input push**. That is "stuck at hanging".

### B2. Long-lived background shells pin sessions busy by design
Any background shell with its output file still open (a dev server, a watcher) makes the session "Working" indefinitely — REST, journal, and push all fold it in. Live evidence: both codex sessions currently shown "Running" (`01a023cc`, `01a01ab8`) have an idle composer, a rollout whose last marker is `task_complete`, and exactly one background terminal each. They are false-Running rows.

### B3. The same fold breaks interrupt (issue 6)
The iOS Stop item only shows when `busy == true` — which B1/B2 make chronically true on idle sessions. So Escape is sent to an idle codex composer (does nothing; second Esc arms backtrack), and `interruptAndConfirm`'s "did the pane stop looking busy within 1.5s" check can never pass because `isBusy` (src/tmux.ts:1162) counts the same background terminal. Result: "most of the time I cannot interrupt" — the minority that works is when the session was genuinely mid-turn. Contributing defects found on the way:

- Every client-side error is swallowed: `store.lastError` is written ~30 places, read nowhere; host-routing miss silently returns (SessionStore.swift:3305).
- Server logs interrupts only after the 404/409 guards — ops.log has 13 interrupts ever, none since 08-17, so failures are invisible.
- One Escape send, never retried — the repo itself documents (src/tmux.ts:1238-1247, for dismissPrompt) that a lone ESC can sit buffered in a TUI's input parser; dismissPrompt retries 3x, interrupt retries 0x.
- 1.5s confirm window is likely too short for codex to unwind an in-flight tool.

### B4. Perf aggravator
The delegated-work enrichment re-streams whole transcripts when the mtime cache misses — measured 858ms per scan for a 536MB codex rollout, on the single Bun event loop, every ~1s. One big live codex session can starve the pump and freeze all statuses on the phone. Commit 0fe790e fixed this for the resumable path only, not the live path.

### Recommended fixes (in order)
1. **Stop folding background shells into `busy`** — surface them as the badge/count only. Also exclude `backgroundProcessCount` from the codex `isBusy` when used as the interrupt-confirmation predicate.
2. **Read `toolUseResult.{agentId,status}` as a lifecycle source** in `readParentEvents` (widen the prefilter to include `"agentId"`) so sync subagents terminate. One-shot discriminator: `listSubagentSessions` on transcript `86865f2b-…` should return `completed` instead of `running`.
3. **Instrument**: move `logOp` above the interrupt endpoint's 404/409 guards; surface `lastError` somewhere in the UI.
4. **Retry Escape** inside `interruptAndConfirm` while the pane still reads busy (mirroring dismissPrompt), and widen the confirm window to ~5s.
5. Skip codex rollouts in `runningBackgroundProcessCounts` (they can never contain `backgroundTaskId`) to kill the 858ms scans.

## Root cause C — transport (issue 5, and today's general brokenness)

- **The Pro fell off the tailnet at ~11:25 today.** The Tailscale extension restarted into `Stopped (WantRunning=false)` and nothing recovered it — the menu-bar GUI app is not running on the Pro, so there is no supervisor. I ran `tailscale up` at 11:29; serving resumed on both hostnames. **Recommendation: keep the Tailscale menu-bar app running / login item on the Pro**, or add a watchdog that reasserts `tailscale up` when the backend reads Stopped.
- **The Air has been off the tailnet ~2 days** (last seen 2d ago; ssh and tailscale ping both dead). Any session last seen on the Air is frozen at its last state on the phone (offline hosts structurally can't retract state — the client-side blanking in `rebuildSessions` is the only defense), and every cold app open pays a probe cycle against the dead host — part of the "syncs a few times before resolving" feel.
- **On the go, the phone reaches the Pro via a relayed DERP (HKG) path** — confirmed by the concurrent "Frequent cellular disconnections" session (a37f59f2): during a bad window `tailscale ping` phone→Mac timed out 5/5, which no client logic can mask. The multi-sync-then-settle behavior on reopen is the client re-baselining against hosts over that path; TestFlight 1.3.0's client changes may improve recovery pacing, worth re-testing after updating.

## Cross-session coordination

- `01a025c2` (codex) — did the codex-status fix and shipped TestFlight 1.3.0. Idle.
- `a37f59f2` (claude) — owns the cellular/Tailscale disconnect investigation. Idle; findings summarized above.
- The B-cluster fixes (busy fold, interrupt) are unowned — no session is working on them.

## Open items

1. Eugene: update to TestFlight 1.3.0 and re-test #1/#3/#5-recovery.
2. Fix root cause B (top 2 items minimum) — unowned; I can take this.
3. Bring the Air back online, then: commit/push the pending fixes from the Pro, pull + restart the Air's server.
4. Make Tailscale on the Pro self-recovering (login item or watchdog).
5. The report's item 7 was empty — if there was a seventh issue, it didn't make it into the message.
