# Desktop session phone continuation

## Problem

LFG already indexes Codex and Claude Code transcripts, but it treats ChatGPT
Desktop's active Codex rollout as closed because the owning `codex app-server`
process is intentionally excluded from the live session list. That makes the
phone offer an unsafe exact resume while another writer still owns the thread.
Unmanaged live Claude Code sessions have a related ambiguity: they can be read,
but LFG cannot drive their non-tmux frontend.

## User flow

1. Start or continue a Codex session in ChatGPT Desktop, or a Claude Code
   session outside LFG.
2. Open LFG on iPhone and find that session in the normal session list.
3. Open it and read the transcript while the desktop frontend still owns it.
4. Tap **Continue in LFG** to create an LFG-owned branch from the latest flushed
   turn and open that branch on the phone.
5. If the desktop frontend has released the session, send normally; LFG resumes
   the original transcript using the existing exact-resume path.

## Success criteria

- [x] An active ChatGPT Desktop Codex rollout appears as live in LFG rather than
      as a closed/resumable duplicate.
- [x] Its transcript is readable from the iPhone client while Desktop owns it.
- [x] The API identifies live sessions that are externally owned and therefore
      cannot accept direct LFG messages.
- [x] The detail screen explains external ownership and offers **Continue in
      LFG**.
- [x] Continuing creates a new LFG-owned branch and navigates to it without
      interrupting or taking over the desktop-owned source.
- [x] Sending directly to an externally owned session is prevented with a clear
      error; it never starts a second writer on the same thread.
- [x] Released desktop-originated transcripts remain in the session list and
      use the existing exact-resume-on-send behavior.
- [x] Claude Code sessions running outside LFG receive the same externally-owned
      treatment when they have no controllable LFG tmux pane.
- [x] Existing LFG-managed session send, resume, fork, and list behavior remains
      covered and passing.

## Technical approach

- Treat writable rollout descriptors held by `codex app-server` as authoritative
  live ownership, but continue suppressing bare app-server phantom rows.
- Add a backward-compatible `control` field to live session payloads:
  `direct` for directly controllable panes, `external` for read-only desktop-owned
  frontends.
- Carry a best-effort `source` label (`chatgpt-desktop`, `claude-desktop`,
  `terminal`, or `lfg`) for product copy and diagnostics.
- Keep exact resume unchanged for sessions with no live owner. For `external`
  rows, expose a branch action through the existing fork API.

## Decision log

- **2026-09-26 — Branch instead of forced takeover while active.** The ChatGPT
  Desktop app-server holds both a writable rollout descriptor and Codex's thread
  writer lock. Killing it or starting a second writer risks interruption or
  corruption. A fork is immediate, safe, and preserves lineage; exact resume is
  reserved for after the owner releases the thread.
- **2026-09-26 — Normal list, not a separate imports screen.** Desktop-started
  conversations are sessions, and separating them would recreate the app silo
  LFG is meant to remove.
- **2026-09-26 — Read-only is ownership, not provider.** The same UI/API state
  applies to Codex Desktop and unmanaged Claude Code sessions, which keeps the
  client behavior composable.

## Verification evidence

- `bun test` targeted ownership, app-server fork, fork-history, bootstrap, and
  existing fork coverage: 24 passed, 0 failed; `bunx tsc --noEmit` passed.
- FlowDeck built the LFG scheme successfully on isolated simulator
  `E5E192B8-5419-4F67-B8DE-1BD1B4D06480`.
- The Swift test targets cannot currently be executed through FlowDeck because
  the checked-in LFG and LFGCore schemes have no configured test action. The app
  build compiled the changed model, client, and SwiftUI files.
- Against an isolated host on `127.0.0.1:8971`, the source remained live and
  externally owned, transcript reads succeeded, direct send/resume returned
  HTTP 409, and fork returned a distinct lineage-preserving session id.
- Simulator evidence verified the complete phone flow: desktop session visible,
  live transcript readable, explanatory **Continue in LFG** surface, navigation
  to a directly controlled branch, inherited desktop history rendered, and a
  writable composer present. Production port `8766` was not restarted.
- Independent visual audit: PASS. Evidence includes screenshots, accessibility
  trees, a 60-second transition recording, and post-flow API snapshots in
  `.codex/evidence/20260926-212736-ios-visual-audit/`.
