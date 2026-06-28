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

## Notes / follow-ups

- `ios/` is untracked — worth committing so device/simulator builds don't silently diverge again.
- Temporary diagnostic logging was added to `src/commands/serve.ts` `/api/file` during investigation and **reverted** (the remaining diff in that file is pre-existing work).
