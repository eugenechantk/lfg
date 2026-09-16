# Feature: transfer-from-offline-host

## User Story

As Eugene, I want to move a session to another host **while its current host is unreachable**, so that an offline Mac never traps a conversation. Today "Move to host" starts by closing the pane on the source host and aborts with "Transfer: closing on <host> failed" when that host is down — which is precisely the situation the move exists for.

## User Flow

1. Session lives on host A. Host A goes offline (asleep, tunnel down, lid closed). The session row dims and the composer shows the offline notice.
2. Eugene opens the ⋯ menu → Move to host → picks host B.
3. The client skips the close on A (A is known down), and asks B to resume the synced transcript, telling B to ignore A's stale lease.
4. B revives the conversation under a new session id; navigation jumps to it; Eugene keeps working on B.
5. When A comes back, the client closes the orphaned pane on A once (best effort, persisted across app restarts), so the old copy does not linger as a second live session.

## Success Criteria

- [x] SC1: Moving a session whose host is **known down** (`offline` / `noNetworkSustained`) skips the source close and proceeds to resume on the target — **Verify by:** `SessionTransferTests` (plan for `sourceKnownDown: true` has `closeSource == false`, `force == true`) + code path in `SessionStore.transfer`.
- [x] SC2: When the host is not yet flagged down but the close fails with a transport error (`notReachable` / `transport`), the transfer still proceeds; an HTTP error from the close still aborts — **Verify by:** `SessionTransferTests.testCloseFailureClassification`.
- [x] SC3: The target server's resume accepts `force: true` and bypasses the "session is live on another host" 409 when the source's lease is still fresh; without `force` it still 409s — **Verify by:** `src/commands/serve-resume-force.test.ts` against a fixture lease file.
- [x] SC4: A skipped source close is remembered (persisted) and executed once the source host next becomes live — **Verify by:** `SessionTransferTests` for `DeferredSourceCloses` (add / take / codable round-trip) + wiring in `SessionStore.setHostState`.
- [x] SC5: Existing behaviour is unchanged when the source host is reachable: close on source, wait for it to disappear, resume on target without `force` — **Verify by:** `SessionTransferTests` (plan for `sourceKnownDown: false`) + `swift test` green + iOS app builds.
- [ ] SC6: Live seam: forced resume over a fresh foreign lease on the real server — **Verify by:** curl `POST /api/sessions/resume` with `force:true` against a fixture lease; expect no 409. (Depends on restarting the long-lived server; see Decision Log.)

- [x] SC7: Before the source is touched, the client asks the TARGET for its transcript status; a target without the transcript refuses the move with "<target> doesn't have this transcript yet" and the source pane is untouched — **Verify by:** `SessionTransferTests.testPreflightMissingTranscriptBlocks` + `serve-transcript-status.test.ts` + live seam (stub as target in `TS_MODE=missing`, source pane still in `tmux ls`).
- [x] SC8: A target whose copy is more than 60s behind the source's last activity gets a confirmation dialog ("… is N min behind …") instead of a silent fork; Cancel leaves the source untouched — **Verify by:** `testPreflightStaleCopyAsksInsteadOfBlocking` + live seam (`TS_MODE=stale`, dialog screenshot, Cancel, source pane still live).
- [x] SC9: A target server without the route (HTTP 404) is treated as unknown and the move proceeds exactly as before; a target missing the session's cwd is refused naming the path — **Verify by:** `transferPreflight` 404 branch by inspection + `testPreflightMissingCwdBlocksWithPath`; full `swift test` green.

## Platform & Stack

- **Platform:** iOS client (SwiftUI, LFGCore package) + Bun server (TypeScript)
- **Key files:** `ios/LFG/SessionStore.swift` (`transfer`, `setHostState`), `ios/LFGCore/Sources/LFGCore/Models.swift` (`ResumeRequest`), `LFGClient.resume`, new `LFGCore/SessionTransfer.swift`, `src/commands/serve.ts` (`resumeClosedSession`, resume route)

## Steps to Verify

