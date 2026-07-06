# LFG — TestFlight setup

## Decisions
- **Bundle ID:** `com.eugenechan.lfg` (was `dev.omg.lfg`; `omg` was upstream's naming).
- **Team:** `39GJBP8V5A` (Eugene's own team — already used by Noto + most apps).
- **API key:** reuse Noto's account-level App Store Connect API key (account-scoped, works for all apps). Stored git-ignored in `ios/fastlane/.env.local`.
- **Mode:** **Local-only.** `bundle exec fastlane ios deploy_testflight` on Eugene's machine. **No GitHub CI** — deliberately. (An earlier plan mirrored Noto's `testflight.yml`; dropped by decision 2026-07-01.)
- **Signing:** **match** (Noto's pattern), assets in a dedicated private repo `github.com/eugenechantk/match-lfg`. Reuses Noto's `MATCH_PASSWORD`; separate repo keeps lfg's cert/profile isolated.
- **APNs:** entitlement made config-driven — `development` (Debug) / `production` (Release/archive) via `$(APS_ENVIRONMENT)`.

## Setup (done)
1. `project.yml`: bundle id → `com.eugenechan.lfg`; `aps-environment` → `$(APS_ENVIRONMENT)`; set `APS_ENVIRONMENT` per config. Regenerate via xcodegen.
2. `ios/Gemfile` (fastlane), `ios/fastlane/{Appfile,Matchfile,Fastfile}`, `ios/fastlane/.env.local` (holds ASC API key + `MATCH_*`).
3. `.gitignore`: ignore fastlane env/build artifacts.
4. App ID registered + App Store Connect app record created (id 6785393158).
5. `bundle exec fastlane ios bootstrap_match` — created + encrypted the `match AppStore com.eugenechan.lfg` profile into `match-lfg` (reuses the account's Apple Distribution cert).
6. `bundle exec fastlane ios deploy_testflight` locally → TestFlight.

## How to ship a build (local)
```bash
cd ios
eval "$(rbenv init - zsh)"   # REQUIRED: system Ruby 2.6 fails w/ "Could not find bundler 2.4.19"; rbenv 3.2.7 has it
set -a; . fastlane/.env.local; set +a
bundle exec fastlane ios deploy_testflight
```
The build archives from the **working tree** (not a commit), so uncommitted
changes ship. Override the changelog (defaults to last commit msg) with
`TESTFLIGHT_CHANGELOG=`.
Build number is an auto HKT timestamp (YYYYMMDDHHMM); changelog defaults to the last git commit message. Override with `BUILD_NUMBER=` / `TESTFLIGHT_CHANGELOG=`.

## Signing model (local, match)
- **match** (`type: appstore`, readonly in `deploy_testflight`). The `match AppStore com.eugenechan.lfg` profile + the account's **Apple Distribution** cert live encrypted in `match-lfg`; `deploy_testflight` fetches them and signs manually. Re-run `bootstrap_match` (readonly false) only to create/renew assets.
- To sign on a fresh machine: clone nothing — just set `MATCH_*` in `.env.local` and run a lane; match pulls + decrypts from the repo.
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
- [x] Switched local signing to **match** (private `match-lfg` repo, bootstrapped 2026-07-01); verified via build 202607011901 uploaded + distributed to Internal testers ✅
- [x] Decision: **no GitHub CI** — deploy stays local (2026-07-01)
