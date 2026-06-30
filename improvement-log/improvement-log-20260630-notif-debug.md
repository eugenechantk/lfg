# Improvement Log — Session 20260630-notif-debug

## Tracker

- [x] 2026-06-30 — Fixed spurious "Finished" push: `isBusy` misread thinking-mode meter as idle (needs server restart to deploy)

## Log

### 2026-06-30 — Spurious "Finished" notifications while a session is still running

**Root cause:** `isBusy()` in `src/tmux.ts` keyed its primary signal off the literal word "tokens" in the spinner meter (`BUSY_METER = /\(\d+m?\s?\d*s\b[^)]*\btokens?\b/i`). During **extended-thinking** phases the meter renders as `(5m 56s · still thinking with medium effort)` — no "tokens" word — so the meter didn't match. `isBusy` then fell back solely to the `esc to interrupt` footer hint, but that footer **rotates** through other hints mid-turn (`← for agents`, `PR #96`, tips). When a thinking phase coincided with the footer rotating away, `isBusy` returned **false while genuinely busy**, and `reduceTransition` fired a "finished" push — repeating every 10s dedupe window.

**Evidence:** Live-captured the AutoClipping redesign session (`cy-133325-65269`) mid-thinking showing `✶ Authoring design artboards… (5m 56s · still thinking with medium effort)`. Before/after: OLD `isBusy` = false (→ spurious finished), NEW = true.

**Fix:** Broadened `BUSY_METER` to match the stable live clock + middot — `/\((?:\d+h\s+)?(?:\d+m\s+)?\d+s\b[^)]*·/` — which is present in both the token form and the thinking form. Kept the `esc to interrupt` fallback for the first frame. Added `src/tmux-busy.test.ts` (8 cases incl. the thinking regression + a stray-`(3s)` false-positive guard). All tests pass; live 80-sample run shows 0 false-idle.

**Deploy note:** The push watcher runs inside the `bun run src/cli.ts serve` process (pid 58546). The fix requires a server restart to take effect; restart drops in-memory session tracking (project hazard) — left for Eugene to trigger.
