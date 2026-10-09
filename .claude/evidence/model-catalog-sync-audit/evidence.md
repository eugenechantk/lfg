# iOS Visual Evidence Audit

Verdict: PASS (all five criteria met; two side notes below)
Timestamp: 2026-10-08 19:01 +0800
Repository: /Users/eugenechan/dev/personal/lfg
Simulator: cc-37ccd237, 85FB247F-5E5F-40AD-BBB5-E856D95EE9F8 (iPhone 17 Pro, iOS 26.3)
App: com.eugenechan.lfg, scheme LFG, ios/LFG.xcodeproj, Debug
Host: https://lfg-pro.eugenechantk.me (online). The second configured host, lfg-air, returned HTTP 530 the whole time (offline).

## Change Audited

The iOS app saves each host's `GET /api/models` answer in UserDefaults (`lfg.modelCatalogCache.v1`). It restores the saved answer at launch and refreshes every host on launch and on foreground. New-session folder defaults use the host catalog's default model. The server keeps the last good discovery per agent in `$LFG_DATA/model-catalog.json` and serves it when discovery fails.

## Success Criteria

| Criterion | Result | Evidence |
|---|---|---|
| SC1: The app saves each host's catalog and restores it at launch | PASS | `swift-test.txt`: all 4 `ModelCatalogCacheTests` pass (round-trip, per-host, corrupt data, pruning). `connection-log-excerpt.txt`: `18:56:42.865 restored saved model catalogs: https://lfg-pro.eugenechantk.me` is logged before the launch banner and before any network call. `plist-vs-host-compare.txt`: the saved catalog equals the host's `/api/models` answer (models, default, efforts, version) and includes gpt-6.1-sol. |
| SC2: The app refreshes on launch and foreground with no picker open | PASS (only one host reachable) | Cold launch at 18:56:42.9 with the list on screen (`01-cold-launch-list-no-picker.jpg`): fetchedAt went from 18:52:44 to 18:56:44.5 (`plist-00` to `plist-01`). Home at 18:58:22, then tapped the lfg icon at 18:58:35.7, and the log says "foreground after 13s backgrounded". fetchedAt went to 18:58:36.3 (`plist-02` to `plist-03`; screens `02` and `03`). The only other writers are SessionDetailView and NewSessionView, and neither was open. |
| SC3: The server serves the last good list when discovery fails | PASS | `bun-test.txt`: 9 pass. `sc3-server-probe.txt`: with `LFG_CODEX_BIN=/usr/bin/false` and a seeded temp `LFG_DATA`, codex returned the seeded list, including the sentinel `audit-seeded-model`. The control run with an empty temp `LFG_DATA` returned the compiled gpt-5.6 list. So the seed is the only cause. |
| SC4: Codex default comes from the host catalog | PASS (unit test, as the doc specifies) | `swift-test.txt`: `testAgentOnlyDirectoryUsesTheHostsDefault` and `testUnsafeModelDegradesToTheHostsDefault` pass and assert gpt-6.1-sol. The old code would return gpt-5.6-sol, so the tests tell old and new apart. The only `inferred(...)` call site (NewSessionView:390) passes `store.modelCatalog(for: selectedHost)`. |
| SC5: No regressions | PASS | `swift-test.txt`: 637 XCTest (1 skipped, 0 failures) and 223 Swift Testing, all pass. `bun-test.txt`: 9/9 pass. `flowdeck-run.jsonl`: BUILD succeeded. `04-model-picker-host-list.jpg` plus the sim-navigate check (0.99): the live picker lists gpt-6.1-sol, gpt-6-astra, gpt-6-sol, gpt-6-luna and gpt-5.6-sol/terra/luna, which is the host's list, not the compiled one. |

## Artifacts

- `01-cold-launch-list-no-picker.jpg`, `01-cold-launch-tree.json`: the list after a cold launch, with no picker open
- `02-backgrounded-home-screen.jpg`, `03-foregrounded-list-no-picker.jpg`: the background and foreground cycle
- `04-model-picker-host-list.jpg`, `04-model-picker-tree.json`: the live model picker
- `05-new-session-composer.jpg`, `06-back-on-list.jpg`: closed without starting, and no session was created
- `plist-00..03-*.txt`, `plist-modelCatalogCache.v1.json`, `plist-vs-host-compare.txt`, `host-api-models.json`
- `connection-log-excerpt.txt`, `sc3-server-probe.txt`, `swift-test.txt`, `bun-test.txt`, `flowdeck-run.jsonl`
- `sim-navigate/20261008-185945-*/` (`final.png`, `trace.jsonl`, `replay.sh`)

## Commands

- `flowdeck config get --json`: the saved config targets E0DC8228 (the shared sim). Overridden with `-S 85FB247F-…` as instructed.
- `flowdeck run -S 85FB247F-5E5F-40AD-BBB5-E856D95EE9F8 --json`: build succeeded and launched pid 71548.
- `flowdeck ui simulator session start|stop -S 85FB247F-…`, `button home`, `tap "lfg"`, `tap "Cancel"`, `tap "newSession.back" --by-id`
- `sim_navigate.py -S 85FB247F-… --goal "...tap '+' New session, tap the model chip, stop on the model picker; never tap Start session" --check "A model named 'gpt-6.1-sol' is listed on screen"`: done in 3 steps, check 0.99. Replay: `sim-navigate/20261008-185945-in-the-lfg-app-session-list-tap-the-new-/replay.sh`
- `swift test` (ios/LFGCore), `bun test src/model-catalog.test.ts`
- `LFG_DATA=<scratch temp> LFG_CODEX_BIN=/usr/bin/false bun sc3-probe.ts`, run seeded and as a control
- `curl http://127.0.0.1:8766/api/models` (read-only, this Mac is the Pro)

## Notes

- "Every configured host" is proven for one host only. The Air is configured but offline (HTTP 530), so its entry is correctly absent. Its fetch attempt cannot be seen in the plist or the log, because the refresh writes no log line.
- Minor: the comment on `refreshModelCatalogs` says an offline host's timeout "can't hold the others back". But the task group saves results only after every host returns. A host that hangs (not a fast 530) would delay saving the reachable hosts by up to the 15 s read timeout, and the in-flight guard would absorb a foreground during that window. This does not fail any criterion.
- Restore-before-network was not shown visually. A picker showing the saved list while the host is unreachable would need the network blocked. The log line and the unit tests cover it.
- The running Pro server (started 18:30) is older than `src/model-catalog.ts` (18:42), so Phase 1 is not deployed. SC3 was proven against the source, as the doc intends.
- Unrelated, already there before this change: the model picker sheet draws white text on a light glass sheet, which is hard to read. The same thing shows in the implementer's `model-sync-picker.png`. The sheet file is not touched by this change.
- Side effect: one `flowdeck ui simulator --help` call without `-S` made the session guard create and boot an extra sim, `cc-37ccd237-acaae0e4` (678F453E-1BED-47B5-884A-55F3627D5EA2). It was not used for anything. It is left booted for the guard's idle reaper.
