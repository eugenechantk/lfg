# Independent verification: Autopilot connection recovery

Verdict after fixes: **PASS for the requested isolated policy, concurrency, and queue fixtures.** Installed-host delivery remains unverified.

Scope: Source review and isolated fixtures only. No real sessions were driven. No host was restarted. No product source was changed. The parent requested this fallback after the prescribed auditor model could not start.

## Final evidence

- Independent fixtures: 8 tests passed, 20 assertions. Output: `results-recheck.txt`.
- Existing recovery and queue tests: 30 tests passed, 113 assertions.
- Commands: `bun test ./.codex/feature/autopilot-recovery-audit/audit.test.ts` and `bun test src/autopilot/recovery.test.ts src/sendq.test.ts`.
- Reproduction fixtures: `audit.test.ts`.

Independent fixtures verify:

1. Twenty concurrent ticks produce one send and one claim. A later fresh invocation cannot resend an uncertain result.
2. Dry run creates neither activation state nor its state directory.
3. New assistant activity or user input supersedes the failed turn.
4. Uncertain queued recovery fails without returning to pending or kicking delivery.
5. Startup recovery parks a sending recovery as queued. An ordinary message retains its previous pending behavior. This uses an injected fake store; no database was opened.
6. Positive transcript acknowledgement marks the recovery delivered without kicking another send.
7. The final submission guard requires the exact own draft, rejects a modified draft, honors Stop, and rejects newer transcript input.
8. Observed `API Error: Connection dropped (ECONNRESET)` qualifies.

## Previously reported findings

- **Resolved:** uncertain recovery queue redelivery. Reconciliation fails closed; startup recovery parks sending recovery messages for acknowledgement.
- **Resolved:** feedback prompt dismissal. Both call sites now exclude recovery, and recovery performs one Enter round with a fresh submission guard.
- **Resolved:** partially visible claim JSON. Complete temporary records are synced and published through an atomic no-replace hardlink. The independent concurrent stress test now passes.
- **Clarified:** the earlier reset fixture used `API Error: Connection reset by peer (ECONNRESET)`. That wording was an unobserved alternative. The historical wording supplied by the parent, `Connection dropped (ECONNRESET)`, is supported and independently tested. The excluded alternative is not an outstanding defect.

## Success criteria

- SC1 PASS: existing registry places recovery first on the established interval.
- SC2 PASS in isolated checks: ownership, activity, drafts, prompts, cancellation, queue, and superseding transcript protections are covered by source review and suites.
- SC3 PASS in isolated checks: atomic claims survive concurrent runs; uncertain queue sends cannot automatically re-drive after restart or reconciliation.
- SC4 PASS: activation cutoff, backoff, three-attempt budget, and genuine user-task reset pass existing fixtures.
- SC5 PASS: independent dry run makes no recovery-state writes and sends nothing.

## Limits

A full fake terminal delivery through private `deliver()` was not exercised. The final submission guard was exercised directly with a fake pane, fake local lease, fake queue, and temporary transcript. Terminal interaction call sites were inspected. Production activation, actual Claude recovery, installed-host cadence, and real terminal behavior were deliberately not exercised.

The original failing output is retained in `results.txt`; `results-recheck.txt` records the corrected implementation.
