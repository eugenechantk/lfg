# Improvement Log — Session ff4c4e3c

> Earlier entries from this session (outbox terminality, POST-boundary enforcement,
> the host-restore mistake) were folded into `consolidated-2026-08-23.md` by another
> session. This file continues from there.

## Tracker

- [ ] 2026-08-23 — Shipped a change that pegged the main thread at 100% and froze the app; my first three screenshots looked like "the server isn't delivering" and I nearly debugged the wrong subsystem
- [ ] 2026-08-23 — The send-time scroll had been dead code since the inversion rewrite (`scrollTo("BOTTOM")` against a deleted sentinel) and nothing caught it — a scroll to a non-existent id fails silently

## Log

### 2026-08-23 — A hang that looked exactly like a backend stall

**What happened:** Making "send jumps to the newest message" work, I called
`jumpToNewest()` synchronously from the composer's send hand-off. That animated scroll
drives `onScrollGeometryChange`, which writes `isAtBottom`, which invalidates the body,
which rebuilds `NewestEndTracker` — and because it all happened inside one view update,
the graph never got a runloop turn to settle. Main thread at 100%, app frozen.

**Why it was nearly misdiagnosed:** the symptoms were "pending spinner never resolves"
and "transcript never updates" while the *server* clearly had both the turn and the
reply. That reads as a live-delivery problem. I went as far as leaving and re-entering
the session to force a refresh before checking the process itself. `ps` showed 100% CPU
and `sample` put `NewestEndTracker.body` in the loop — one command that would have saved
three screenshots and a wrong hypothesis.

**What better looks like:** when a UI stops updating, check whether the process is *alive*
before theorising about what feeds it — `ps -eo pcpu` then `sample <pid>`. A frozen client
and a silent server look identical in a screenshot, and only one of them is my code.
Second lesson, SwiftUI-specific: **never drive a scroll synchronously from inside a view
update** — hop a turn (`Task { @MainActor in … }`). The existing double-tap caller was
safe only because a gesture callback already runs between updates, so the same function
was fine at one call site and fatal at another.

### 2026-08-23 — A silently dead scroll target survived the inversion rewrite

**What happened:** Eugene reported that sending doesn't take him to his new message. The
cause was that the send handler called `scrollProxy.scrollTo("BOTTOM", anchor: .bottom)`
— and `"BOTTOM"` was a sentinel the inverted-list rewrite (my own work, earlier this
session) deleted. `ScrollViewProxy.scrollTo` on an unknown id does nothing and reports
nothing, so the send path had been scrolling nowhere for as long as the new architecture
has existed, with a comment above it confidently describing behaviour that no longer
happened.

**Why it survived:** the rewrite's verification measured *programmatic scroll writes
during scrolling* (target: zero) and open-at-newest. Both passed. Neither exercised
"send while scrolled up", so a writer that had become a no-op looked exactly like the
intended "nothing scrolls" property.

**What better looks like:** when deleting a sentinel/anchor id, grep for the string, not
just the symbol — `"BOTTOM"` was a literal in a different file region and no compiler
error could catch it. And when a rewrite's success criterion is "fewer things happen",
add at least one criterion of the form "this specific thing still happens", or dead code
reads as success.
