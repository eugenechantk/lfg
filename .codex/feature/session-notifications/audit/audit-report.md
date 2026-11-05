# Session notification audit

Verdict: PASS for SC1–SC6 using their declared automated verification methods.
No open findings remain in this gate.

The audit edited evidence only. It did not change product code, production data, or installed clients.
Real host probes used isolated data on checked loopback port 18771. Background workers and physical APNs were disabled.
The probe server exited and released the port.

## Current evidence

- `independent-regressions.txt`: 208 tests and 716 assertions passed across 15 files, including all 12 independent adversarial tests.
- `adversarial-output.txt`: the 12 independent tests passed again in isolation, with 87 assertions.
- `types.txt` and `diff-check.txt`: both commands exited 0 without diagnostics.
- `desktop-feature-output.json`: the final real application executable independently passed 282 checks.
- `native-output.json`: 21 independent native probes passed. The harness compiles exact production declarations for notices, copy, tracking, decoding, and reconciliation.
- `real-route-output.json`: a fresh real host accepted real CLI and MCP requests. It journaled exactly two alerts and returned duplicate=true for a retry.
- The real host retained the completed receipt separately after a later needs-input alert replaced the latest notification.
- Two fake mobile registrations produced honest failed receipts because physical APNs was disabled. No physical notification was sent.
- `source-hashes.json` records the final source files and executable. `native-source-hashes.txt` records the native harness inputs.

## Criterion results

- SC1: PASS. All five statuses fan authored copy to both injected mobile environments. Production serialization stays within 4,096 bytes for maximum valid Unicode.
- SC2: PASS. Native frames decode, reconcile against stale snapshots, and retain authored copy. Replayed receipt IDs do not repeat alerts.
- SC3: PASS. Real CLI, MCP, and HTTP calls share the request contract and return honest acceptance receipts.
- SC4: PASS. Completion receipts suppress the same stop, including markerless sessions. Later busy cycles and real questions still alert.
- SC4 also passes delayed old receipts, marker repair, missed completion events, later reminders, and a completion arriving during host observation.
- SC5: PASS. Blank, oversized, invalid-display, cross-origin, unknown-session, and conflicting retry requests fail safely.
- SC5 also passes concurrent retries, restarted retries, transport failure, and an ambiguous receipt persisted before delivery finished.
- SC6: PASS. Automatic copy uses current assistant prose, preserves filenames and C#, and excludes stale replies and private thinking.
- Managed session instructions retain caller context and require exact session identity. Durable native chats receive their own UUID on resumed turns.
- Scheduled chat turns omit the extra notification instruction.

## Findings resolved during audit

1. An unbounded real session title produced a 7,046-byte APNs envelope. The service now caps and sanitizes the snapshot title. The same probe produces 476 bytes.
2. Unpaired surrogates produced a 4,320-byte envelope. Custom fields now reject them and non-display controls before persistence or emission.
3. Missing or stale native user markers caused duplicate generic completions. Explicit completion receipts and a completion latch now suppress that stop.
4. A boolean REST hint could re-arm an old completion after a later busy edge. Both clients now remember completion receipt identity separately.
5. Markerless host sessions duplicated completion on mobile. The watcher now checks the latest completion receipt after observation and remembers its identity.

The host and native tracker clear the latch for a later busy interval or a newer user turn.
An old receipt cannot re-arm it. A later reminder cannot erase completion metadata.

Before-fix evidence remains in `adversarial-before-fixes.txt`, `native-before-fixes.json`, and `native-delayed-hint-before-fix.json`.

## Limits

This gate did not verify physical iPhone or iPad arrival, human receipt, or native macOS banner rendering.
It proves production payload construction, route behavior, journal delivery, native posting candidates, and tests.
No host deployment, app installation, release, commit, or push formed part of this audit.
