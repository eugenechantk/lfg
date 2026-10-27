# Merge durable chats into main

The user approved merging and pushing the durable chat feature on 28 October 2026. This does not request a host deployment or TestFlight release.

## Success criteria

- [x] SC1: Merge the full feature with current main while retaining file previews, the share extension, account usage and terminal task outcome reviews. Verify resolved source, generated project, native builds and independent audits.
- [x] SC2: Preserve shared task persistence, lifecycle, migration, notifications and scoped tools alongside main's review queue. Verify backend regressions, independent probes and typechecking.
- [x] SC3: Message and Tasks open the correct durable conversation on iPhone and iPad. The iPad conversation uses an open canvas like Sessions, with no enclosing colored card or rounded wrapper. Verify the integrated binary with fresh independent screenshots and playable recordings.
- [x] SC4: Prepare reviewable commits and a clean merge for main. No incoming path collides with main's untracked files. The feature and documentation commits are c7ef7ce and bbae50e. Push after the native audit, then report the remote main SHA in the session.

## Decisions

- Preserve the feature worktree and main's untracked files. Resolve the merge in an isolated integration worktree.
- Keep code and its tests together; commit architecture and verification notes separately. Exclude generated captures, recordings, local tools, build logs and scratch fixtures.
- Regenerate the Xcode project from the merged project.yml, retaining all test targets and the share extension.
- Preserve terminal post-session reviews and their queue. Reject terminal review requests for chat/reminder runs so they cannot rewrite notification decisions or delivery receipts.

## Verification evidence

- Independent backend audit PASS: 411 product tests / 1508 assertions and 39 independent probes / 143 assertions. Typechecking passes; all 25 backend source fingerprints match.
- Swift package: 561 tests / 86 suites pass.
- iOS application tests through FlowDeck: 17 tests pass.
- Mac build passes; 259 desktop feature checks pass. The final open-canvas source also passes a fresh Mac build.
- Canonical iOS build passes. Root self-check opens Message then Scout's durable conversation on the merged binary.
- Independent native audit PASS on the final rebuilt iPhone and iPad binaries. Instructions, memory, models, canonical Tasks, lifecycle controls, coding fields and Open chat routing pass. The iPad canvas passes empty/populated portrait and landscape plus the software keyboard. Four curated H.264 recordings play at 30 fps. Evidence stays locally under `.codex/feature/durable-chat-merge/native-audit/`.
- Main has no tracked dirt and no untracked file collides with incoming feature paths.

## Tooling note

FlowDeck intermittently selected the Widgets product when launching the multi-target LFG scheme. A temporary, uncommitted app-only verification scheme installed the merged app on the owned iPhone and iPad simulators. The canonical project was regenerated afterward and matches its audited source. This changed no product code. Failed launch experiments and their logs remain local.

## iPad design adjustment

The user requested removing the background container around the full iPad conversation before merging. The detail now uses the app canvas with no rounded clipping or outer vertical inset. Its header shares the canvas, and the composer keeps its own raised surface. The sidebar keeps its existing list card. Fresh empty and populated captures pass in landscape and portrait. The landscape software-keyboard composer and final phone regression pass.

## Review page

The existing native review gallery now uses the flat iPad captures and current iPhone recording. The live HTML and portrait capture return HTTP 200. Media remains local and uncommitted. The page is public to anyone with its link and stops serving after a Mac reboot until sharing restarts.

## Delivery boundary

The local merge commit is bfd6dbe. The user-requested iPad styling follows as its own commit. Backend and native audits use temporary test stores and fake notification transports. Physical APNs delivery remains unverified. No production host restart, deployment, database operation or TestFlight release was performed.
