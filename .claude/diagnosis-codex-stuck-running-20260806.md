# Codex sessions stuck on "Running" — diagnosis (2026-08-06)

Reported: `codexy-231643-85569` still shows **Running** in the iOS client although
codex finished its turn. Same for `codexy-124211-26549`.

## Verdict

Not a codex bug, not a state-derivation bug. **The server's journal pump stopped
emitting `busy` updates, and the client is architecturally unable to correct a
stale journal value from the REST snapshot it already has.**

Both codex sessions were *legitimately* busy at the instant the pump last spoke.
Every client latched that `busy: true` and nothing will ever un-latch it.

## Ground truth

Server-side, both sessions are idle and have been since 13:58:

| source | says |
| --- | --- |
| `GET /api/sessions` | `busy: false`, `status: "ok"`, `prompt: null`, `closed: null` |
| lease `019fd27f-….lease.json` | `{"state":"idle","stateEvent":"Stop","stateAt":13:58:23}` |
| rollout tail | `task_complete`, `turn_id 019fd592-…`, 13:58:23 |
| `sessionTurnState()` (re-run out of process) | `{"state":"idle","source":"transcript"}` |
| `isBusy(pane)` | `false` |
| pane text | idle at the `›` composer, "Worked for 22m 06s" |

So every layer of the state stack agrees the session is idle. The problem is
purely delivery.

## The journal's last word

`~/.lfg/journal.db`, every `busy`/`prompt` event since the server started
(pid 54000, 12:50:12):

```
49249  12:50:14  019fd27f-92e  busy  {"busy":true}     <- codex, last word
49261  12:50:14  019fd561-01a  busy  {"busy":true}     <- codex, last word
49266  12:51:41  d45c5fbf-7d4  busy  true
49279  12:52:31  d45c5fbf-7d4  busy  false
49281  12:52:31  03533b45-6a9  busy  true
49285  12:52:32  d45c5fbf-7d4  busy  true
49326  12:55:06  6cc1cc66-4b5  busy  true
49885  14:04:55  193eed5a-1db  busy  true             <- last poll-loop output, ever
```

`12:50:14` is the pump's boot burst. `busy: true` was **correct** then — both
codex sessions were mid-turn. Nothing was emitted for either session again, so
`busy: true` is what every client still holds.

## Why the client can't self-correct

`SessionStore.refresh` (`ios/LFG/SessionStore.swift:1686`) seeds `busy` from the
REST snapshot only for sessions the journal has *not* spoken for:

```swift
for s in fresh {
    guard let sid = s.sessionId, let b = s.busy else { continue }
    if busyFromJournal.contains(sid) { continue }   // <- permanent veto
    busy[sid] = b
}
busyFromJournal.formIntersection(Set(fresh.compactMap(\.sessionId)))
```

`busyFromJournal` is only cleared when a session **leaves the live list**. These
codex sessions never leave it — the tmux pane is alive and idle at the codex
prompt. So the correct `busy: false` sitting in every `/api/sessions` response is
discarded on every refresh, forever.

The rationale in the comment ("a journal value is fresher than this snapshot") is
right when the pump is healthy and wrong in exactly this failure mode: the
journal value is 84 minutes old and the snapshot is 200 ms old.

`SessionDetailView.swift:295` then renders `Text("Running")` off `store.busy[sid]`.

## Why the pump went quiet

The pump appends a `busy` event only when the value **changes**
(`src/journal-pump.ts:210`), so silence is normally indistinguishable from
"nothing happened". Here it is not:

- **The poll loop has produced nothing since 14:04:55** (~1h10m), while a healthy
  loop sweeps every session every second.
- **My own claude session (`b15d76c5-…`) has zero journal events** despite its
  transcript being written continuously right now. `refreshWatchSet()` only runs
  inside `pollLoop`, so a session that starts after the loop stops is never added
  to the watch set at all.
- `sample 54000 3` shows the main thread **2159/2527 samples parked in
  `kevent64`** with essentially no `posix_spawn`. A live pump spawns
  `tmux capture-pane` ~37×/second. The event loop has nothing pending.

`pollLoop` is a self-scheduling async function whose next `setTimeout` is only
armed after the body completes:

```ts
const pollLoop = async () => {
  if (stopped) return;
  await refreshWatchSet();          // <- NOT inside the per-session try/catch
  for (const w of watched.values()) {
    try { await pollOne(w); queueOne(w); … } catch {}
  }
  pollTimer = setTimeout(pollLoop, POLL_TICK_MS);
};
```

Either a rejection out of `refreshWatchSet()` or a promise that never settles
inside the loop kills the timer permanently, silently, with no supervision and no
log line. The pump then looks alive (message tailing is a *separate* loop and did
keep running until 14:07) while every state signal is frozen.

I could not pin which call stalled without instrumenting the live process, and
did not restart it. Everything `pollOne` does was re-run out of process against
the same session and completed in **558 ms for all 37 sessions**
(`capturePane` 4 ms, `sessionTurnState` 0 ms, `pendingToolPrompt` 1 ms), so the
stall is not inherent to the work.

## Also found

