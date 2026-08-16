# Improvement Log — Session 20260816-on-the-go-disconnect

## Tracker

- [ ] 2026-08-16 — Wrote a `kill $(lsof -ti :8766)` that expanded to three PIDs and died on a malformed pid list
- [ ] 2026-08-16 — Misread elapsed uptime as "30 minutes stable" without ever checking `date`
- [ ] 2026-08-16 — First streaming rewrite was slower AND hungrier than the code it replaced; caught only because I benchmarked
- [ ] 2026-08-16 — A written, tested fix sat undeployed for 20 minutes while the host kept dying
- [ ] 2026-08-16 — Spent the whole session optimizing allocations before checking whether the ceiling measured real memory
- [ ] 2026-08-16 — Used `setsid` on macOS in the relaunch of an always-on service; it doesn't exist, and the host was down ~30s
- [ ] 2026-08-16 — Declared the host restart loop "the answer" without checking it against the symptom's own frequency; Eugene had to correct me twice
- [ ] 2026-08-16 — Read the client log twice and missed the absent keepalives; only found it after reading the policy file's comments

## Log

### 2026-08-16 — `kill $(lsof -ti :8766)` matched clients, not the listener

**What happened:** The project CLAUDE.md rule is "kill by PORT (`lsof -ti :8766`), not by pkill pattern." I
followed it literally. `lsof -ti :8766` returns every process with a socket on that port — which included
the two *client* processes (`lfg` CLI and the `LFG` desktop app) holding established connections. The
result was a three-line PID string, `kill` rejected it as an illegal pid, and `ps -p` errored too.

**Why this was wrong:** Nothing broke, but only by luck — had the list been valid, I would have killed
Eugene's desktop app and CLI alongside the server. The rule needs the LISTEN filter to mean what it says.

**What better looks like:** `lsof -nP -iTCP:8766 -sTCP:LISTEN -t`. The `-sTCP:LISTEN` is the part that
makes "kill by port" safe. Worth amending the project CLAUDE.md line, which currently shows the unsafe form.

### 2026-08-16 — Misread elapsed uptime as evidence of stability

**What happened:** I read `ps` output showing the serve process started at 13:20:22, assumed the current
time was ~13:31, and concluded "11 minutes in and stable — before the fix it died every 6-25 min." I
repeated the same error a second time and told myself it had been up 30 minutes. The actual clock was
13:26. The process had been alive six minutes, which proves nothing against a failure whose observed
interval was 6-25 minutes.

**Why this was wrong:** I inferred wall-clock time from the timestamps in my own earlier tool output rather
than reading it. A soak test whose duration you guessed is not a soak test. I nearly reported a fix as
verified on the strength of it.

**What better looks like:** Any claim of the form "it has been stable for N minutes" requires `date` in the
same command as the `ps`. Print both, subtract, never estimate. And a soak window must exceed the *upper*
bound of the observed failure interval, not the lower one.

### 2026-08-16 — The obvious streaming rewrite made both metrics worse

**What happened:** To stop `messagePage` materializing a 511 MB transcript as one string, I wrote the
textbook streaming reader: `carry += decoder.decode(chunk, {stream: true})`, then scan `carry` for
newlines. Benchmarked: **3413 MB peak / 2790 ms**, against the whole-file version's **1987 MB / 843 ms**.
Strictly worse. The rewrite that actually worked carries *bytes* in a `Uint8Array[]` and decodes each
complete line once: **1013 MB / 273 ms**.

**Why this was wrong:** Rows in these rollouts average ~137 KB and Bun streams 256 KB chunks, so `carry`
is long and re-flattened by `indexOf` on every chunk — quadratic in the length of a record. "Streaming
must use less memory than reading the whole file" is an intuition, not a fact.

**What better looks like:** I did do the right thing — I had a benchmark harness from the previous fix and
reran it before deploying, which is the only reason this was caught. Generalize it: any change justified by
a resource claim gets the before number and the after number from the same harness, on production-sized
data, *before* it ships. A passing test suite says nothing about peak RSS.

### 2026-08-16 — Tested fix sat undeployed while the host kept crashing

**What happened:** A prior session diagnosed the `scanBack` blowup correctly, wrote the fix, and left it
uncommitted and undeployed at 13:03. Bun has no hot-reload, so the running server kept the old code and
was killed at the 4 GB ceiling twice more (13:00 and 13:20) before I restarted it.

**Why this was wrong:** From Eugene's phone this is indistinguishable from "nobody fixed it." The diagnosis
was the hard part and it was already done; the remaining step was one restart.