1. `cd ios/LFGCore && swift test --filter SessionTransferTests`
2. `bun test src/commands/serve-resume-force.test.ts`
3. `flowdeck build` of the iOS app (compile gate for the SessionStore wiring)
4. Live: fixture lease + curl resume with/without `force` (SC6)

## Implementation Phases

### Phase 1: Server `force`
- Scope: `resumeClosedSession({force})` skips the foreign-lease veto when set; the route reads `force` from the body; log the override.
- SC covered: SC3.

### Phase 2: LFGCore pure logic + models
- Scope: `SessionTransfer.plan`, `closeFailureIsUnreachable`, `DeferredSourceCloses`; `ResumeRequest.force`; client sends it.
- SC covered: SC1, SC2, SC4 (logic), SC5.

### Phase 3: SessionStore wiring
- Scope: `transfer` uses the plan; deferred closes persisted in UserDefaults and replayed on host-live transition.
- SC covered: SC1, SC4, SC5.

### Phase 4: Pre-flight on the target (added 2026-09-15, second request)
- Scope: `GET /api/sessions/:id/transcript-status` (server, tested); `TranscriptStatus` model + `LFGClient.transcriptStatus`; `SessionTransfer.preflight` rules; `SessionStore.transferPreflight` + gate at the top of `transfer`; stale-copy confirmation dialog in the detail view's menu.
- SC covered: SC7, SC8, SC9.

## Decision Log

- **Force is client-asserted, not server-inferred.** The target server cannot tell "source host is down" from "source host is fine but the phone can't reach it" — both look like a fresh synced lease. The client is the only party that observed the outage, so it passes `force` only when its own host-state machine says the source is down (or the close itself failed at the transport layer). Alternative: retry the resume until the 90s lease expires. Rejected: it adds up to 90s of waiting, and a host that is up-but-unreachable-from-the-phone never expires it.
- **Deferred close instead of no close.** Eugene asked to move "without necessarily closing". Reading: the close must not be a precondition. Once the source is back, its pane is an idle orphan of a conversation that continued elsewhere, so closing it is cleanup, not data loss (the transcript survives a pane close). It is best effort and one-shot.
- **Resume on the target may KEEP the id.** The server comment says claude `--resume` mints a new id; the live run showed the Pro's revived pane reporting the SAME id (`50980bea…`). So the orphan on A and the live copy on B can share an id until A is back and the deferred close lands — a bounded window of the "one id, two processes" hazard. The deferred close is therefore routed by HOST (`settings.client(for: sourceHost)`), never by `client(forSession:)`, which would resolve to the new owner and close the wrong copy.
- **No confirmation dialog.** Eugene's stated intent is the move; the menu action is explicit. The differing semantics are surfaced by the source copy simply being closed later.
- **Server restart for SC6 is deferred to Eugene.** Restarting `lfg serve` drops in-memory session tracking; per project CLAUDE.md restarts are deliberate. SC6 is verified when the server next restarts; the unit test covers the same guard.

- **Pre-flight is asked of the target, and `found:false` is a 200.** A 404 must stay reserved for "old server without the route" so the client can keep working against un-restarted hosts (`.unknown` → proceed as before). Staleness compares the target copy's last message timestamp (not mtime — Syncthing rewrites mtimes) with the source session's `lastActivityAt`; the threshold is 60s so sync jitter never nags. Stale is a confirmation, not a refusal: the user may want the older copy (the source is down and they want to keep going). Missing transcript / missing cwd / unreachable target are refusals — no choice makes them sensible.

## Verification Evidence

_Evidence dir: `.claude/feature/evidence/transfer-from-offline-host/` (stub log, screenshots, stub script)._

