# Improvement log digest — 2026-10-30

Eight new logs contain 18 observations across three substantive sessions (October 25–28). Five logs are empty templates. Original logs remain preserved.

## Repeated patterns

- Verification must cover the actual behavior. A clean merge can still break a native build. A passing healthy-provider probe does not cover rate limits or an empty cache. Build the combined source and state pending checks plainly.
- Shared tooling needs ownership. Use a separate simulator for audits, keep the working directory stable, and avoid a permanent build lock for long-running WebDriverAgent.
- Repository cleanup needs a publication boundary. This public repository contains private runtime captures and over a gigabyte of generated evidence. Commit product code, reviewed design sources and concise documentation. Preserve raw evidence locally.

## Specific findings

- Inspect staged source after applying patches; zero-context insertions previously landed in the wrong location.
- Compare flaky broad test failures against the base before attributing them to a change.
- Syncthing conflict objects inside .git need a separately approved repair.
- Record whether a fix reached main, rather than recording only a branch commit.
- Provision extension entitlements before releasing. The earlier App Group blocker is recorded as addressed.
- JXA launch callbacks must be functions. This was recorded as addressed.
- Use rg for scoped searches. Avoid bare equals separators in zsh.
- Shared provider budgets need retry-after handling and a persisted last reading.
- The Air host may lack GUI Keychain access. Verify its actual credential source before deployment.
- Use SwiftUI _printChanges to identify repeated body invalidation after sampling identifies the affected view.

## Current coverage and follow-up

The standing instructions already cover release verification, scoped searches, simulator ownership, commit boundaries and preserving uncertain work. The build guard now uses native process discovery and bounded degraded discovery. Its permanent WebDriverAgent lock concern is a separate follow-up.

No global instructions, skills, agents or memory were changed. No logs were deleted. Those system changes and deletion require separate approval under the consolidation skill; they do not block the requested commits and build.
