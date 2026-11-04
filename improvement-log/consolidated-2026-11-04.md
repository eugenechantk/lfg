# Release lessons, 4 November 2026

This digest covers the changed October 23 log and the nonempty November 3 log. Earlier archived logs and the original entries remain unchanged. No global rules or memories changed.

- Verify releases against the running listener and App Store Connect. A stale checkout or release record does not prove what is deployed.
- Freeze source before a release. Keep signing and push operations in the working GUI session when SSH cannot access the keychain.
- Report only checks that ran. Use bounded test groups when the full backend suite exceeds available memory. Keep the successful command and result together.
- Check compatibility in both directions. An older server can return success while dropping a new field. Require an acknowledgement before treating registration as complete.
- Apply user filters uniformly. Avoid special cases for one kind of scheduled task.
- Measure actual transcript formats before adding parsers. Revert unsupported heuristics.
- Keep UI fixtures isolated from real hosts. Inspect the combined screen and sheet, and verify navigation outcomes instead of trusting a zero-step automation result.
- Quote shell paths and use arrays for lists. Improve assertion diagnostics at the source rather than inferring failures from generic localized errors.

Follow-up candidates are a bounded backend test runner and clearer desktop assertion errors. They are outside this release.
