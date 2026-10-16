# Desktop session status stays synchronized

Product tier. Desktop session list and its host state feed.

## User story

The desktop session list must show the real running state. Finished sessions leave Working, and active sessions remain Working, across both hosts and after reconnects.

## Success criteria

- [x] Compare live desktop and host states and reproduce stale status in both directions. Verify host snapshots, installed-client observations, and a controlled transport fixture.
- [x] Start, completion, abort, and waiting states update the desktop consistently. Verify deterministic regression tests for both false-working and false-idle cases.
- [x] Reconnects, missed events, and stale updates converge to the host's current authoritative state. Verify integration or desktop model tests.
- [x] Quiet explicit provider turns remain running until an actual completion, abort, or confirmed stop. Verify existing and new lifecycle regressions.
- [x] Appropriate host and desktop tests/build pass, and independent verification confirms user-visible state convergence.

## Decision log

Trace the desktop projection, transport, and provider state before choosing the fix. Preserve pending iOS fade work. Do not interrupt, send to, or close real user sessions to reproduce this issue. Use disposable synthetic sessions for mutation tests.

The initial Pro and Air APIs and installed Pro menu counts agreed. Later live verification captured an idle row under Recent that still displayed Working. Both native clients reached both hosts. Python's public-host request received HTTP 403, so it was not used as evidence of native host availability.

Desktop previously refreshed from ten-second view timers and had no journal subscription. Make synchronization application-owned. Use one resumable journal stream per host, with the same SSE frame parser as iOS. Keep ten-second authoritative snapshots as recovery, independently of which view is open. Preserve journal edges newer than an in-flight snapshot, and do not mark a healthy streaming host offline because one REST request failed.

Extract the existing generic SSE parser into its own foundation-only source file without changing its public API. Existing parser tests passed before and after extraction. Parse network bytes outside the main actor; only typed status updates enter the store. Keep host/provider state inference unchanged.

A second defect lived in native row rendering. After a session moved between nested status groups, its Button label retained the previous state. A same-window SSE fixture reproduced both directions: an active row under Working said Ready, and a finished row under Recent said Working. Key the whole row subtree by session ID, projected status, and offline state so a status change recreates its native label. Apply the same identity rule to menu-bar rows. Add `--stream-for <seconds>` to the existing offscreen harness to verify changes within one view hierarchy. A resumed session whose ID already exists as a closed historical row must trigger immediate live discovery; only live rows satisfy the event discovery check.

## Verification evidence

- Final native desktop build passed: `.codex/evidence/desktop-status-sync/build-resume-fixed.log`.
- All 202 desktop checks passed, including 19 new status regressions. The independent final candidate and both installed copies repeated these checks.
- Existing parser tests passed before and after extraction: 14 tests each, `parser-before.log` and `parser-after.log`.
- Existing host lifecycle, arbitration, parity, and journal tests: 80 passed, zero failed, `host-tests.log`. Quiet explicit Codex turns retain their established lifecycle behavior.
- Production-store transport integration passed against two disposable hosts: immediate start/completion, independent hosts, delayed REST responses, missed starts on reconnect, cursor resume, journal reset, REST failure during healthy streaming, and discovery/completion of new sessions. Results: `integration-result.json`; observed row histories: `integration-observations.json`.
- Independent transport/store verification passed 27 temporal checks plus 202 native and 89 host tests. Final same-window verification passed both status directions, prompt appearance, prompt clearing, and historical-row resume. Resume discovery requested a snapshot within 29 milliseconds. Report: `.codex/evidence/desktop-status-sync-independent-20261017/render-transitions/evidence.md`.
- The same signed final binary is installed and running on Pro and Air. SHA256: `c0d8019ae53e45cf5b019bd3155fc4d14cf597ee68a3bb761235dfbda2c14751`. Installation, backup, signature, and test receipts: `.codex/evidence/desktop-status-sync/deployment/`.
- Both installed native clients connected to both live hosts. Every observed row matched the corresponding host snapshot: 42 rows on Pro and 41 on Air, including six Working sessions. Captures occurred at different times. The live Pro window also displayed six correct Working rows. See `deployment/live-verification.json` and `pro-final-installed-ui.png`.

## Residual risks

The exact historical rows from the original report were not named. A live false Working label was captured and repaired, and both directions passed same-window regression verification. Air verification covers the installed binary, native live feed, and model; its GUI was not inspected. The Air SSH observation ended early after its valid baseline; a later check confirmed the sole installed app still running. Host/provider inference remains unchanged. No commit or TestFlight release was made for this change.
