# Why "Needs input" sessions load their transcript slowly

**Date:** 2026-08-06 · **Host:** eugenes-macbook-pro-2 · **Status:** root-caused, not yet fixed

## Symptom

Opening a session in the **Needs input** group makes the transcript take a long time to
appear/settle. Sessions in **Running** or **Idle** open quickly.

## Not the cause (measured, ruled out)

The fetch path is *identical* for all three states, and it is fast.

- iOS makes exactly **one** transcript call on open: `GET /api/sessions/:id/messages?limit=5000&full=1`
  (`SessionDetailView.swift:121` → `SessionStore.swift:2060` → `LFGClient.swift:244`).
  No SSE-per-session, no polling, nothing gated on `prompt` / `busy` / `blocked`.
- `messagesResponseForSession` (`src/commands/serve.ts:597`) never reads session state — no
  `listSessions()`, no `pendingToolPrompt()`, no `capturePaneAsync()`, no lock. Its only branch is
  `forkPending`.
- Measured that endpoint against **all 50 live sessions** on this host:

  | | worst | median-ish |
  |---|---|---|
  | `?full=1&limit=5000` | **64 ms** / 1.57 MB | ~20 ms / 400 KB |
  | `?page=backward&limit=220` | 64 ms / 134 KB | — |
  | `?limit=30` (256 KB tail) | 2.4 ms | — |

  Largest transcript on the box is 55 MB and still answers in 59 ms. The server is not the
  bottleneck. `tmux capture-pane` measures 5 ms.

## Actual cause: a `prompt` event storm, ~every 1.7 s, for the whole time the session is parked

The journal pump re-scrapes every pane once a second and journals a `prompt` event whenever the
payload differs (`src/journal-pump.ts:369-371`, dedup via `PumpDeltas.promptChanged`,
`src/journal.ts:184` — signature is `JSON.stringify(prompt)`).

`PanePrompt.context` (`src/tmux.ts:647`) is scraped from the live pane — the assistant prose above
the selector. **That scrape is not stable across captures**, so the signature changes on almost
every tick and the dedup never holds.

Journal evidence, session `279d6650`, parked at one permission prompt:

```
seq    gap    payload
52920  —      404B  "Do you want to proceed?"
52924  0.8s   NULL
52928  1.0s   430B  "Do you want to proceed?"
52934  1.9s   404B
52935  3.4s   430B
52938  1.4s   404B
...  (28 events, steady 1.7s cadence, until the prompt was answered)
```

The only field that differs between the two variants:

```
context A: 'Running 1 shell command… ⎿  $ touch /tmp/permprobe.txt'
context B: "I'll run that command.\n\nRunning 1 shell command… ⎿  $ touch /tmp/permprobe.txt"
```

The `⏺ I'll run that command.` preamble line flickers in and out of `contextAbovePrompt`'s 8-line
search window as the TUI redraws, so the pump alternates between two payloads forever.

Sessions **not** at a prompt emit zero prompt events (verified: 44 prompt events in the last ~1000
journal events, 28 of them from that one parked session; every other session's inter-event gaps are
minutes to hours).

### What that does to the client

1. `SessionStore.apply(.prompt)` (`SessionStore.swift:1926`) does an unconditional
   `prompts[sid] = prompt` — no equality guard, so `@Observable` dirties on every event.
2. `AgentPrompt` is `Hashable` **including `context`** (`Models.swift:169-186`), so the flap counts
   as a real change.
3. `SessionDetailView.swift:240` — `.onChange(of: prompt) { withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) } }`.
4. That is an **animated `scrollTo` on a `LazyVStack` holding the whole transcript** (up to 5000
   markdown-rendered rows, from the 1.5 MB `full=1` fetch). Scrolling to the trailing anchor forces
   SwiftUI to resolve the intervening rows.

So: every 1.7 s, for as long as the session sits at the prompt, the detail view re-lays-out the
entire transcript with an animation — *on top of* the initial load, and it never stops. Running and
Idle sessions have no such repeating invalidation (a Running session's `msg` events are additive and
carry real new content; an Idle session gets nothing at all).

The `full=1&limit=5000` fetch is what makes the list heavy enough for this to hurt — it's the
amplifier, not the trigger.

## Fixes, cheapest first

1. **Exclude `context` from the pump's change signature** (`src/journal.ts:184`): dedup on
   `question` + `options` only; let a context-only change ride along on the next real event. Kills
   the storm at the source, one-line-ish. *(Recommended.)*
2. **Guard the client assignment**: `case .prompt(let sid, let p): guard prompts[sid] != p else { return }`
   (`SessionStore.swift:1926`). Defence in depth — stops any future server churn from repainting.
3. **Don't animate/scroll on a context-only prompt change** (`SessionDetailView.swift:240`), or drop
   `withAnimation` there.
4. **Stop fetching the full transcript on open.** `LFGClient.messagesBackward` (`?page=backward`) is
   already implemented and **never called**. 220 messages = 134 KB vs 1.5 MB, and a far smaller
   `LazyVStack`. This is the general open-latency win for *all* states.
5. Optionally stabilise `contextAbovePrompt` (`src/tmux.ts:659+`) so the scrape stops flickering —
   the real bug, but the hardest to make robust against TUI redraws.

## Outcome — fixes 1 & 2 implemented 2026-08-06

- `src/journal.ts` — `promptChanged` now compares question+options exactly and `context` loosely:
  a context-only change is journaled **once** when it strictly grows (so the assistant preamble
  still reaches the client), and never again when it flaps back.
- `ios/LFG/SessionStore.swift` — `apply(.prompt)` is equality-guarded, so a repeat prompt event
  costs an open session nothing.

**Verification.** Replayed the *actual* captured payload sequence for `279d6650` (pulled live from
`/api/events/page`) through the fixed `PumpDeltas`:

```
events journaled BEFORE fix (what actually shipped): 28
events journaled AFTER  fix:                          5
```

All 23 suppressed events were pure `context` flap. The 5 survivors are genuine assertions.

Also: 3 new unit tests in `src/journal.test.ts` (flap suppression, selection-change still emits,
suppressed context doesn't poison the baseline). Full suite green — 354 server tests, 11 LFGCore
tests, `flowdeck build` clean.

### Known remaining flap (NOT covered by these fixes)

Two of the 5 survivors are a transient `prompt → null → prompt` round-trip: the pane scraper
momentarily failed to find the selector, so the session dropped out of "Needs input" for ~1.8s and
came back. That is a second, independent flap — same class of bug, different field. Fixing it needs
hysteresis in the pump (require N consecutive null scrapes before retracting a live prompt), which
trades ~1 tick of latency on a *legitimate* prompt clear. Worth doing if the group still flickers.

## Method note

Ruled the server out by measuring, not by reading: timed the real endpoint against every live
session, then read the journal (`/api/events/page`) to find what actually differs between session
states. The journal is the right ground truth for "what does the client receive" questions.