**What better looks like:** In this repo, "fixed" means the *running* process has the code. The existing
CLAUDE.md check — compare `ps -eo pid,lstart` against `stat -f %Sm src/<file>.ts` — should run at the *end*
of a fix, not only when re-debugging a recurrence.

### 2026-08-16 — Optimized three allocators before questioning the measurement

**What happened:** I took "lfg serve at 4379MB >= 4096MB" at face value and spent the session making the
server allocate less: three real fixes, all measured, all deployed. Only when Eugene asked "is it possible
to not kill lfg but just clean up" did I check what the ceiling was actually measuring. `ps` RSS said
3326 MB; `phys_footprint` said 906 MB, with 2471 MB sitting in the *reclaimable* column. Forcing
`Bun.gc(true)` took heapUsed from 695 MB to 4.7 MB while RSS did not move a single megabyte. The server was
never using 4 GB. It was being killed every few minutes over pages the allocator had already freed.

**Why this was wrong:** The supervisor's own log line was the premise of the entire investigation and I
never audited it. This is [[disconfirm-before-declaring-root-cause]] applied one level too shallow — I
disconfirmed hypotheses *about why memory was high* and never asked whether memory was high. Everything I
built on top was true and useful, but it was treating a symptom of a broken gauge.

**What better looks like:** When a threshold alarm is the evidence, validate the gauge before optimizing
against it — one `footprint -p <pid>` next to the `ps -o rss` would have reframed the whole session in
40 ms. On macOS specifically, RSS is not a memory-pressure signal: it counts MADV_FREE'd pages until the
kernel actually wants them. `phys_footprint` is what jetsam uses and what any ceiling should gate on.

**Also worth noting:** Eugene's question was the intervention. "Can we clean up instead of killing" is a
question about the *mechanism*, and answering it honestly required measuring the mechanism. I should
generate that question myself when I'm about to accept a restart loop as normal.

### 2026-08-16 — `setsid` on macOS took the host down for ~30 seconds

**What happened:** To install the supervisor change I killed the 9-day-old `serve-forever.sh` (pid 44362,
orphaned to launchd, nothing auto-restarts it) and relaunched with
`setsid nohup bash scripts/serve-forever.sh &`. macOS has no `setsid`. The command failed, so nothing
restarted, and `lfg serve` was simply gone until I noticed in the next `ps` and relaunched with plain
`nohup`.

**Why this was wrong:** I killed a service with no supervisor above it using a relaunch command I had never
run on this platform. The relaunch is the risky half of that operation and it got no verification at all,
while I had carefully unit-tested the shell function that was merely *read* by the script.

**What better looks like:** When killing something nothing will restart, prove the relaunch command works
*before* the kill — run it against a harmless target, or at minimum `command -v` every binary in it. Same
class of error as shipping generated code unexecuted, which the global CLAUDE.md already forbids; the rule
should read as covering recovery commands too. Linux-isms to check on macOS: `setsid`, `timeout` (needs
coreutils), `free`, `/proc`, `pgrep -a`, `stat -c`.

### 2026-08-16 — Answered "why does it disconnect" without checking my answer against the symptom

**What happened:** I found the host restarting every 6–25 minutes, measured it thoroughly, fixed it, and
presented it as the answer. Eugene: "the disconnection is not every 6-25 mins it is more frequent
especially when I am on cellular network." The restart loop was real but could not explain either the
frequency or the cellular correlation. I had never checked my explanation against the *shape* of what he
reported — only against the evidence I happened to be looking at.

**Why this was wrong:** A cause has to match the symptom's frequency, timing, and conditions, not merely
exist. "The host restarts sometimes and that breaks streams" is true and was never sufficient. Worse, the
cellular correlation was in his original message — "especially when I am on cellular" — and I treated it as
colour rather than as the discriminating fact it was. Compare [[verify-the-discriminating-case]]: I should
have asked what the restart theory predicts on Wi-Fi (identical drops) and noticed that contradicts the
report.

**What better looks like:** Before presenting a root cause, write the symptom's parameters down — how
often, under what conditions, since when — and check the candidate cause reproduces all of them. If it
explains three of four, it's a contributing cause, and say so in those words rather than calling it the
answer.

### 2026-08-16 — Read the smoking gun twice without seeing it

**What happened:** The decisive evidence was *absence* — zero successful `KAL rtt=…` lines in 65 seconds of
client log. I read that log carefully twice, built a whole timeline of stream lifetimes from it, and did not
notice the missing keepalives. I only found the bug after reading `HostEvents.swift`, where the comment on
`keepaliveInterval` explains that its purpose is keeping the carrier-NAT binding warm against a ~30s expiry.
That sent me back to count KAL lines, and there were two, both failures.

