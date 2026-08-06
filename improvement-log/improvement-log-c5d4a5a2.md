# Improvement Log — Session c5d4a5a2-1368-4e94-94b2-96a3460d9804

## Tracker

- [ ] 2026-08-04 — Asked how to implement "unread" before questioning whether it belonged at all
- [ ] 2026-08-04 — `flowdeck ui simulator screen --output <relative>` reported success but wrote nothing
- [ ] 2026-08-04 — Burned ~4 turns tapping a SwiftUI send button by coordinate; sheet a11y tree was empty
- [x] 2026-08-04 — Memory `live-activity-lockscreen-height-budget` was stale (said cap at 2 rows; 3 now fit) — memory updated
- [ ] 2026-08-04 — Shipped a bug: re-derived session classification instead of mirroring `group(for:)`, so closed sessions showed as "running" forever

## Log

### 2026-08-04 — Asked how to implement "unread" before questioning whether it belonged

**What happened:** Eugene's first message asked for a card showing "working, needs input and
unread". I mapped the data model, found that unread is per-device client state the server
cannot see, and asked a well-formed 3-option question about how to keep it accurate while the
phone is locked. He answered "client-only", then immediately followed with "no more unread
sessions — they're not active anyway", which made the whole question moot.

**Why this was wrong:** I had the evidence in hand *before* asking. `SessionStore.group` returns
`.unread` only after the `.needsInput` / `.blocked` / `.working` checks all fail — i.e. unread is
by construction a property of *idle* sessions. I read that code, quoted it in my own analysis,
and still didn't connect it to "so it doesn't belong on an ACTIVE card." I optimised the
question's framing instead of challenging its premise.

**What better looks like:** When a request contains a category that the data model says is
mutually exclusive with the request's own framing, raise that first — one line, before asking
any implementation question. "Unread only ever applies to idle sessions, so it can't appear on
an 'active' card — do you want it anyway?" would have skipped a wasted question and a wasted
option-design pass. Challenge the premise before optimising the solution.

### 2026-08-04 — `flowdeck ui simulator screen --output <relative>` silently wrote nothing

**What happened:** Ran `flowdeck ui simulator screen -S <udid> --output ios/design/.../x.png`.
The command printed its normal success block (`Elements: 11`, `Size: 402x874`) and exited 0. The
file did not exist at that path — the next command failed with `FileNotFoundError`. Re-running
with `"$PWD/ios/design/.../x.png"` worked.

**Why this was wrong:** I treated a success message as proof of the artifact. The relative path
resolved against something other than my shell's cwd (FlowDeck resolves against its own project
root), so the screenshot landed somewhere unseen. Nothing in the output hinted at the real
destination.

**What better looks like:** Always pass an **absolute** path to `--output`. More generally: when
a tool's job is to *produce a file*, the success signal is `ls` on the file, not the tool's exit
message. Cheap to check, and it turns a silent misfire into an immediate one.

### 2026-08-04 — Tapped a SwiftUI send button by coordinate four times before checking the tree

**What happened:** In the new-session sheet, I tapped the send arrow at coordinates read off a
screenshot. It "succeeded" (`✓ Tapped at (357, 807)`) but nothing sent. I retried the same
coordinate, then re-typed, then retried again — three wasted round-trips — before reading the
accessibility tree, which turned out to contain exactly one element (the `Application` root):
the sheet's contents were not exposed at all.

**Why this was wrong:** Two compounding errors. (1) The first tap's coordinates came from a
screenshot taken *before* the text wrapped to two lines, which moved the button — I verified the
tap fired, but never verified the *effect*, which is the rule in the FlowDeck skill. (2) When it
failed I repeated the same failing action instead of switching to the tree, which would have
told me in one call that coordinates were the only option available and why.

**What better looks like:** After any tap that should change state, read the screenshot and
confirm the *state changed*, not just that the tap dispatched. On the second identical failure,
stop and read `latest-tree.json` before a third attempt. If the tree is empty/degraded, say so
and pick a non-UI path (here: the `/api/sessions/new` REST endpoint, which worked first try and
was what I should have reached for once the sheet proved opaque).

### 2026-08-04 — Memory `live-activity-lockscreen-height-budget` was stale and would have misled

**What happened:** The memory states the lock-screen card must be capped at "header + 2 rows +
overflow" because `header + 3 rows` center-clipped and dropped the header. Design frame 27 calls
for 3 rows + "N More". Taken literally the memory says the design is unbuildable.

**Why this mattered:** The memory recorded a *measurement of one specific layout* as a general
rule. The old fleet row carried a host pill, a divider and larger type; frame 27's row is a dot +
one line of 15px text. Measured from the design, the whole card is ~153pt against the ~160pt
frame — 3 rows fit. I built 3 rows and confirmed by screenshot that the header survives.

**What better looks like:** Memories that encode a numeric budget should record *what was
measured* alongside the conclusion, so a future layout can be re-measured rather than assumed
impossible. Updated the memory to state the real constraint (the ~160pt frame and the
center-clip failure mode) and to note that the row count depends on row height — with the
verified data point that frame 27's lean rows fit three.

### 2026-08-04 — Re-derived session classification instead of mirroring `group(for:)`

**What happened:** Eugene reported session `e64271a9` showing as "running" on the Live
Activity forever, despite being closed in the client. Cause: `FleetActivitySnapshot`
classified sessions with its own ladder — `prompts` → `busy` → skip — while the app's real
grouping, `SessionStore.group(for:)`, checks `closed` FIRST and `isBlocked` before `busy`.
Two states diverged. `closed` is client-synthesized and `busy` is only ever *seeded* for live
sessions and never cleared on close, so a session that was working when it ended kept
`busy == true` permanently → rendered as working forever. Paused (`isBlocked`) sessions had
the same problem in a milder form.

**Why this was wrong:** I had `group(for:)` open in this very session — I quoted its
precedence when reasoning about unread, and I *still* wrote a parallel classifier next to it
instead of mirroring it. Duplicating a state machine that already exists is a guaranteed
future divergence; here it diverged immediately, in the same session, on the branch I had
already read. The unit tests I wrote passed because I tested my ladder against itself: every
fixture used a live session, so the missing `closed` branch was invisible.

**What better looks like:**
- When a view derives from state a store already classifies, **reuse the classifier** or, if
  it can't be reached (here `group(for:)` lives in the app target and pulls in read-state that
  doesn't belong in LFGCore), mirror it *branch for branch* with a comment naming the function
  it mirrors and why the order matters. Both are now in place.
- Test the **precedence**, not just the happy path: for any classifier with an ordered ladder,
  write one fixture per branch that a *higher* branch must beat (closed+busy, closed+prompt,
  blocked+busy, blocked+prompt). All four now exist and all four would have caught this.
- Fixtures that only ever exercise the common case (live sessions) prove nothing about the
  guards. When a model has a flag like `closed`, at least one fixture must set it.
