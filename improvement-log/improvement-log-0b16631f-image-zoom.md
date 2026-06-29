# Improvement Log — Session 0b16631f (image zoom + file-open diagnosis)

## Tracker

- [ ] 2026-06-28 — Hypothesized the file-open 404 cause for several turns before getting the literal screenshot
- [ ] 2026-06-28 — `ios/` was untracked, letting the iPhone build silently diverge from on-disk source (stale-build bug class)
- [ ] 2026-06-29 — `/api/sessions` takes ~7s and intermittently wedges → clients show "Host unreachable / request timed out"
- [ ] 2026-06-29 — FlowDeck synthetic `pinch` didn't drive UIScrollView zoom; `double-tap` did — verify zoom via double-tap or a real device

## Log

### 2026-06-29 — `/api/sessions` slow/wedged
**What happened:** While verifying the image-zoom change, the iOS app showed "Host unreachable / request timed out". `/` returned 200 in <1s but `/api/sessions` took ~7s (and one worker fully wedged until killed; serve-forever respawned it).
**Why it matters:** ~7s exceeds the client's request timeout, so the app reads as offline even though the host is up. With ~35 sessions, `listSessions()` does per-session transcript/tmux/process work — likely O(n) expensive calls. This degrades every client, not just the simulator.
**What better looks like:** Profile `listSessions()`; cache/parallelize per-session lookups or paginate. Separate task from the image feature.

### 2026-06-29 — FlowDeck pinch vs double-tap for zoom verification
**What happened:** Implemented a `UIScrollView`-backed `ZoomableImageView`. `flowdeck ui simulator pinch in/out` reported success but the screenshot never changed. `double-tap` correctly zoomed in (2.5x, centered on tap) and toggled back to fit-width.
**Why it matters:** Synthetic pinch on the simulator is unreliable for driving `UIScrollView`'s native pinch recognizer; relying on it would have falsely read as "zoom broken."
**What better looks like:** To verify pinch-zoom, use `double-tap` as the deterministic proxy (or test on a real device). Don't conclude zoom is broken from a no-op synthetic pinch.
