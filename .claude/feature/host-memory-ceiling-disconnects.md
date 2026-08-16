# Host memory ceiling disconnects

## Problem

The physical iPhone loses its LFG event stream outdoors even while Tailscale
VPN On Demand is enabled. The phone's Tailscale peer is healthy and has an
active direct endpoint; the disconnect is on the host. `lfg serve` repeatedly
crosses the supervisor's 4 GB RSS ceiling and is killed, and every kill drops
all `/api/events` streams. VPN policy cannot prevent it.

Evidence from `/private/tmp/lfg-serve.log`, 2026-08-16 morning — five kills in
just over an hour, at 4252, 4662, 4379, 4388 and 5208 MB, with lifetimes of
62 s to 26 min:

```
12:05:32 start → MEMORY CEILING at 4662MB after 1564s
12:31:37 start → MEMORY CEILING at 4379MB after  362s
12:37:40 start → MEMORY CEILING at 4388MB after  723s
12:49:44 start → MEMORY CEILING at 5208MB after  632s
13:00:18 start → MEMORY CEILING at 4379MB after 1203s
```

The live transcript corpus now contains Codex rollouts of 511, 484, 357, 256
and 246 MB. Two read paths scaled with file size instead of with the amount of
data actually wanted.

### Allocator 1 — `scanBack` re-read its whole window after every miss

`src/transcript.ts`. The backward JSONL scanner widened the tail and rescanned
every previously-seen byte after each miss, so a match near the head of a large
rollout was quadratic in I/O and allocation.

### Allocator 2 — `messagePage` read the entire transcript into one string

`src/sessions.ts`. `messagePage` calls `recentMessages(path, 0, {maxBytes: null})`
to serve a single 220-message page. That did `(await file.slice(0).text())` and
`.split("\n")` — for the 511 MB rollout, one ~511 MB string plus the line array
built from it, all to return 220 of 1290 messages. Every phone scroll-back on a
big Codex session paid it.

## Success criteria

- [x] Backward transcript scans preserve newest-first and full-file semantics.
- [x] Each byte range is read at most once during a miss; individual reads stay
      bounded by the configured step size.
- [x] Split JSONL records are reconstructed correctly across read boundaries.
- [x] Whole-transcript reads never materialize the file as a single string.
- [x] The streamed reader returns messages identical to the string reader,
      including records spanning many chunks, multi-byte characters astride a
      chunk boundary, and a final row with no trailing newline.
- [x] The focused transcript tests and full Bun test suite pass.
- [x] A production-sized rollout scan completes without multi-gigabyte RSS
      growth.
- [ ] The supervised host stays below its 4 GB ceiling across an observation
      window longer than the worst observed pre-fix lifetime (26 min).

## Verification evidence

Measured against the real 511 MB rollout
`~/.codex/sessions/2026/08/14/rollout-2026-08-14T15-36-28-…jsonl`, peak RSS
sampled every 25–50 ms in a dedicated Bun process
(`scratchpad/bench-scanback.ts`, `bench-messagepage.ts`).

### `scanBack`, worst case (a `pick` that never matches — full walk to the head)

| | peak RSS | wall time |
|---|---|---|
| before | **5226 MB** | 13 057 ms |
| after | **915 MB** | 769 ms |

5226 MB alone exceeds the 4096 MB ceiling, which matches the observed 4.3–5.2 GB
kill points.

### `messagePage`, one 220-message page

| | peak RSS | wall time |
|---|---|---|
| before (whole file as one string) | 1987 MB | 843 ms |
| first rewrite (`carry += decode(chunk)`) | **3413 MB** | 2790 ms |
| after (byte carry, decode each line once) | **1013 MB** | 273 ms |

The middle row is the important one: the textbook string-carry streaming reader
was *worse than the code it replaced*. Rows in these rollouts average ~137 KB
and Bun streams 256 KB chunks, so the `carry` string is re-flattened by
`indexOf` on every chunk — quadratic in record length. Carrying `Uint8Array`
fragments and decoding each complete line exactly once is what actually pays.

### Equivalence

`scratchpad/equiv-messagepage.ts` on the same 511 MB file: the streamed line
sequence and `(await file.text()).split("\n").filter(Boolean)` are identical —
3717 lines each, `firstDiffIndex: -1`. `messagePage` returns the same 1290-message
total and the same 220-message page.

`src/sessions-message-stream.test.ts` holds the invariant as a unit test:
`recentMessages(path, 0, {maxBytes: null})` (streamed) must equal
`recentMessages(path, 0, {maxBytes: 1 GB})` (the string path, which starts at
byte 0 for any file smaller than the cap). Cases: plain transcript, a 5 MB record
spanning 21 stream chunks, 4 MB of CJK + emoji guaranteeing a multi-byte scalar
lands astride a chunk edge, a final row with no trailing newline, and an empty
file. Chunk size confirmed at 262 144 bytes, so these genuinely exercise the
carry path rather than passing vacuously.

