# Diagnosis — a session stuck at "running" forever

**Reported:** 2026-08-04, session `cy-163217-77946` (`c5d4a5a2-1368-4e94-94b2-96a3460d9804`)
**Symptom:** the iOS client showed the session as running indefinitely; queued
messages sat `pending` and never landed.

## Ground truth

| Signal | Value |
| --- | --- |
| `GET /api/sessions` → `busy` | `true` |
| Pane tail | `✻ Churned for 3m 54s` (past tense, no live clock) → **turn finished** |
| `lastActivityAt` | 7.5 min stale (`REST_BUSY_WINDOW_MS` is 12 s → `transcriptRecent` = false) |
| `delegated` | false |
| Composer | held unsent text; one queue item `pending`, `attempts: 0` |

`busy` is `delegated || (paneBusy ?? transcriptRecent)`, so the only input that
could be `true` was `paneBusy`.

## Cause

`isBusy(pane)` tested its two markers against the **entire captured pane**:

```ts
BUSY_METER.test(pane) || /esc to interrupt/i.test(pane)
```

`BUSY_METER` correctly read false (the turn was over). The `esc to interrupt`
fallback matched — on **line 46 of the pane, inside the agent's own answer**:

> A session that is still live but hung — pane alive, still showing
> **esc to interrupt** — stays busy: true legitimately…

The session had been asked about lfg's busy detection, wrote the phrase, and
pinned itself busy for as long as that text stayed on screen. `paneBusy` has a
10 s TTL but the pump refreshed it to `true` every tick, so it never expired,
and it overrides the transcript-age fallback. Downstream, `sendq` holds messages
for a busy session — hence the stranded `pending` item.

This is a self-referential bug class: **any** session that prints a busy marker
pins itself busy. In this repo, which discusses its own busy detection, that is
routine rather than exotic. The meter has the same exposure — an agent quoting
`(5m 50s · ↓ 2.2k tokens)` would have matched too.

## Fix

Both markers are TUI chrome and only ever render in a fixed region around the
composer box. Anchor the scan to that region instead of the whole pane:

```
✶ Crunching… (5m 50s · ↓ 2.2k tokens)          ← meter: ≤6 lines ABOVE the top border
  ⎿  Tip: …                                     ← optional interstitials
               Update available! …              ┘
────────────────────────────────────            ← composer top border
❯ typed text
────────────────────────────────────            ← composer bottom border
  ⏵⏵ bypass permissions … · esc to interrupt …  ← hint: strictly BELOW the border
```

- `esc to interrupt` → searched only **below** the composer's bottom border.
  Transcript prose can never reach the footer.
- `BUSY_METER` → searched only in the 6 lines **above** the top border, *and*
  anchored to end-of-line (`[)…]\s*$`). The region alone was not enough: a quoted
  meter can land inside the window, but it carries trailing prose, whereas the
  real meter closes the line on its paren (or a truncation ellipsis).
- Border **runs** are collapsed the same way `inputBoxFromPane` collapses them —
  a border drawn wider than the pane wraps into two consecutive rule lines.
- No border at all (a codex `›` prompt, or a mid-render capture) → fall back to
  the pane **tail**, never the scrollback.

`src/tmux.ts` — `busyChromeRegions()` + `isBusy()`; 7 regression tests in
`src/tmux-busy.test.ts`.

## Verification

Ran old vs new `isBusy` over all 12 live panes. Exactly one verdict changed:

```
   cy-151451-2768:0.0    old=true  new=true     ← genuinely running
>> cy-163217-77946:0.0   old=true  new=false    ← the bug
   lfg-8206bb:0.0        old=true  new=true     ← genuinely running
   lfg-b7fee2:0.0        old=true  new=true     ← genuinely running
   (8 others            old=false new=false)
```

206/206 bun tests, `tsc --noEmit` clean.

## Not the cause

Session `c5d4a5a2` independently diagnosed the same symptom as the journal pump
dropping vanished sessions without retracting `busy` (fixed in `journal-pump.ts`
as `appendDisappearanceRetractions`). That is a real defect and worth keeping —
but it does not explain this instance: the session never vanished, it was live
and enumerated the whole time. Two distinct causes behind one symptom.

## Deploy note

`serve` is long-lived with no hot reload — the fix is inert until the process is
restarted. Restarting also deploys `c5d4a5a2`'s uncommitted pump changes and
drops in-memory session tracking for the ~8 live sessions.
