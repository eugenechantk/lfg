# Pro disk recovery, 25 October 2026

The Pro's full disk stopped LFG. Clearing disposable uv cache restored the service.

## Cause

At 13:25 HKT, the data volume had about 114 MiB free. Memory pressure was normal.
LFG's log recorded failed writes with `ENOSPC` and `SQLITE_FULL`.
The server exited at 13:19 and failed each restart with a disk I/O error.
SSH and the Cloudflare tunnel remained available.

## Action

The user authorized cleanup. No process had the uv cache open.
Ran `/opt/homebrew/bin/uv cache clean` on the Pro.
uv removed 189,771 files and reported 8.8 GiB removed.
Actual free disk space increased to 3.637 GiB. Cache size and reclaimed space differ.
No active apps, sessions, models, project environments, or databases were removed.
No source code, deployment, commit, or push was involved.

## Verification

- LFG restarted automatically at 13:26:31 HKT.
- At 13:27:01, `/api/info` returned HTTP 200 and identified the Pro.
- `/api/sessions` returned HTTP 200 with 24 sessions.
- The new server log showed event-stream clients reconnecting, without another startup error.
- The memory guard reported normal pressure, 31.2% compressor segments, and 7.87 GiB swap used.
- An external probe from the Air returned HTTP 403. The phone UI was not inspected.

Remaining disk space is limited. Larger caches include installed tools and models, so they were preserved.
