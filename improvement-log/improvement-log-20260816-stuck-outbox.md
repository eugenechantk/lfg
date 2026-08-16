# Improvement Log — Session 20260816-stuck-outbox

## Tracker

- [x] 2026-08-16 — Read the trace log before reproducing: `~/.lfg/sendq.log` answered "why is this row stuck" in one grep
- [ ] 2026-08-16 — A "fix" verified only by unit tests + a clean simulator shipped with the real failure unreproduced
- [ ] 2026-08-16 — Nearly re-debugged already-fixed code because the fix was uncommitted and I couldn't tell what shipped
- [x] 2026-08-16 — Wrote down a risk in my own diagnosis, shipped without closing it, and it was the next bug report

## Log

### 2026-08-16 — sendq.log answered the question before any repro

**What happened:** Instead of reproducing "message stuck at the bottom" live, I grepped
`~/.lfg/sendq.log` for the session id. It showed 67 lines: six distinct queue items for one text,
32 `deliver-failed` with `"message never left the input box after retries"`, and the one copy that
finally delivered an hour later. That plus the transcript's user-turn positions (38–40 turns back)
was the whole root cause.
**Why this mattered:** The project CLAUDE.md already says to read this log before re-deriving a
"my message never arrived" report by live repro. It was right — the log is retained even though the
queue rows themselves are pruned.
**What better looks like:** Keep doing this. For any send/delivery report: `grep <sid> ~/.lfg/sendq.log`
is step one, before the API, before the simulator.

### 2026-08-16 — a fix verified only by unit tests + a clean simulator

**What happened:** The reconciliation fix from the previous session was correct, but its own feature
doc recorded the residual risk honestly: "A clean Simulator cannot reproduce the original device's
persisted outbox rows." So the actual failing scenario was never exercised, and the half of the bug
that lives in the *durable* outbox (rows resurrecting on every launch because nothing deletes them)
was never found.
**Why this was wrong:** A clean simulator can't reproduce persisted state — but the state is a
sqlite table, and seeding it directly is three lines of Python. The obstacle was treated as a limit
rather than a thing to work around.
**What better looks like:** When the failure lives in persisted state, seed the store directly
(terminate app → write sqlite → relaunch) and always seed a **control row** that must NOT resolve.
Removal-only evidence can't distinguish "reconciled correctly" from "removed everything".

### 2026-08-16 — uncommitted fixes make "is this already fixed?" unanswerable

**What happened:** The fix for the primary cause was written, working, and sitting uncommitted in the
tree across several sessions' worth of changes. Determining whether the user's phone had it required
grepping the archived build's dSYM for a symbol name (`clockSkewAllowance`).
**Why this is costly:** With a dirty tree, "does the shipped app have this?" cannot be answered from
git at all. dSYM archaeology worked, but it is a workaround for missing history.
**What better looks like:** After a fix is verified, commit it — the repo's own CLAUDE.md warns that
a recurring "previously-fixed" bug is usually a deploy gap. The same reasoning applies to the client:
uncommitted work makes every deploy-gap question expensive.

### 2026-08-16 — wrote the risk down, shipped anyway, it came back as the next report

**What happened:** Round 1's diagnosis contained the sentence *"If the fetch is slow, fails, or the
host is unreachable, they stay visible for the whole session"* and *"The text match is a mask, not a
resolution."* I shipped the outbox-delete fix and stopped. Eugene reported the same symptom on a
different session an hour later, and the cause was exactly that unclosed hole: `ensureHistory`
swallowed a failed transcript fetch with `try?`, leaving a partial transcript against which no
optimistic row can ever be proven landed — and nothing retried.

**Why this was wrong:** Identifying a failure mode in writing and shipping without closing it is
worse than not noticing it — the analysis was done, the fix was ten lines. It also cost a second
round trip through Eugene, who had to re-report a bug I had already characterised.

**What better looks like:** When a diagnosis names a second way the same symptom can occur, either
fix it in the same pass or state explicitly that it is deferred and why. Specifically for this
codebase: a `try?` on a fetch whose result the UI depends on is a defect — it converts a network
failure into a wrong screen with no log line. Grep for `try? await client.` before shipping client
changes.
