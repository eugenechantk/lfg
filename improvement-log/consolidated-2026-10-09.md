# Improvement Log Digest — 2026-10-09

This incremental digest covers 40 logs since September 25, including 14 substantive logs and 76 tracker items. Earlier digests remain the record for older work. All source logs remain intact.

## Recurring findings

- Runtime proof must follow the user's actual route. API responses, source inspection, and upload completion each prove only one boundary.
- Several Codex installations have reappeared. Resolve the actual executable and version on each Mac; historical install policy is not runtime evidence.
- Concurrent sessions share source files, build folders, and simulators. Freeze a reviewed source snapshot before release and compare hashes before replacing remote files.
- Shell aliases, zsh expansion, and guessed FlowDeck arguments repeatedly broke otherwise correct commands. Use explicit working directories, literal simulator IDs, and documented arguments.
- Broad process matches killed unrelated work. Resolve exact listener or application PIDs before a restart.

## Existing coverage and remaining work

Project instructions already cover shared-tree preservation, process discovery, server restart verification, and dependency installation before a restart. FlowDeck documents simulator targeting and command discovery. The release skill requires IPA metadata, processing state, version train, and beta availability.

The model cache, transient-error classification, PDF file policy, folder trust, and desktop fork fixes address concrete product findings. iPhone preview and scheduled tasks have independent native audits.

A durable release script could freeze source, verify host file hashes, check dependencies, install the signed desktop bundle, restart exact listeners, and record live probes. Evaluate that separately after this release. An Access-secret rotation runbook remains useful; do not rotate credentials during routine deployment.

No global instructions, skills, memories, or credentials were changed. No logs were deleted. Those optional system changes and deletions require separate approval under the consolidation skill.
