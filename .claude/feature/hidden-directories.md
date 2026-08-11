# Hidden directories — a per-device mute list for the iOS session list

**Tier:** product (shipping TestFlight app)
**Date:** 2026-08-11
**Ask:** "Filter out all the gbrain sessions from my iOS client so they don't show
— there are too many when autopilot is running and consolidating my vault. And set
it up as a primitive so I can decide what other sessions to filter out."

## The population being hidden

`gbrain` autopilot sessions run in `~/.gbrain` — they are indistinguishable from
real work by agent, model, or title, but they share one stable property: their
working directory. Two are live right now; during a vault consolidation there are
many more, and each one is a card in the list.

```
claude | /Users/eugenechan/.gbrain | Users-eugenechan--gbrain | is whatsapp via hermes ...
claude | /Users/eugenechan/.gbrain | Users-eugenechan--gbrain | Can we remove the Noto cli ...
```

So the primitive is **hide by working directory**, as Eugene called it: a list of
directory paths; any session whose `cwd` is at or under one of them is not shown.
`~/.gbrain` is then just the first entry in a list he controls.

### What live testing changed: paths alone are not enough

Running the client against the real host surfaced a **second** gbrain population,
and it is the one the complaint is actually about — autopilot works out of a fresh
temp directory per run:

```
/private/var/folders/cd/_rd32xx…/T/gbrain-claude-cli-cwd-24267   ← 24267 is a pid
```

A literal mute list would have muted exactly one run and been stale by the next,
so the primitive takes **patterns** as well as paths: an entry containing `*` or
`?` is globbed against the `cwd` and its ancestors. `*/gbrain-claude-cli-cwd-*`
mutes the whole family, across TMPDIRs and pids, forever. Still "filter by
directory" — just a directory *shape* rather than one literal instance.

Because a per-run path is a bad thing to hide literally, `suggestedPattern`
recognizes the shape (a last path component ending in `-<digits>`/`.<digits>`) and
the swipe offers a second, explicitly-labelled action — "Hide all like this" — that
adds the pattern instead. Narrow on purpose: a wrong generalization hides real work.

## Why client-side, not server-side

- It is a **viewing preference**, not a fact about the session. The desktop app,
  the CLI and `lfg-sessions` should keep seeing everything.
- Directory hiding must span hosts. A server only knows its own sessions; the
  client already merges every host's list and holds each session's `cwd`.
- No server deploy, no protocol change. (`serve` restarts drop in-memory session
  tracking — see `.claude/CLAUDE.md`; avoiding one is a real win.)

The cost of this choice: **it cannot suppress push notifications**, which are
decided by `runPushTick` on the host. See "Out of scope" below.

## Design

### The primitive — `LFGCore.HiddenDirs`

A pure, `Sendable` value wrapping a normalized path list. Lives in `LFGCore` with
unit tests, per the iOS convention that non-UI logic is reasonable-about without
Apple's runtime.

```
HiddenDirs(["/Users/eugenechan/.gbrain"])
  .hides(cwd: "/Users/eugenechan/.gbrain")         → true   (exact)
  .hides(cwd: "/Users/eugenechan/.gbrain/vault")   → true   (descendant)
  .hides(cwd: "/Users/eugenechan/.gbrainstorm")    → false  (segment boundary)
  .hides(cwd: nil)                                 → false  (unattributable)
```

Rules, each of which is a test:

- **Normalize on the way in:** trim whitespace, collapse repeated and trailing
  slashes. Drop entries that aren't absolute — the client cannot expand `~`
  against a host's home directory, so a `~/...` entry would silently match
  nothing and read as a bug. Reject empty.
- **Match on path-segment boundaries**, never raw `hasPrefix` — `.gbrain` must
  not swallow `.gbrainstorm`.
- **Case-insensitive**, because the hosts are macOS (case-insensitive FS) and a
  path typed with the wrong case silently matching nothing is a worse failure
  than over-matching.
- **A session with no `cwd` is never hidden.** Hiding is an assertion about a
  directory; with no directory there is no assertion to make.
- **Empty list hides nothing** — the feature is inert until used.
- `adding`/`removing` are idempotent and order-stable, so the Settings editor and
  the row swipe can't produce duplicates.

