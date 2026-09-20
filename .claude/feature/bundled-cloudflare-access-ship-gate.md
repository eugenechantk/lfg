# Bundled Cloudflare Access: make every TestFlight build carry Pro + Air

**Date:** 2026-09-20 · **Tier:** product · **Status:** deploying (evidence below)

## Ask

Bundle the Pro and Air Cloudflare tunnel URLs and the Access service token into
the iOS app so a fresh install never needs the host/credential setup form again.

## Finding: the feature already exists; the gap is what ships

| Layer | State on 2026-09-20 |
| --- | --- |
| `LFGCore/BundledCloudflareAccess.swift` | parses `{hostURLs, clientID, clientSecret}`, additive host seeding (commit 6f6d9f5, 1dd7add, Aug 20–21) |
| `LFGApp.swift` init | reads `PrivateResources/BundledCloudflareAccess.private.json` from the bundle every launch, saves the credential to Keychain for every host, appends missing hosts |
| `ios/PrivateResources/BundledCloudflareAccess.private.json` (gitignored) | present on the Pro; lists `lfg-pro` **and** `lfg-air`; token returns 200 on both hosts, 403 without |
| `ios/scripts/generate-bundled-cloudflare-access` | regenerates it from the macOS Keychain pilot item |
| IPA from deploy 202609191931 | payload present (262 B) |
| xcarchive 2026-09-19 20:02 (build 202609192001) | `PrivateResources/` holds **only README.md** — payload dropped |

Build 202609192001 was archived from a tree that lacked the gitignored file (a
clean worktree; three of the current worktrees have README-only PrivateResources).
The lane happily archived, the phone got a build with no bundled hosts, and the
setup form came back. Nothing in the deploy or verify lanes checked for the file.

## Change

1. **`ios/fastlane/Fastfile` — `ensure_bundled_cloudflare_access!`** runs in
   `deploy_testflight` after `regenerate_project`, before signing/archive. Missing
   payload → runs the generator; still missing or malformed (no hosts, empty
   id/secret) → `user_error!`. Escape hatch for an intentional public build:
   `ALLOW_UNBUNDLED_CLOUDFLARE_ACCESS=true`.
2. **`verify_testflight_build` DoD 1b** — the local IPA must contain the payload
   and its host list must equal the local payload's. A clean-worktree archive can
   no longer pass the definition of done without the hosts.
3. **Generator fallback** — when the Keychain pilot item is absent (the Air has
   `~/.cloudflared/lfg-access-service-token.private.json` but no Keychain item),
   read the desktop app's private file, which has the same JSON shape.

Desktop app: not affected. It reads the token from the Mac Keychain or the
`~/.cloudflared` file at runtime; nothing is bundled.

## Success criteria

- [ ] Deploy from a clean worktree (README-only PrivateResources) generates the payload and archives.
- [ ] Shipped IPA contains `PrivateResources/BundledCloudflareAccess.private.json` listing both hosts.
- [ ] `verify_testflight_build build_number:<n>` passes including DoD 1b.
- [ ] Generator fallback path produces the same two-host payload (verified: bogus Keychain service → fallback file → identical hosts/id).

## Behaviour on existing installs

The seed is additive and runs every launch: an install that already has manual
hosts keeps them, gets the bundled credential re-saved for the same origins, and
gains whichever of Pro/Air is missing. No reinstall needed; the next TestFlight
update is enough.

## Evidence

(appended after the deploy)

### 2026-09-20 12:37 deploy (worktree `.worktrees/testflight-bundled-access`, HEAD 08de5d5)

- Gate fired: payload missing → generated → "hosts: lfg-pro, lfg-air" (log lines 27–33).
- Archive + export OK at 12:39. IPA `build/fastlane/LFG.ipa` (8.1 MB) contains
  `PrivateResources/BundledCloudflareAccess.private.json` with both hosts; CFBundleVersion 202609201237, v1.3.0.
- **Upload failed:** altool ran 13 min, sent >260 MB, 1584 × "WILL RETRY PART 1. Checksums do not match", then
  "Process crashed", exit -1. Route to 17.156.106.13 (Apple upload) was via utun4 (26.26.26.1, a VPN tunnel) while
  the default route was the en0 hotspot; previous uploads over en0 took 75–90 s. Killed at 12:52. Re-upload pending
  with the VPN off/bypassed: `bundle exec fastlane ios upload_only` is not a lane yet — use `pilot upload` on the existing IPA.
