# Improvement Log — Session 20260729-tap-timestamp

## Tracker

- [ ] 2026-07-29 — Burned ~6 minutes swipe-hunting for a transcript position; `flowdeck ui simulator scroll --until` reported success without scrolling

## Log

### 2026-07-29 — `scroll --until` returns success without scrolling (SwiftUI ScrollView)

**What happened:** To verify consecutive user-bubble spacing I needed a specific spot in a long transcript. `flowdeck ui simulator scroll --direction UP/DOWN --until "<label>"` returned `"success": true` every time but the screen never moved — it appears to match the element in the accessibility tree even when it is off-screen, then stop. I then over/undershot repeatedly with blind swipes and burned several screenshot round-trips.

**Why this was wrong:** I trusted the tool's success flag instead of verifying the screen changed, and I checked with expensive image reads rather than cheap text.

**What better looks like:** For "scroll to a known label in a long SwiftUI list", skip `--until`. Loop `swipe` + `grep` the session's `latest-tree.json` for the label (text, cheap, no image read), break when found, then pull frames from the tree. That loop found the target in 3 swipes. Also: the a11y tree's `frame.y` values are the precise way to verify spacing changes (measured 20pt gap vs 30pt before) — better evidence than eyeballing a screenshot.