### Where it applies

Hiding is a **list** concern, not a reachability concern. Applied at:

| Surface | Why |
| --- | --- |
| `SessionStore.filteredSessions` | the list, `grouped()`, `unreadCount` all derive from it |
| `SessionStore.runningCount` | the top-bar count must match the list it sits above (it reads unfiltered `sessions` today, so this also fixes an existing inconsistency with `unreadCount`) |
| `rebuildSearchResults` | server-side search spans *every* transcript on every host, so without this a hidden directory reappears the moment you type |
| `FleetActivityController` snapshot | otherwise the Live Activity counts sessions the list doesn't show — the exact class of parallel-ladder bug `.claude/CLAUDE.md` warns about |

Deliberately **not** applied at:

- `SessionStore.session(_:)` — a push or deep link into a hidden session must
  still open. You muted a directory in the list; you didn't make it unreachable.
- The new-session directory picker. Hiding `~/.gbrain` from the list is not a
  declaration that you'll never start a session there by hand.

### Affordances

1. **Row swipe → "Hide"** in the session list. Hides that session's directory,
   which is how a mute list should be built: from the thing annoying you, in one
   gesture, with no path typing.
2. **Settings → "Hidden directories"**: the current list (swipe to unhide) plus a
   picker of every directory the client has actually seen, so `~/.gbrain` is a
   tap rather than a typed path. Plus a manual path field for directories no
   session has surfaced yet.
3. **A visible count, so it is never a silent black hole.** A header chip
   (`eye.slash` + count) sits beside the filter and gear buttons; its menu unhides
   any muted directory in one tap. A filter you forgot you set is a bug report
   waiting to happen.

   Two things were wrong on the first live pass and are worth keeping fixed:
   - It started as a **footer** at the bottom of the list. The list is long and
     paginated — a disclosure under the closed section is one nobody scrolls to.
   - It counted **all** hidden sessions, which read "63 hidden" against a handful
     of live agents and *climbed as the closed list paginated*. It now counts the
     live population only, the same one "N running" describes.

## Success criteria — verified

Live against the real host (iPhone 17 Pro sim, `flowdeck`), evidence in
`.claude/evidence/20260811-hidden-directories/`.

| # | Criterion | Result |
| --- | --- | --- |
| 1 | No `~/.gbrain` session in the list — live, closed, or search | ✅ list clean; searching "gbrain" returns only sessions that *mention* it from other directories |
| 2 | Every other directory unaffected | ✅ lfg / inbox / reelly / fiftyworkout untouched |
| 3 | A prefix-sharing sibling (`.gbrainstorm`) is not hidden | ✅ unit-tested (no live sibling exists to drive) |
| 4 | Top-bar count agrees with the visible list | ✅ "2 running" / Working 2 |
| 5 | Hiding survives relaunch | ✅ persisted across a full reinstall + relaunch |
| 6 | Unhiding restores immediately, no relaunch | ✅ chip menu → `.gbrain` rows back, Unread 17→19, chip 4→2 |
| 7 | A notification deep-link into a hidden session still opens | ⚠️ **not live-verified** — structurally guaranteed (`session(_:)` is unfiltered), but driving a real push was out of scope |
| 8 | The count discloses what is hidden | ✅ chip read 4, then 3, matching `/api/sessions` exactly as an autopilot session ended |
| 9 | Tests green | ✅ 283 XCTest + 43 swift-testing, 33 of them `HiddenDirsTests` |

The autopilot temp-dir pattern was exercised end-to-end: swipe → "Hide all like
this" → `*/gbrain-claude-cli-cwd-*` stored → the live temp-dir session disappeared
from the list and from the "directories in use" picker.

## Out of scope (flagged, not silently dropped)

- **Push notifications from hidden directories still arrive.** The decision is
  made by `runPushTick` on the host, so a client-side mute list cannot see it.
  Fixing it means either a server-side per-device mute list (`/api/push/…`
  registration carrying hidden paths) or a `UNNotificationServiceExtension` that
  drops payloads whose `cwd` matches. Worth doing if autopilot turns out to push;
  a separate change either way.
- **Desktop app.** Same primitive would port, but the ask was the iOS client.
