# Verification Audit

Verdict: PASS
Timestamp: 2026-11-03 10:39 HKT
Repository: /Users/eugenechan/dev/personal/lfg (uncommitted tree on main, host Eugenes-MacBook-Pro)
Surface: mixed (server tests + live API, iOS simulator UI + push, macOS desktop CLI test)

## Change Audited

Hidden directories also mute notifications per device. The server stores each phone's `hiddenDirs`
with its push token and skips muted devices in `runPushTick` and `SessionNotifications.send`.
The iOS app sends the set on register, re-registers on change, and drops foreground banners for
hidden cwds. The Mac app filters `notificationItems`.

## Success Criteria

| Criterion | Declared Method | Result | Evidence |
| --- | --- | --- | --- |
| SC1 watcher skips muted devices only | `bun test src/push/` | PASS: 137 pass, 0 fail. New case sends `ipad:s1, ipad:s2, phone:s2`. With the filter disabled in a scratch copy, it fails (`phone:s1` appears). Real-seam probe with the sim's stored record and real cwds: 0 sends to the sim for 2 inbox sessions, 6 to it for others | 01-sc1-bun-test-push.log, 01b-sc1-push-junit.xml, 09-mutation-server-filters-disabled.log, 10-real-seam-probe.log |
| SC2 notify skips muted devices; all-muted is `muted` | `bun test src/session-notifications.test.ts` | PASS: 12 pass, 0 fail. Mutant fails (`phone` gets sent). Probe: inbox session gives `{"state":"accepted","attempted":1,"muted":1}` | 02-*.log/xml, 09-*.log, 10-real-seam-probe.log |
| SC3 register normalizes; omit keeps; `[]` clears | curl on :8792 plus the store file | PASS: messy input stored `["/Users/e/.gbrain","*/gbrain-claude-cli-cwd-*","/Users/e/dev/x"]`. Omitted and `null` keep it. `[]` clears it, and a later omit keeps `[]`. A bad token gets 400 | 03-sc3-register-curl.log, 03b-sc3-cleanup.log |
| SC4 sim sends its hidden set and re-registers on change | Drive the Filter sheet and watch the store | PASS: tap hide `dump` at 10:30:48.6, store shows `[inbox, dump]` at 10:30:49.46. Tap Show at 10:31:09.4, store shows `[inbox]` at 10:31:10.2 | 04-sc4-store-watch.log, 04-sc4-actions.log, 04-sc4-0*.jpg |
| SC5 foreground: hidden cwd shows no banner; visible cwd does | `flowdeck simulator push` in the foreground | PASS: muted pushes produced 0 changed frames in 5 s and in 6 s. The control banner showed at +290 ms and fully at +1068 ms. The only difference between payloads is the cwd | 05-sc5-push.log, 05-sc5-02-control-frame-1793673168604.jpg, 05-sc5-03z-after-muted2.jpg, payload JSONs |
| SC6 Mac app posts no local alert for hidden-dir sessions | build.sh -Onone + `--desktop-feature-test` | PASS: `{"ok":true,"tests":286}`. A mutant without the filter fails with `"sessions in a hidden directory post no native notification"` | 06-sc6-desktop-build-and-feature-test.log, 11-mutation-desktop-filter-removed.log |
| SC7 footer copy | Sim screenshot | PASS: "...stay out of the list, the counts and search on this device, and send it no notifications. They keep running. Swipe a directory to show it again." | 07-sc7-filter-directories-footer.jpg, 07-sc7-filter-directories-footer-2.png, 07-sc7-filter-sheet-tree.json |
| Regression: LFGCore `swift test` | `swift test` | PASS: 651 XCTest (1 skipped, 0 failures) and 582 Swift Testing tests pass. Both new tests pass | 08-lfgcore-swift-test.log |
| Extra: type check | `bunx tsc --noEmit` | PASS: exit 0 | 12-tsc-noemit.log |

## Commands

- `cd /Users/eugenechan/dev/personal/lfg && bun test src/push/`
- `bun test src/session-notifications.test.ts`
- `curl -i -X POST -H 'content-type: application/json' -d '<body>' http://127.0.0.1:8792/api/push/register`, then read `<scratch>/lfg-data/push-devices.json`
- `flowdeck ui simulator session start -S 5EC98829-...` then `tap sessions_more --by-id`, `tap directoryFilterButton --by-id`, `tap "hideCandidate-/Users/eugenechan/dev/personal/dump" --by-id`, `swipe --from 330,610 --to 80,610`, `tap --point 339,606` (Show)
- `flowdeck simulator push <payload.json> -b com.eugenechan.lfg -S 5EC98829-...` with frames grabbed from the UI session's screens dir
- `cd desktop && LFG_DESKTOP_OPTIMIZATION=-Onone ./build.sh && ./build/lfg.app/Contents/MacOS/lfg --desktop-feature-test`
- `cd ios/LFGCore && swift test`
- Mutants: copies in scratchpad (`audit-mutant-server`, `audit-mutant-desktop`) with the filter line disabled. The repo was not edited.

## Notes

- The doc claims 161 push tests and 285 desktop checks. This run gives 137 and 286. The counts drift. No failures.
- The audit's fake token `a0d17a0d17000001` was unregistered from the scratch store afterwards. The sim was left with `inbox` hidden, as found.
- **The tree changed during the audit.** Between 10:30 and 10:32 a concurrent agent edited `watcher.ts`, `session-notifications.ts`, `chat-jobs.ts`, `desktop/DesktopNotifications.swift`, `DesktopNotificationTests.swift`, `build.sh` and `StartSessionIntent.swift`, and added `alert-title.ts` and `AlertStatus.swift` (a separate emoji-title change). The mute lines did not change. After those edits, the audit re-ran the server tests (137 + 13 + chat-jobs 8 pass, 13-rerun-after-concurrent-edits.log) and LFGCore (651 XCTest + 584 Swift Testing pass, 14-lfgcore-swift-test-rerun.log). The desktop build (10:33:50), both mutants and the probe all ran after the last edit (10:32:26).
- The scratch server (started 10:22) and the sim app predate the alert-title edits. Neither touches the register route or the iOS mute code.
- See the final report for gaps outside the criteria.
