# lfg iOS/iPadOS MVP — Verification Report

Rebuilt the native app from scratch against the
[Live-sessions feature doc](./ios-mvp-live-sessions-feature-doc.md), including the
§8 macOS host-enablement backend patch. Verified live on this Mac (server on
`127.0.0.1:8766`, iPhone 17 + iPad Pro M5 simulators reaching it directly).

## What was built
- **Backend patch** — `src/procinfo.ts` (new) Darwin-gated process-introspection
  shim; `src/sessions.ts` + `src/tmux.ts` refactored to use it. CLI claude/codex
  sessions now enumerate on macOS and emit `prompt` events. Linux path unchanged.
- **`ios/LFGCore`** (SPM) — `Models`, `SSEParser`, `LFGClient` covering every Live
  endpoint + the live SSE stream. **15 unit tests, all green** (`swift test`).
- **`ios/LFG`** (SwiftUI) — full Live UI: connection/settings, grouped list,
  transcript, create/resume, steering, prompt panel, paused banner, iPad
  rail+stage. Built clean via FlowDeck (XcodeGen project).

## Feature parity checklist — verified

| Feature | Status | Evidence |
|---|---|---|
| Connection / host setup + reachability test | ✅ | "✓ Reachable" on `http://127.0.0.1:8766`, Save → list |
| Reachability banner (host unreachable) | ✅ | Banner shown on iPad before host fixed |
| Session list grouped by state (Needs you / Paused / Working / Idle) | ✅ | "IDLE 10", then "NEEDS YOU 1" + "PAUSED 1" after driving |
| Session card (agent icon, model badge, owner, status dot, relative time) | ✅ | List screenshot — opus/sonnet/gpt-5.5 badges, eugene@…, "1h ago" |
| **CLI agents enumerate on macOS** (the §8 patch) | ✅ | `claude` (opus) CLI sessions visible in-app; server `/api/sessions` shows them |
| Live transcript stream (SSE) — markdown, thinking, tool lines, Actions footer | ✅ | Auth-audit + post-answer transcripts rendered live |
| **Interactive prompt panel — render + tappable options** | ✅ | "Where should I deploy?" Staging/Production rows |
| **Answer a prompt** | ✅ | Tapped Staging → pane: "Where should I deploy? → Staging"; transcript advanced; panel cleared |
| Create session (agent/model/repo/owner pickers + resume list) | ✅ | New-session sheet; all 5 agents in picker; started a Claude (CLI) session |
| Resume a recent session | ✅ | Resume list populated in sheet |
| Paused banner + "Resume on Opus" | ✅ | `claude-fable-5` unavailable → banner + Resume-on-Opus button |
| Session menu (model switch / rename / assign / stop / end) | ✅ | ⋯ menu implemented; model options per agent |
| User filter (All / Unassigned / per-user) | ✅ | "All" filter in toolbar |
| Light/dark | ✅ | System-adaptive (semantic colors) |
| **iPad rail + stage** | ✅ | NavigationSplitView: rail (grouped list) + stage (transcript + composer) side by side |

## Bugs found & fixed during verification
1. **SSE blank-line swallowing (critical).** `URLSession.AsyncBytes.lines` drops
   empty lines, but SSE uses the blank line as the event-dispatch boundary — so
   no events ever dispatched. Fixed by splitting the raw byte stream on `\n`
   ourselves and feeding `SSEParser` (`LFGClient.liveStream`).
2. **CRLF grapheme split.** `firstIndex(of: "\n")` never matches `\r\n` (one
   grapheme cluster in Swift). Fixed `SSEParser.feed` to split on Unicode scalars.
3. **macOS pidfile time mismatch** (backend patch). claude writes `procStart` in
   UTC; macOS `ps -o lstart=` prints local time — naive compare rejected every
   pidfile. Fixed with epoch-ms compare + tolerance in `procinfo.procStartMatches`.

## Known runtime conditions (not app bugs)
- **Model availability:** `claude-fable-5` (and transiently `opus`) returned
  model-unavailable on this account, which surfaced the paused banner. Use a
  known-available model (sonnet) for a clean run.
- **Prompt option indices are 1-based** (server contract). The app answers with
  the option's own `index` field, so this is handled.

## How to run again
```bash
# backend (host)
cd /Users/eugenechan/dev/personal/lfg && bun run serve     # :8766

# app — simulators (the saved iPhone 17 config sim was deleted; dedicated sims made):
#   iPhone:  9E92114B-…   iPad: D4C3A63B-…
flowdeck build -S <udid> && flowdeck run -S <udid>
# in-app: set host to http://127.0.0.1:8766 (simulator shares the Mac's loopback)
# over Tailscale from a real device: set host to the Mac's MagicDNS https URL
cd ios/LFGCore && swift test                                # core unit tests
```

## Follow-ups (not blocking)
- Transcript renders natively from structured fields (markdown inline); tables
  render as text. Migrate to richer rendering or the server `html` if needed.
- Batch macOS `ps`/`lsof` calls in `procinfo` if session counts grow large.
- The FlowDeck config still points at the deleted `iPhone 17` sim — update it to
  one of the dedicated sims if you want bare `flowdeck build`/`run`.