| SC | Method | Result |
| --- | --- | --- |
| SC1 | `swift test --filter SessionTransferTests` (plan for known-down source) + live seam | 7/7 pass. Live: stub host killed 09:12:12Z, offline notice shown (`s9-detail-offline.png`), Move to host → Cloudflare Pro at 09:15:40Z; **no close reached the stub** (`stub.log` lines 1–30) and the Pro spawned pane `lfg-ac573b` resuming `50980bea…`; detail view re-homed to Eugenes-MacBook-Pro with a live composer (`s12-after-move.png`) |
| SC2 | `SessionTransferTests.testCloseFailureClassification` | pass (notReachable/transport → proceed; http/decoding/other → abort) |
| SC3 | `bun test src/commands/serve-resume-force.test.ts` | 3/3 pass: fresh peer lease → 409 + liveOn; `force` → no veto; no lease → no veto |
| SC4 | `SessionTransferTests` (add/take/forget/codable) + live seam | pass. Live: stub back 09:16:22Z; first successful `GET /api/sessions` 09:18:58.822Z → `POST /api/sessions/50980bea…/close` 09:18:58.876Z on the STUB (`stub.log` lines 31–33), 54ms later, routed by host id |
| SC5 | full `swift test` + `flowdeck build` + `tsc --noEmit` | 516 tests, 0 failures (1 skipped); build completed twice (before and after the 409-message edit); no tsc errors in serve.ts. Reachable-source path unchanged by inspection (`git diff ios/LFG/SessionStore.swift`) |
| SC6 | curl resume with `force` against the live server | **Not run** — the running `lfg serve` (pid 41409, started 16:05) predates the edit and a restart drops in-memory session tracking; left to Eugene. Until the server is restarted on both hosts, a forced move within ~90s of the source's last synced heartbeat gets the new "still sees this session running on X. Try again in a minute." message; after that window it succeeds even on the old server |
| SC7 | `swift test` pre-flight tests + `bun test src/commands/serve-transcript-status.test.ts` + live seam | 14/14 + 3/3 pass. Live (stub as TARGET, `TS_MODE=missing`, source = real Pro pane `lfg-72f509`): tap Move to host → stub; stub log `GET …/transcript-status` 09:48:35.836Z, **no close**; banner "Transfer: stub-offline-test doesn't have this transcript yet — the synced copy hasn't arrived. Try again in a few minutes." (`sc7-missing-transcript-banner.jpg`, tree `sc7-missing-transcript-tree.json`); source pane still in `tmux ls`, session still on the Pro |
| SC8 | `testPreflightStaleCopyAsksInsteadOfBlocking` + live seam | pass. Live (`TS_MODE=stale`, copy dated 30 days ago vs source 8 days): dialog "Move anyway? stub-offline-test's copy of this conversation is 22 days behind Eugenes-MacBook-Pro. Moving now continues from that older copy; the newer turns stay only on Eugenes-MacBook-Pro." with "Move to stub-offline-test" (`sc8-stale-copy-dialog.png`); dismissed → source pane alive, zero close requests |
| SC9 | `transferPreflight` catch `LFGError.http(404)` → `.unknown` (inspection) + `testPreflightMissingCwdBlocksWithPath` + `testTranscriptStatusDecodesLenientlyAndFoundDefaultsFalse` | pass; full `swift test` 524 tests, 0 failures; FlowDeck build green; `tsc --noEmit` clean for serve.ts |

Cleanup (phase 4): stub killed, source pane `lfg-72f509` closed via the Pro API, stub host removed from Settings.

Cleanup: stub killed, test pane `lfg-ac573b` closed via the Pro API (tmux back to the 12-pane baseline), stub host removed from the simulator's Settings.

## Audit

`verification-auditor` verdict **PARTIAL** (report: `.claude/feature/evidence/transfer-from-offline-host/evidence.md`): SC1–SC5 PASS, SC6 not verifiable until the long-lived server is restarted. Audit note acted on: `close(_:)` now forgets a deferred close only when the manual close succeeded (a failed close leaves the replay to clean up); app rebuilt green afterwards. Not acted on (consistent with one-shot intent): a host removed from Settings drops its owed closes; the normal path sends `"force": null`, which the server's `=== true` check treats as absent.

Phase 4 audit: `verification-auditor` verdict **PASS** on SC7–SC9 (report `evidence-phase4.md`). Deploy note: the Pro's `lfg serve` was restarted at 17:28 (after the `force` edit, before the transcript-status edit), so on the Pro the forced-resume half is live and the pre-flight route still 404s → the client takes the `.unknown` path until the next restart.

## Bugs

_None open._
