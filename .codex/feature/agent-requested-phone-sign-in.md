# Agent-requested phone sign-in

Product-tier change, following phone sign-in commit `100dfd6`. No new commit unless requested.

## Interaction
A Claude or Codex agent encountering an authentication wall invokes a shared skill/CLI command with its session ID, exact connected browser ID, and login URL. The host creates a short-lived request and the command waits for a terminal result. The session view shows **Sign in to <website>** above the composer. One tap opens a fresh, nonpersistent website session with the URL and browser already chosen. **Done** sends all exportable cookies from that session, including cross-domain login cookies, to the pinned browser and releases the waiting command. No typing a URL, choosing a browser, domain checklist, or separate Send step in this path.

## Boundaries and decisions
- Requested sign-in is the primary contextual button. More → Sign in on iPhone lists this session’s history, with manual sign-in available from the list’s + button.
- Local token-authenticated request creation; phone operations use existing HTTPS/Cloudflare authentication. No agent sees cookie values or passwords.
- Exact target binding. Reconnect/disconnect does not silently choose another browser. One active request per browser; duplicate creates for the same session/browser/URL reuse the existing request.
- Requests expire after 15 minutes. Up to 128 metadata records are retained across host restarts in an owner-only file; URLs persist as origins only. Restart expires pending requests and marks interrupted delivery unknown. No stored credentials or automatic cookie replay.
- Done acknowledges cookie installation, not website acceptance. The agent must refresh/check the requested website before continuing. Cancel, expiry, offline, partial and uncertain delivery stay distinct.
- Agent integration is a global skill shared between Claude and Codex plus a CLI, rather than a new MCP server. The CLI returns metadata only and supports explicit request/status/cancel and bounded waiting.
- Session detail polls only its owning host while active. Request metadata is separate from transcripts. No changes to database schema.

## Success criteria and verification
- [x] An agent command creates a request bound to session, URL, and exact browser; duplicates, auth boundaries, offline targets and expiry are tested.
- [x] iPhone/iPad show the contextual sign-in button; tapping opens the requested website directly, without URL/browser/domain fields.
- [x] Done exports all valid cookies from this isolated web session exactly once to that browser; real integration proves target isolation and the waiting command's result.
- [x] Cancel, expired/disconnected targets, ambiguous delivery, host restart and concurrent Done never report false success or reroute cookies.
- [x] Shared skill installed for Claude/Codex with deterministic invocation and metadata-only debug mode.
- [x] Independent visual audit passes; updated Hihi build and actual host integration verified.

## Evidence
- Backend: 12 Bun tests / 79 assertions pass. New tests exercise pinned targets, idempotent creates/completes, request expiry, cancellation, offline targets, concurrent Done, local-token/origin/proxy boundaries, and missing state after host replacement.
- Real CLI process creates request via HTTP, waits while pending, then returns `installed` after a real Playwright context imports portal + SSO cookies. Protected page changes 401→200; another context remains empty; attempted client retargeting is ignored. Output contains no cookie values.
- Full Swift package: 463 XCTest + 118 Swift Testing tests PASS (581 total), including all-domain export and server-bound completion request shape.
- TypeScript and whitespace checks pass. Simulator build passed after fixing one catch-variable shadowing error; one simulator installation hit a transient IPC failure, and retry succeeded without changing app code.
- Self-verification: native contextual button → direct fresh fixture → synthetic login → Done, request `fe9fcc9a-55d9-468e-ab5c-a8b4d406031a` installed 1/1 and fixture changed installed:false→true. Initial self-recording did not include the final Done and is not acceptance evidence; independent auditor is recording the full interaction.
- Global Claude skill installed at `~/.claude/skills/request-phone-sign-in/SKILL.md`, exposed to Codex by symlink. Packaged template and safe installer live in `integrations/phone-sign-in/` and `scripts/install-phone-sign-in-skill.ts`.
- Live Mac host updated using additive feature files after snapshotting previous files; restart retained all 23 session IDs. Live CLI create/status/cancel PASS against the actual Chrome destination. Verification request cancelled afterward.
- Hihi build/install/launch PASS, FlowDeck run `55FB95D9`. Existing private Cloudflare bootstrap remains gitignored. No new commits/pushes.
- Independent iPhone/iPad audit PASS: contextual button → direct fresh website → synthetic sign-in → Done → installed result. Fresh-session isolation, empty-cookie Done, Cancel/removal and browser disconnect before Done all pass. Full recordings and report: `.codex/evidence/agent-phone-sign-in/audit/`. Actual account authentication was not repeated in this iteration; the prior App Store Connect acceptance remains separate evidence.


## Hihi live request trial — 2026-09-12 02:28 HKT
- Rebuilt, installed and launched current feature on Hihi; FlowDeck run `557C3D2E-D29E-4000-AC2C-BA9E97744DE4` succeeded.
- Created request `8aa5f33e-f1ec-452c-a310-7900b2922c09` for this session, App Store Connect `/apps`, and connected `Chrome — personal` target `572484d6-b4f3-4f36-8963-781dcf4b787d`. CLI waits for Done.
- Desktop App Store Connect was already authenticated before this trial; a subsequent authenticated page alone will not prove a signed-out→signed-in transition. Cookie-delivery metadata and the physical phone interaction are the checks for this trial.
- Eugene pressed Done on Hihi. Live request and waiting CLI both returned `installed`, 12 of 12 cookies delivered to the pinned personal Chrome target. Refreshed the existing `/apps` tab; authenticated Eugene account navigation appeared. PASS for real phone request→Done→Chrome acknowledgment→waiting-agent completion. Desktop was already authenticated, so this trial does not independently prove a signed-out→signed-in transition. No cookie values were inspected or recorded.

