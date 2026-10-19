# Feature: Directory-first session search

## User story

Find sessions mainly by directory, then by title, with recent conversations first.
Apply the same rule on mobile and desktop.

## User flow

1. Type into session search.
2. See directory matches before title matches, followed by other matches.
3. Read each match group from newest to oldest.
4. Clear search to restore the ordinary list order.

## Success criteria

- [x] SC1: Full-query directory or project matches lead title-only matches. Verify host ranking tests and shared Swift ordering tests.
- [x] SC2: Each match group sorts by last activity, newest first. Exact titles, prose relevance, and message counts cannot lift older sessions above newer peers. Verify regression tests with ten-week-old fixtures.
- [x] SC3: Both clients use this rule for live and closed sessions, across hosts and pages. Verify client tests, builds, and independent native UI audits.
- [x] SC4: Matching excerpts, filtering, deduplication, and stable pagination still work. Verify existing search integration tests and Swift reconciliation tests.

## Decisions

- A directory match requires every query term in the working path or project label, case-insensitively.
- A title match requires every query term in the title. Other accepted matches remain searchable after these groups.
- Use last activity for recency, consistent with the session list.
- Keep existing status and directory sections. Apply search ordering within sections and to directory section leaders.
- Search order overrides the mobile name sort while a query is active. Clearing search restores the selected ordinary sort.
- Share one Foundation-only ordering helper between mobile and desktop. Mirror its three priorities on the host before pagination.
- Preserve unrelated dirty-tree work. Do not commit, deploy, or restart production services.

## Verification evidence

- Host red regression: 3 expected failures in `directory-first-search-red.txt` before the implementation changed.
- SC1, SC2, SC4: `bun test src/ranked-session-search.test.ts src/ranked-session-search.integration.test.ts src/session-search.test.ts src/session-index.test.ts src/session-content-index.test.ts`: 63 passed, zero failures. Includes directory/title/prose ordering across frozen pages and ten-week-old fixtures. Output: `directory-first-search-host.txt`.
- SC1, SC2, SC4: Focused Swift search suites: 14 XCTest cases and 4 Swift Testing cases passed. Output: `directory-first-search-swift.txt`.
- Full LFGCore package suite passed: 648 XCTest cases (one skipped), plus 474 Swift Testing cases. Output: `directory-first-search-swift-full.txt`.
- Desktop build passed through the existing standalone `desktop/build.sh` (the desktop has no Xcode project). Final `--desktop-feature-test`: 259 assertions passed, including menu-bar order, clearing search, and loaded closed-history exclusion. Output: `directory-first-search-desktop-tests.txt`.
- TypeScript typecheck passed: `bunx tsc --noEmit --pretty false`. Output: `directory-first-search-types.txt`.
- iOS Simulator build passed through `flowdeck build --json --xcodebuild-options='CODE_SIGNING_ALLOWED=NO'`. Output: `directory-first-search-ios-build.jsonl`.
- Native audits use synthetic fixtures on checked port 18967; they do not use production data or services.
- Desktop independent audit PASS: native full-window and menu-bar search/clear, all five closed results, live/closed mixing, and three-page host ordering. Report: `../evidence/20261019-directory-first-desktop/REPORT.md`.
- Phone independent audit PASS: live and closed ordering, directory section leaders, active search overriding Name sort, and Clear restoring Name order. Report: `../evidence/20261019-122901-directory-first-ios/evidence.md`. Clean interaction recording: `../evidence/20261019-122901-directory-first-ios/23-clean-name-search-clear.mov`.

## Delivery boundary

The user authorized committing, installing, and cutting a new build. Release work uses an isolated snapshot of the search commit so unrelated dirty changes stay out of the release.
The release record under `.codex/releases/` records installed and TestFlight results separately.
Temporary acceptance host, isolated desktop processes, and phone fixture app/session are stopped. Evidence remains available on disk.

## Bugs

- Fixed: the desktop audit found that loaded closed history was treated as live during search reconciliation. This dropped those matches. Search now uses the same live-only ID helper as ordinary history placement. The regression assertion and native re-audit pass.
- Resolved audit false alarm: repeated menu gestures changed Name to Recent activity. A clean continuous sequence proves Name stays selected through search and Clear. No app change was needed.
- No open bugs.