Full suite: 623 pass, 0 fail, 55 files.

### Deploy

Bun has no hot-reload. Fixed code ran only after `lfg serve` was restarted at
13:26:29 (pid 94573) — `src/transcript.ts` mtime 13:03:40, `src/sessions.ts`
13:24:43, both older than the process start. Post-restart health: loopback
`/api/ping` 200 with LFG JSON, `http://100.120.101.14:8766/api/ping` 200,
`https://eugenes-macbook-pro.tail97cc70.ts.net/api/ping` 200.

## The gauge was broken too

Everything above is real, but it was optimizing against a threshold that was
measuring the wrong thing. Prompted by "is it possible to not kill lfg but just
clean up", two measurements reframed the problem.

**There is nothing to clean up.** `Bun.gc(true)` collects everything already:

| | heapUsed | external | RSS |
|---|---|---|---|
| after work | 695 MB | 694 MB | 1645.4 MB |
| after 3 forced GCs + idle | **4.7 MB** | 3 MB | **1645.6 MB** |

The JS heap empties completely and RSS does not move one megabyte. The memory is
already free *inside* the process; the allocator has simply not returned the
pages to the OS.

**`ps` RSS is not memory pressure on macOS.** Same instant, live `lfg serve`:

```
ps RSS            3326 MB
phys_footprint     906 MB
  dirty            911 MB
  clean             35 MB
  RECLAIMABLE     2471 MB   ← counted by RSS, free for the kernel to take
```

`WebKit malloc` alone showed 42 MB dirty against 798 MB reclaimable. macOS keeps
`MADV_FREE`'d pages resident until something actually needs them, so RSS
overstates by ~3.5×. jetsam gates on `phys_footprint`, not RSS.

So `serve-forever.sh` was killing a healthy server every few minutes over memory
it was not using, and each kill drops every `/api/events` stream — which is
precisely what the phone reports as "host disconnected".

### Fix

`scripts/serve-forever.sh` now samples `phys_footprint` via `/usr/bin/footprint -p`
(`mem_mb_of`, ~43 ms per sample), falling back to `ps -o rss` if `footprint` is
absent so a live child is never mistaken for a dead one. The 2026-08-07 runaway
protection is intact — that leak was dirty memory, which `phys_footprint` counts.

Verified before deploying: parser exercised against `B`/`KB`/`MB`/`GB` inputs and
a fractional `3.50 GB`; live pid → 1025 MB (vs 3310 MB RSS); `launchd` → 2 MB;
dead pid → empty; fallback path (with `footprint` renamed away) → returns the RSS
value; `bash -n` clean.

Supervisor restarted 13:38:31 (pid 25825, reparented to launchd, survived the
launching shell). Steady state now **833 MB footprint against a 4096 MB ceiling**,
~5× headroom, where the old gauge read 2730 MB.

**Cost of the deploy:** ~30 s of downtime. The relaunch used `setsid`, which does
not exist on macOS, so the kill succeeded and the restart silently did not. Plain
`nohup` worked. Logged in the session improvement log.

### Soak result — PASS

240 samples at 30 s over **2 h 01 m**, a single process throughout (pid 25837,
started 13:38:31 — one distinct pid in the whole series), **zero ceiling kills**.
That is ~4.7× the worst pre-fix lifetime (26 min), against a pre-fix pattern of
five kills in the preceding hour.

```
footprint  min 709 MB   max 1841 MB   avg 1071 MB   ceiling 4096 MB
```

Peak was 45% of the ceiling, and the average never trended upward across two
hours — this is a steady state, not a slower leak. **Honest caveat:** peak `ps` RSS during this window
was 3348 MB — under 4096, so this window would also have survived on the *old*
gauge. The soak therefore proves the allocation fixes were sufficient here; it
does **not** independently prove the gauge change was necessary. The gauge change
stands on its own evidence (RSS 3326 MB vs phys_footprint 906 MB with 2471 MB
reclaimable, and GC reclaiming the heap entirely without moving RSS) — it is
correct because RSS was measuring the wrong thing, not because this soak needed
it. What it buys is headroom: 41% of ceiling instead of ~82%.

If the ceiling is ever hit again on the *new* gauge, the next thing to bound is
`listResumable({limit: 30})`, still 642 MB peak (`scratchpad/bench-resumable.ts`),
driven by `enrichCandidate` → `lastUserText`.