## Match child-agent button styling
Use the existing child-session card's background, 11pt corner radius, subtle separator border, 16pt outer inset, 12×9pt inner padding, 28pt tinted icon column, primary semibold title, secondary caption and tertiary chevron for the requested sign-in button. Keep the request action and accessibility ID. Styling only: simulator build and independent visual evidence are appropriate; no new logic tests. Verification PASS.
- Styling update builds and launches on iPhone 17 Pro (`A3C92730`) and Hihi (`F366F53A`). Independent visual comparison PASS: both cards align and match background, border, corner shape, icon/text insets and typography. Tapping sign-in still opens the direct website. Evidence: `.codex/evidence/phone-sign-in-button-style/matching-cards.jpg`.

## Session sign-in history
More → Sign in on iPhone becomes a submenu with View all and this session's requests, like child sessions. View all opens a newest-first list showing website, browser, timestamp and status. Waiting rows reopen the sign-in view; terminal rows show read-only outcome details. Manual sign-in remains available from the list. Composer cards stay waiting-only.

Host keeps up to 128 recent metadata records across all sessions in an atomic owner-only JSON file. Stored URLs are origins only; cookies and URL paths/query/fragment never persist. On restart waiting requests become expired and in-progress delivery becomes unknown, never replayed. Tests cover session isolation, ordering, persistence/redaction, restart states and terminal non-replay. Independent iPhone/iPad audit checks submenu, list, detail and pending navigation. Verification pending.
- History verification: all 14 pre-existing/current backend tests passed (93 assertions), followed by the added restart-during-delivery test (7 request-registry tests /37 assertions). Combined coverage: 15 tests/96 assertions. Six focused Swift tests pass, including status presentation and millisecond timestamp decoding. TypeScript and whitespace checks pass.
- Live history deployment: metadata file migrated with the successful personal Chrome request and cancelled Browse request; both returned newest-first after restart, permissions 0600. All 23 live session IDs retained.
- Hihi history build installed/launched successfully, FlowDeck run `62DB3AFA`. Independent iPhone audit passes submenu/list, pending→Done→Sent, terminal read-only detail, Cancelled retained newest-first, close/reopen history and composer cleanup. Remaining iPad/empty/manual checks pending.
- Independent iPad audit caught a row hit-area gap: text was tappable but blank space between text and chevron was not. Added a full-row rectangular content shape; rebuilding/re-auditing that interaction before completion.
- Final independent audit PASS on iPhone and iPad. More submenu, newest-first history, pending→login→Done→Sent, read-only terminal details, Cancelled retention, close/reopen, empty-session isolation and manual fallback all pass. Full-row content-shape correction verified at blank-space tap points on final iPad `DFE65F20` and iPhone `37ED2F60` builds. Evidence/report: `.codex/evidence/phone-sign-in-history/audit/report.md`.
- Final Hihi build/install/launch PASS `F36BE2DE`, including full-row hit-area fix. No commits or pushes.

## Direct medium history sheet
User correction: More → Sign in on iPhone must open the history sheet directly, with no nested menu/popover. Match Child sessions: medium initial detent, expandable to large, visible drag handle, inset-grouped list, 22pt status icon, body/medium title, single caption line combining destination and status, 3pt vertical row padding. Keep timestamps in detail. Login website sheets stay large. No backend or logic changes; verify native iPhone/iPad presentation and row taps with focused independent audit.
- Final medium-sheet build/run PASS on iPhone17Pro `35B122BD` and Hihi `2FEC8108`, including matching status tints. Independent focused presentation/style audit PASS on iPhone `35B122BD` and iPad `CBABA12A`: single More action directly opens medium sheet with drag handle; child-list row styling matches; full-row taps open exact pending website in large sheet; iPhone drag expansion passes. Report `.codex/evidence/phone-sign-in-medium-sheet/report.md`. No logic changed; prior backend/Swift behavior tests remain applicable.

## Completion interaction (2026-09-12)
Requested sign-in removes the destination caption. Successful Done sends once and dismisses the website sheet; partial/unknown/failed delivery stays actionable. Done is hidden until unexpired cookies exist and either requested-host account/sign-out controls are detected without visible login fields/iframes, or the user confirms “I’m signed in”. Cookies alone never imply login. A one-second active-view check supports same-page web apps and expires readiness when cookies disappear. Navigation clears explicit confirmation. Detection reads control metadata only, never field values. Generic automatic authentication detection remains heuristic; account controls can be present on signed-out pages, so Done always remains a user action and the agent verifies the protected destination after delivery.
Validation: focused Swift readiness cases plus independent simulator recording of hidden Done before login, available Done after login, direct dismissal, and installed-cookie metadata.

Completion validation so far: seven focused Swift tests pass; seven real-browser DOM checks pass (including shadow-root menu, visible login form, iframe, and generic account link); final simulator build E7909E37 succeeds; signed iOS device build succeeds. Hihi install is currently blocked: Xcode lacks destination00008110-0011083A1151801E and direct FlowDeck install reports CoreDeviceError1011 (device unavailable). No app installed on any alternate device. Final independent UI report: `.codex/evidence/phone-sign-in-completion/report.md`.

Final independent functional audit passed on iPhone and iPad: automatic completion2/2 cookies on both; manual confirmation1/1; no-cookie fallback disabled; cancelled/expired/offline paths remain explicit and never show success. Success closes directly to parent without acknowledgement sheet. iPhone fallback has a faint trace below its readable label near the sheet bottom; no label clipping or hit-target failure. Hihi still requires reconnecting before installation.
