# Sends must survive an unreadable composer

Date: 2026-08-04. Symptom reported: "messages are not sent for sessions that are
idle, even when hosts are connected" and "resending / interrupting / follow-up
messages are not sent stably."

## What is actually broken

`deliver()` already treats the **transcript** as the authority for *submission*
(`sendq.ts:752-780`) — it does not require a composer re-match after Enter, and
it handles an unreadable composer (`held === null`) as "the draft left the box."
That half is correct and is not the bug.

The bug is one step earlier, in *insertion* confirmation (`sendq.ts:721-735`):

```ts
let settled = false;
for (let i = 0; i < 20; i++) {
  await sleep(150);
  if (composerHoldsInput(target, needle) === true) { settled = true; break; }
}
if (!settled) { tmuxClearInput(target); await sleep(200); continue; }
```

`composerHoldsInput` (`sendq.ts:445`) is tri-state:

| Return | Meaning |
|---|---|
| `true` | composer parsed, holds our draft |
| `false` | composer parsed, does **not** hold our draft |
| `null` | composer could not be parsed / is not on screen |

The loop only accepts `true`. So whenever the composer is **unreadable**, the
send never settles → `tmuxClearInput` → retry → 3 attempts → `failed: message
never left the input box after retries` — **while the keystrokes were landing
correctly the whole time.** This is the same class of failure as the `(Branch)
──` border bug, and it will recur on every future TUI shape the parser doesn't
know.

`null` is not hypothetical: the send-path diagnosis recorded a live pane
returning `null` because it was showing a scrolled output view with no composer.

## Fix

Distinguish "the composer says our text isn't there" from "we cannot read the
composer." Only the first is evidence of failure.

- `true` → settled, submit (unchanged)
- `false` → composer readable, draft absent → genuine insertion failure → clear
  and retry (unchanged)
- `null` → **cannot tell.** Fall through to Enter unconfirmed and let the
  existing transcript / composer-cleared authority decide.

Guard on the `null` path: if a selector/overlay is open, an Enter would pick an
option rather than submit a message, so `null` + selector-open still retries.

Keystrokes reach the pane whether or not lfg can parse the render, so pressing
Enter on an unreadable composer is exactly what a human does. If the text truly
never landed, the transcript will not grow and the composer-clear check will not
fire — the attempt loop then retries as it does today. The change removes a
false negative; it does not remove a real check.

## Success criteria

- SC1 — `insertionOutcome` returns `settled` for `true`, `retry` for `false`,
  `unconfirmed` for `null` with no selector, `retry` for `null` with a selector.
- SC2 — `bun test` passes with new coverage for all four cases.
- SC3 — a real send to a live tmux session still reaches `delivered`.
- SC4 — a real send to a session whose composer parses as `null` reaches
  `delivered`/`queued` instead of `failed`. (Verified against a live pane if one
  presents that shape; otherwise recorded as unverified-live.)

## Files

- `src/sendq.ts` — `insertionOutcome` (new, pure, exported); insertion loop
  tracks its last observation and consults it.
- `src/sendq-insert.test.ts` — new.

## Verification — 2026-08-04

| SC | Result |
| -- | ------ |
| SC1 | **PASS** — all four cases asserted in `src/sendq-insert.test.ts`. |
| SC2 | **PASS** — `bun test` 174 pass / 0 fail across 25 files. |
| SC3 | **PASS** — real send, real seam. `POST /api/sessions/<id>/send` (the same endpoint the iOS client uses) to a live throwaway session reached `delivered` in **<3s**; `tmux capture-pane` shows `❯ Reply with exactly: ack` answered `⏺ ack`. |
| SC4 | **PARTIAL — branch proven on the real seam, full path not staged.** A real tmux pane with no composer returns `inputBoxText === null`, and `insertionOutcome(null, false)` returns `unconfirmed` where the old code retried 3× and failed. What was *not* staged is a live Claude session whose composer is unreadable *while a send is in flight* — all 5 live panes parsed cleanly at verification time (the `(Branch) ──` fixes are holding), so the shape could not be reproduced on demand. |

Deployed: server restarted 15:37:18 (pid 26167) against `sendq.ts` mtime
15:35:42, so the running process carries the change. `/api/ping` 200 in 19ms
after respawn.

### Residual risk

SC4's unstaged half means the `unconfirmed` path has been proven correct in
isolation and proven reachable in the wild, but not yet observed rescuing a real
send. The failure mode if it is wrong is bounded: an Enter on a pane that never
received the text, which the transcript probe declines to confirm, so the
attempt loop retries exactly as it does today. It cannot strand a send that the
old code would have delivered.