**Why this was wrong:** I was reading the log for events that happened, and the bug was an event that
didn't. Nothing in my scan was designed to notice a gap. I also had the cadence written down —
`keepaliveInterval = 10` — and 65 seconds of log; the arithmetic (expect ~6, found 2) was available the
whole time and I never did it.

**What better looks like:** For any periodic mechanism in a log, count the occurrences and compare against
the documented period *before* interpreting anything else. Absence is evidence, but only if you go looking
for it. Concretely: list the recurring line types, note each one's expected cadence, and flag every one
that's under-represented.

### 2026-08-16 — Shipped a fix whose mechanism was right and whose theory was wrong

**What happened:** I found a real bug (`HostLink.keepalive()` gated on `.catchingUp/.live`, so the
NAT-warming ping went silent whenever the link was struggling), built a causal story around it
(binding expires at ~30s → Tailscale re-punch → black-hole → cannot reconnect → keepalive stays
silent), fixed it, and shipped it to TestFlight. The behavioural change is confirmed live: keepalives
now fire for a host that is never `.live`, at a strict 10s cadence. **And the disconnects continued
exactly as before.** The theory was refuted by its own prediction.

**Why this was wrong:** I had a disconfirming datum in hand and did not use it. The same log I
diagnosed from contained successful `KAL rtt=115ms` lines at 11:34 — keepalives working fine on the
OLD build — and long healthy streams (55s, 85s, 137s) interleaved with the bad periods. If a silent
keepalive were the cause, those good periods could not exist on the same binary. I anchored on the
65-second window at 13:48 where keepalives were absent, and read absence as cause when it was a
*symptom* of the same outage that killed the streams. `keepalive()` only fires when the stream is
alive, so a dead transport produces missing keepalives automatically — the correlation was
guaranteed, not evidence.

**What better looks like:** Before accepting a mechanism, find the periods in the same data where the
mechanism was NOT in play and check the symptom tracked it. Here: "were there stretches with healthy
keepalives on the old build, and were they free of drops?" Both answers were in the log and both
refuted me. This is [[verify-the-discriminating-case]] — what would the old build have shown in this
exact window? — applied to evidence I already had rather than to a test I still had to run.

**Also:** the fix introduced a regression I flagged only after shipping. The dead Air host now gets a
keepalive every 10s forever on top of its 18s stream dials, on a link that is already marginal.
"Ping in every started state" is correct; "ping a host unreachable for six hours, indefinitely" is
not. I should have paired the gate change with the dead-host backoff in the same change, since I had
already identified it.

### 2026-08-16 — Ran the whole session without checking the cheapest cross-layer probe

**What happened:** `tailscale ping <phone>` from the Mac takes 2 seconds, bypasses lfg entirely, and
answers "is this lfg's problem at all?" definitively. I ran it once, late, got a healthy direct 99ms
reply, and used it to argue the path was fine. I did not run it again during a failure. When I finally
did (17:24), it timed out 5/5 — proving the outage sits below anything lfg controls.

**Why this was wrong:** A single sample of a flapping link tells you about that instant only. I built
a case on one favourable reading and never sampled during the state I was trying to explain.

**What better looks like:** For any intermittent fault, sample the ground-truth probe during BOTH
states, and prefer the probe that excludes the most layers. The memory [[tailscale-ping-is-ground-truth]]
already says `tailscale ping` doesn't lie — what it needed was "and sample it while it's broken."

### 2026-08-16 — Fixed the regression I shipped, in the change that should have carried it

**What happened:** The keepalive gate fix (Attempt 7) made a dead host *more* expensive: the Air, off all
day, went from silent to a ping every 10s on top of its 18s stream dials. I identified that as a needed
follow-up in the same message where I reported the fix, then shipped without it. Eugene's next log showed
exactly the predicted waste.

**Why this was wrong:** I knew the downside before the build went out. "Ping in every started state" is
correct for a host that might answer and wrong for one that has been unreachable for hours; the
qualifying condition was part of the design, not a later refinement. Splitting it across two TestFlight
builds meant a real regression reached the device.

**What better looks like:** When I catch a downside of a change while writing it up, that is a signal the
change is incomplete, not that I have a good backlog item. Ship the qualifier with the thing it qualifies.

**The fix, for the record:** `coldAfter = 120s` with no contact of any kind (stream byte OR keepalive
pong) marks a host cold. Cold hosts ping once a minute instead of once every 10s, and no longer have their
backoff ladder reset by `resumeNow(foreground)` — which is what had pinned the Air at attempt 1 through
dozens of foregrounds. The threshold is asserted in tests to sit clear of the widest stale watchdog (40s)
and the top of the reconnect ladder (30s), so a merely-struggling host never trips it, and cold hosts keep
retrying at the 30s cap rather than stalling.
