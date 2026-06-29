# LFG — TestFlight setup

## Decisions
- **Bundle ID:** `com.eugenechan.lfg` (was `dev.omg.lfg`; `omg` was upstream's naming).
- **Team:** `39GJBP8V5A` (Eugene's own team — already used by Noto + most apps).
- **API key:** reuse Noto's account-level App Store Connect API key (account-scoped, works for all apps). Stored git-ignored in `ios/fastlane/.env.local`.
- **Mode:** Local Fastlane first (automatic signing, no match), then GitHub Actions + match later.
- **APNs:** entitlement made config-driven — `development` (Debug) / `production` (Release/archive) via `$(APS_ENVIRONMENT)`.

## Phase 1 — local upload (no match)
1. `project.yml`: bundle id → `com.eugenechan.lfg`; `aps-environment` → `$(APS_ENVIRONMENT)`; set `APS_ENVIRONMENT` per config. Regenerate via xcodegen.
2. `ios/Gemfile` (fastlane), `ios/fastlane/{Appfile,Matchfile,Fastfile}`, `ios/fastlane/.env.local`.
3. `.gitignore`: ignore fastlane env/build artifacts.
4. Register App ID + create App Store Connect app record (`fastlane produce`, with confirmation).
5. `bundle exec fastlane ios deploy_testflight` locally (automatic signing) → TestFlight.

## Phase 2 — CI (later)
- Create `match-lfg` private repo, `bootstrap_match`, GitHub Actions `testflight.yml`, secrets. Mirror Noto.

## How to ship a build (local)
```bash
cd ios
set -a; . fastlane/.env.local; set +a
bundle exec fastlane ios deploy_testflight
```
Build number is an auto HKT timestamp (YYYYMMDDHHMM); changelog defaults to the last git commit message. Override with `BUILD_NUMBER=` / `TESTFLIGHT_CHANGELOG=`.

## Signing model (local)
- No match. `sigh` creates/installs the **`com.eugenechan.lfg AppStore`** profile via the API key; manual signing with the existing **Apple Distribution** cert in the keychain.
- App ID `com.eugenechan.lfg` has **Push Notifications** + In-App Purchase capabilities.
- Release entitlement `aps-environment=production` (Debug=development) via `$(APS_ENVIRONMENT)`.
- `ITSAppUsesNonExemptEncryption=false` baked into Info.plist (standard HTTPS only).

## Known follow-ups
- ASC app name registered as "Lfg iOS Client" (Apple title-cased "LFG"); rename in App Store Connect if desired.
- Ruby 3.2.7 — fastlane wants 3.3+ soon; bump rbenv eventually.

## Status
- [x] Phase 1 files (Gemfile, fastlane/{Appfile,Matchfile,Fastfile}, .env.local, .gitignore)
- [x] App ID registered + push capability enabled
- [x] App Store Connect record created (id 6785393158)
- [x] First build uploaded to TestFlight (build 202606291446, distributed to Internal testers) ✅
- [x] Real app icon (full-bleed 1024, derived from the supplied mark; build 202606291520) ✅
- [x] Launch screen (LaunchScreen.storyboard: #080808 bg + centered mark; verified on sim; build 202606291620) ✅
- [ ] Phase 2 CI (GitHub Actions + match-lfg repo)
