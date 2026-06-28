# Improvement Log Digest — 2026-06-29

**Logs processed:** 19 (14 empty templates, 5 substantive)
**Date range:** 2026-06-18 → 2026-06-29
**Observations found:** 11 (10 unaddressed at consolidation time)

## Patterns (recurring across 2+ sessions)

### P1 — "Verified" from isolated/mocked evidence, not the real seam
- **Frequency:** 2 sessions (2026-06-28 ×2: UI md-card, APNs)
- **Summary:** Work marked verified on sub-component proof (regex mirror + curl + clean build) or a passing mock suite (26 green APNs tests) while the actual deliverable failed. UI fix never tapped the card; APNs `fetch()` couldn't parse HTTP/2 — only a live send caught `Malformed_HTTP_Response` (fix: `node:http2`).
- **Root cause:** Validating easy-to-test parts while the load-bearing seam (real UI gesture / real wire transport) stays unexercised, then letting green isolated evidence imply whole-system coverage.
- **Current coverage:** Partial — `verify-ui-by-tapping.md` covers the UI variant; the wire-protocol/external-service variant had no memory.
- **Fix:** New memory [[verify-real-seam-not-mocks]]. Balanced with O4 (don't over-verify pure-logic bugs).

### P2 — Hypothesizing before obtaining ground truth
- **Frequency:** 2 sessions (2026-06-26 /proc enumeration, 2026-06-28 ios 404)
- **Summary:** ~30 min brute-forcing a missing UI state before reading `src/sessions.ts` (enriches via `/proc/<pid>/cwd`, Linux-only). Separately, traced code + offered ATS/network hypotheses before a screenshot revealed a plain 404.
- **Root cause:** Treating unexplained behavior as interaction/timing and iterating, instead of reading source or demanding the literal error first.
- **Fix:** New memory [[ground-truth-before-hypothesizing]].

### P3 — lfg architecture hazards (single-process Bun + macOS + multi-session)
- **Frequency:** 2 sessions (2026-06-26 PTY hung server, 2026-06-28 concurrent edit collision)
- **Summary:** Terminal-tab PTY websocket saturated the single Bun event loop (HTTP stalled 20s+, restart lost in-memory CLI tracking). A concurrent lfg session edited `SessionStore.swift` mid-task → "file modified since read" + build break.
- **Root cause:** lfg's premise (many concurrent sessions on one single-process box) + macOS (no `/proc`) undocumented; each session rediscovers the hazards.
- **Fix:** New project CLAUDE.md.

## One-Off Observations

- **O1 — Swift/iOS SSE & UI-automation gotchas** (YES persist): `AsyncBytes.lines` drops SSE blank lines; `\r\n` is one grapheme so `firstIndex(of:"\n")` misses CRLF (split on `unicodeScalars`); driving SwiftUI text fields for URLs is unreliable — write the app's plist in the sim data container + relaunch. → project CLAUDE.md.
- **O2 — `ios/` untracked → stale-build "works on sim, broken on device"** (YES): iPhone 404 was a stale installed build. → commit `ios/`; rule: device-only iOS bug → first ask "did the device get the latest build?".
- **O3 — flowdeck stale destination id / wrong flag** (marginal, already resolved): cached destination id gone; guessed `--destination` (correct: `-S`). Governed by flowdeck skill.
- **O4 — Redundant sim scroll-hunt after a logic fix was unit-proven** (YES, counterbalance to P1): when a bug is pure logic and the failing input is reproduced exactly, the unit test IS the verification.

## Already Addressed
- [x] flowdeck stale destination id (`idle-msg`) — resolved in-session (check `--help`/list sims first).
- [x] UI-verify-by-gesture — persisted as `verify-ui-by-tapping.md`.

## Recommended Actions
| # | Action | Mechanism | Location | Priority |
|---|--------|-----------|----------|----------|
| 1 | lfg architecture + iOS/Swift gotchas + ios stale-build rule | Project CLAUDE.md | `lfg/.claude/CLAUDE.md` | HIGH ✅ |
| 2 | Real-seam verification memory | Memory | `…/memory/` | HIGH ✅ |
| 3 | Ground-truth-first memory | Memory | `…/memory/` | HIGH ✅ |
| 4 | Commit `ios/` | Git | `lfg/ios/` | MED (this cleanup) |
| 5 | Sharpen global anti-pattern wording | Global CLAUDE.md | `~/.claude/CLAUDE.md` | LOW (skipped) |
| 6 | Delete empty template logs | Cleanup | `lfg/improvement-log/` | LOW ✅ |

## Logs Archived
All 19 `improvement-log-*.md` deleted after capture; this digest is the permanent record.