- **Two `serve` processes.** pid 54000 (real, `~/.lfg/journal.db`, port 8766) and
  pid 66597 — a scratch server the codex run left behind, cwd
  `.worktrees/browser-preview-prototype`, data dir
  `/private/tmp/lfg-browser-preview.Vxnspm`, burning 17% CPU. Separate DB, so it
  is not corrupting anything, but it is a genuine instance of "codex leaves
  things running".
- `019fd561-01a9` has a send stuck in a **retry loop** — `queue {"kind":"failed"}`
  re-emitted at 14:05:41, 14:05:53, 14:09:12, 14:11:11, 14:12:37.
- Two sessions share the tmux prefix `019fd27f` (`-5353` and `-92ec`) from two
  codex launches 16 s apart; only `-92ec` is bound to the pane.

## Fixes, in priority order

1. **Supervise the pump loops.** Wrap each iteration in `try/finally` so the
   timer is re-armed no matter what, add a per-session timeout around
   `pollOne`/`tailOne`, and log when a sweep exceeds its budget. A silent
   permanent stop is the worst possible failure for a change-only event stream.
2. **Make the client's journal veto expire.** `busyFromJournal` should hold a
   timestamp, not a bare flag: if the journal has not spoken for a session in
   ~60 s and the REST snapshot disagrees, take the snapshot. The correct answer
   was in hand the whole time.
3. **Consider a heartbeat re-assert.** Have the pump re-emit each session's
   current `busy`/`prompt` every N minutes even when unchanged, so a client can
   detect staleness instead of inferring it from silence.
4. Clean up the orphaned worktree server and the stuck sendq retry.

## Immediate unwedge

Restarting `serve` fixes the display (it re-emits a fresh boot burst for every
session), at the documented cost of losing in-memory session tracking. That is a
workaround, not the fix — item 1 is.

---

# Fixed — 2026-08-06 14:27

Items 1 and 2 are implemented; 3 was not needed once 2 landed; 4 is noted below.

## What changed

**Server — `src/journal-pump.ts`.** Three new pieces, all unit-tested:

- `startSupervisedLoop` re-arms the next tick in a **`finally`**, so a throw costs
  one sweep instead of the loop. It logs `[pump] <name> sweep threw: …` and
  `[pump] <name> sweep took Nms` past a 10s budget, so the next occurrence is
  visible instead of silent.
- `settleWithin` bounds a step at 15s and reports which happened rather than
  rejecting, so a sweep survives a step that never settles.
- `StepRunner` runs one keyed step per sweep and **refuses to start a second copy
  while the first is outstanding**. Without that guard, the timeout would convert
  one wedged session into a spawn storm — a new abandoned copy every second on the
  single event loop. A wedged session now costs exactly one outstanding promise
  and the other 36 keep reporting.

`refreshWatchSet()` — the call that sat outside the per-session `try/catch` and
was the most likely killer — is now both inside the supervised body and bounded.

**Client — `ios/`.** `busyFromJournal: Set<String>` became
`busyStatedAt: [String: Date]`, and the veto is decided by
`JournalFreshness.snapshotWins` (new, in `LFGCore`, with tests). Past 60s a
journal value stops out-voting the REST snapshot, so a dead pump self-corrects
within one look at the screen instead of never. Clock-skew safe: a `statedAt` in
the future reads as fresh rather than as an enormous age.

## Verification

| check | result |
| --- | --- |
| `bunx tsc --noEmit` | clean |
| `bun test` | **335 pass / 0 fail** (12 new: supervision, timeout, in-flight guard) |
| `swift test` (LFGCore) | **229 XCTest + 11 swift-testing pass / 0 fail** (8 new) |
| `flowdeck build --scheme LFG` | Build Completed |
| pump alive after restart | 41 events in 75s, including 3 `busy` transitions |
| pump doing work | `posix_spawn` 19/2527 samples (was 7), `kevent64` 47% (was **85%**) |
| the session that proved it was dead | `b15d76c5-…` now journals normally |

On restart both codex sessions were re-stated correctly:
`019fd561-01a9` → `busy: false` (the stuck value, now right), and `019fd27f-92ec`
→ `busy: true` — genuinely correct, because its long-stuck `/review` send landed
during the restart and codex is actually working again.

Incidental confirmation of the known codex gap: that session's `paneBusy` reads
`false` while it is visibly "Working (1m 50s)". The pane scraper does not know
codex's TUI chrome, so codex busy rides entirely on the transcript layer. Fine
today, but it means codex has no pane backstop if the transcript layer ever
abstains.

## Not done

- **The client fix is built and tested but not shipped.** It reaches the phone
  only via a TestFlight build; the server fix is live now and is the one that
  matters for the reported symptom.
- The 60s-TTL path is unit-tested, **not exercised live** — reproducing it means
  stopping the pump on the shared host, which would disrupt every other agent.
- The orphaned worktree server (pid 66597) was **left running**: its parent is
  the codex process itself (pid 87565), so codex is tracking it as its own
  background job ("1 background terminal running · /stop to close"). Killing it
  out from under a live codex session is its owner's call, not mine.
