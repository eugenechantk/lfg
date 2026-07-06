# iOS file-open 404 — diagnosis & fix

**Date:** 2026-06-28
**Reported:** "On the ios/ipados client, there is still issue with opening any file sent by the agent." Every file shows **"Can't load file — Host returned 404. The file may have moved or sit outside the served folders."**

## Root cause

**The iPhone is running a stale build of the app.** The current on-disk iOS code resolves and opens files correctly; the binary installed on the iPhone has older path-resolution logic that produces a wrong absolute path, which the host's `/api/file` endpoint rejects with 404.

### How we got there

1. The error is a **404 from the host**, not a network failure (confirmed from the screenshot).
2. `/api/file` on the running Mac serve (`:8766`) was tested directly with `curl` for the exact file in the screenshot — returns **200** for both the absolute path and the relative path. So the **server is correct**.
3. The iPhone's `baseURL` points at **this Mac** (`100.120.101.14:8766`) — the same serve the simulator uses. So the server sees identical requests from both clients; the difference must be **client-side**.
4. The entire `ios/` directory is **untracked in git** — builds are ad-hoc, so the iPhone's installed binary can lag the on-disk source.
5. Built the **current** code to the **simulator** (same Mac serve) and tapped files:
   - `lfg_promptpanel2.png` (absolute path) → **opened** (QuickLook image).
   - `README.md` (relative path, resolved against session `cwd`) → **opened** (markdown).
   - Both path types resolve correctly in the current code.

Conclusion: current code is correct; the iPhone simply has an older build.

### Relevant current code (correct)

- `ios/LFG/RichContent.swift` — `HostFiles.resolve(rawPath:)` → `absolutePath()` joins the session `cwd` for relative paths, then `fileURL(forPath:)` builds `GET /api/file?path=…`.
- `ios/LFG/SessionDetailView.swift:41` — injects `session.cwd` into the `hostFiles` environment so relative paths resolve. (A stale build lacking/differing this logic explains the 404.)

## The fix

Reinstall the **current** build on the iPhone. No code change required.

### Blocker: device signing

Local device build fails on provisioning:

> Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the Push Notifications capability / `aps-environment` entitlement (target 'LFG').

The app declares `aps-environment: development` (`ios/LFG/LFG.entitlements`). The automatic profile for `dev.omg.lfg` doesn't carry Push. Simulator builds skip this; device builds don't. `flowdeck project sync-profiles` also fails — the App ID needs its Push capability registered via Xcode/the developer portal.

### Options to get the build onto the iPhone

- **A — Xcode local run (fastest to verify on-device):** open `ios/LFG.xcodeproj`, select the iPhone ("Hihi", network), Run. Xcode's automatic signing registers Push on the App ID and provisions. Confirms the fix immediately.
- **B — Ship via release CI/TestFlight (matches normal update path):** the phone is normally updated via `.github/workflows/release.yml`. Commit the `ios/` changes and run the release; install the new TestFlight build.
- **C — (not recommended) strip the `aps-environment` entitlement** to force a local flowdeck device install. Disables push and diverges from real config.

## Update 2026-07-01 — codex-specific recurrence (different root cause)

**Reported:** "still this issue of files not able to be opened … 404 for codex sessions." This time scoped to **codex** sessions while Claude sessions work on the same installed build — so it is a real code difference, not the stale-build cause above.

### Root cause
Codex (`--yolo`) writes screenshots/scratch media to **`/tmp/*.png`** and **`$TMPDIR` (`/var/folders/.../T/*.jpg`)** and presents those absolute paths in its messages. The iOS `MediaScanner.bareRef` regex matches them cleanly (no spaces), so a file card renders — but `/api/file` only allowed `$TMPDIR/lfg-uploads` under the temp dirs, so tapping returned 403/404. Claude Code avoids this because the global `~/.claude/CLAUDE.md` instructs it to write outputs into cwd/home and emit served absolute paths; codex has no such instruction.

Evidence: 29 distinct `/tmp` + `/var/folders/.../T` media paths across recent codex transcripts (e.g. `/tmp/screenshot.png`, `/tmp/superslide-*.png`, `/var/folders/.../T/screenshot_optimized_*.jpg`). Live-endpoint test confirmed each 403/404 before the fix.

### Fix
`src/commands/serve.ts` `/api/file` root set broadened from `[REPOS_ROOT, SELF_REPO, $TMPDIR/lfg-uploads, homedir()]` to also include `tmpdir()` ($TMPDIR), `/tmp`, and `/private/tmp`. `homedir()` was already a fully-served root, so this is strictly *less* exposure than what was already allowed — not a posture change. Requires a `serve` restart to take effect (Bun has no hot-reload).

Verified against the live restarted server: `/tmp`, `/private/tmp`, `$TMPDIR` media → 200; `/etc/hosts` → 403; `/tmpfoo/evil.png` prefix-escape → 404 (the `r + "/"` boundary holds).

### Known remaining gap (separate, not the 404)
`MediaScanner.bareRef` (`/[^\s)]+`) stops at whitespace, so codex paths **containing spaces** (e.g. `…/Japan Ski Trip/vlog.mp4`) are not detected → no card renders at all. That is a non-detection bug, distinct from this 404. Follow-up if spaced-path media needs to render.

## Update 2026-07-01 (b) — video "sent but not viewable" = missing HTTP Range support

**Reported:** a Claude session (tmux `lfg-ff449f`, AutoClipping) sent `…/improvement-log/demo_flow.mp4`; it rendered but wouldn't play in the iOS client. **Different bug from the 404s above.**

### Root cause
`/api/file` answered AVPlayer's `Range: bytes=0-1` probe with **`200 OK` + the whole file** (no `Content-Range`, no `Accept-Ranges`). iOS AVFoundation requires **`206 Partial Content`** to progressively stream remote video; given a 200-with-everything it renders a dead/blank player. Images were unaffected because `AsyncImage` just downloads the whole file. File itself was fine (exists, H.264/yuv420p mp4, served 200).

### Fix
`src/commands/serve.ts` `/api/file`: added byte-range handling — parses `Range: bytes=start-end | start- | -suffix`, returns `206` with `Content-Range`/`Content-Length` for partials, `416` for unsatisfiable, and `Accept-Ranges: bytes` on the full `200`. Requires a `serve` restart.

Verified at HTTP level (curl): `bytes=0-1`→206, `bytes=1000000-`→206 clamped, `bytes=-500`→206 suffix, `bytes=9999999-`→416, no-range→200+Accept-Ranges. **Visually verified** in the simulator: opened the AutoClipping session, the `demo_flow.mp4` AVPlayer rendered and advanced frames on tap (evidence: `ios/design/video-verify-1.png`, `video-verify-2.png`).

## Notes / follow-ups

- `ios/` is untracked — worth committing so device/simulator builds don't silently diverge again.
- Temporary diagnostic logging was added to `src/commands/serve.ts` `/api/file` during investigation and **reverted** (the remaining diff in that file is pre-existing work).
