# Offline chat release

Source: the verified `codex/chat-host-availability` worktree on cc5fdaf. No commit or push was requested.

| Target | Current result | Evidence |
| --- | --- | --- |
| Pro host | Updated and restarted | Public chat capabilities and health return 200. All 31 task configurations and 34 terminal sessions survive. |
| Pro desktop | Updated and running | Installed executable hash and all eight bundle files match; signature and 259 built-in checks pass. |
| iOS | Available in TestFlight | Version 1.4.1, build 202610291121. IPA metadata, both bundled hosts, VALID, highest train and IN_BETA_TESTING verified. |
| Air host and desktop | Pending connectivity | SSH tunnel fails, local hostname does not resolve and the public API returns HTTP 530. Both update packages are retained. |

The host deploy uses a checked snapshot of the live runtime with only the two reviewed backend files replaced. Type checking and all 157 backend regressions pass in that snapshot. Existing coding agents stay in their terminal sessions. The prior desktop bundle is retained for rollback.

The iOS project was regenerated back to its canonical form after upload. All audited product hashes still match. Main's unrelated tracked edits remain untouched. The Mac was relocked after background UI verification.

Canonical TestFlight verification completed with DoD PASS at 11:31:50 HKT. Pro health passed again after the desktop update. Air remained unreachable on the final SSH and HTTP checks. User action: bring Air online to finish its update. See `release-state.json` and `testflight-verify.log` for receipts.
