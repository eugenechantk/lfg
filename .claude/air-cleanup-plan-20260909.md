# Air cleanup plan — 2026-09-09

**State:** Data volume 99% full — **2.9 GB free of 228 GB**. Pro has 201 GB free.
lfg server on the Air at **3.0 GB RSS** (started 09-07). One live Claude session
(cy-224353, transcript touched 00:53 today).

**Ground rule:** `~/dev`, `~/.claude`, `~/.codex` are Syncthing **send-receive**
mirrors of the Pro. A delete inside them propagates to the Pro unless the path is
in the Air's `.stignore` first (and the ignore has registered). Everything under
`~/Library`, `~/.cache`, `~/.local` is Air-local.

## Tier A — Air-local, no sync impact (~8 GB)

| what | size | action |
|------|------|--------|
| Simulators: iPhone 17, iPad mini, iPhone 17 Pro Max data | 2.0 + 1.2 + 0.7 GB | `flowdeck simulator erase` (keep iPhone 17 Pro, our verification device) |
| `~/Library/Caches/Google` (Chrome cache) | 1.5 GB | delete |
| `~/Library/Caches/ms-playwright` | 554 MB | delete (browse/gstack ship their own Chromium) |
| `~/Library/Caches/org.swift.swiftpm`, `pnpm`, `Homebrew` | 230 + 222 + 163 MB | delete / `brew cleanup` |
| `~/.local/share/claude/versions` 2.1.246/247/251 | 660 MB | delete, keep 2.1.261 |
| Xcode Archives 2026-07-* | ~300 MB | delete (Aug 25 archive kept) |
| `~/.Trash` | 197 MB | empty |
| `~/Library/Logs/CoreSimulator` | 59 MB | delete |

## Tier B — synced junk; deleting on BOTH machines is the point (~12 GB Air, ~4.5 GB Pro)

| what | Air | Pro | note |
|------|-----|-----|------|
| `~/.claude/telemetry/1p_failed_events.*` | 4.0 GB / 3849 files | 4.0 GB / 3854 | failed telemetry uploads, pure waste |
| gbrain autopilot temp-cwd transcripts `~/.claude/projects/-private-var-folders-*` | 4.6 GB / 161 dirs | 148 MB / 91 | throwaway cwds ([[gbrain-autopilot-temp-cwds]]); counts differ so sync is already incomplete here |
| `~/.claude/session-env/` older than 7 days | 1.1 GB / 142,900 dirs | 257 MB / 33,069 | per-session env dirs; 72k are >14 days old |
| `~/.codex/sessions/2026/08` rollouts ≥100 MB | 2.5 GB / 9 files | same | these are the 500 MB rollouts that blow lfg's read paths ([[lfg-host-disconnect-is-memory-ceiling]]) — removing them helps both hosts |

## Tier C — Air-only via `.stignore` then local delete; Pro keeps its copy (~30 GB)

Only worth it if the Air does not need this media. Pro has the full 50 GB fiftyworkout tree.

| what | size | .stignore pattern (Air only) |
|------|------|------------------------------|
| `fiftyworkout/studio-data` (clip sources) | 20 GB | `/personal/fiftyworkout/studio-data` |
| `fiftyworkout/content/*/_working` (raw DJI camera) | 5.9 GB | `/personal/fiftyworkout/content/*/_working` |
| `fiftyworkout/ads` (production + finals) | 6.9 GB | `/personal/fiftyworkout/ads` |
| `reelly/ios/assets/sample_videos`, `reelly/stock-videos` | ~4 GB | `/personal/reelly/ios/assets/sample_videos`, `/personal/reelly/stock-videos` |

Recipe per path: add pattern → wait for Syncthing to rescan (or `syncthing cli` rescan) → confirm
the path shows as ignored → `rm -rf` on the Air.

## Not touching, but flagged

- `~/dev/inbox/.git` **10 GB** and `podcast-pipelines/.git` **7.5 GB** — media committed into git
  history. Only a history rewrite shrinks these; both sync to the Pro at the same size.
- `~/Library/Application Support`: FileProvider 3.8 GB + CloudDocs 2.5 GB (iCloud), Google 2.8 GB
  (Chrome profile), Syncthing 1.7 GB (index). Leave.
- Chrome on the Air: renderers from Sep 5, ~2.5 GB RAM. Yours to close.
- `~/.claude/skills/gstack` 1.2 GB — bundled browser, in use.

## Service hygiene (not disk)

- **lfg server 3.0 GB RSS.** Restart by port when no session is mid-turn
  (`lsof -nP -iTCP:8766 -sTCP:LISTEN -t | xargs kill`; serve-forever respawns).
- **Done today:** Air `~/.claude/.stignore` was missing the `/state` exclusion the Pro has
  (simulator-activity ledger must not sync). Aligned; backup `.stignore.bak-20260909`.

## Recommendation

Run **A + B now** (~20 GB back on the Air, 2.9 → ~23 GB free), and **C for
fiftyworkout studio-data + _working + reelly sample videos** unless the Air is where that
footage gets edited. That lands the Air near 50 GB free. Restart the lfg server after.

---

## Executed 2026-09-09 01:40–02:00 HKT (Eugene chose A + C + lfg restart; B deferred)

| step | result |
|------|--------|
| Tier A caches / archives / sim logs / Trash / brew | done, ~2.5 GB |
| Tier A simulators erased (iPhone 17, iPad mini, 17 Pro Max) | 3.9 GB → 51 MB; iPhone 17 Pro kept |
| Tier A old Claude Code binaries | 2.1.246 + 2.1.247 removed; **2.1.251 kept** — the live session (pid 93782) still executes it; delete once that session ends |
| Tier C ignore + delete | patterns added to Air `~/dev/.stignore`, rescan, all 5 paths `ignored=True`, then `rm -rf`; Pro verified intact (20 + 5.9 + 7.9 + 3.2 + 1.1 GB), `needDeletes=0` |
| lfg server restart | pid 1038 (3.0 GB RSS) → pid 55915 (313 MB); live session re-enumerated |
| `.claude/.stignore` drift | Air now matches Pro (`/sessions` + `/state`) |

**Air free space: 2.9 GB → 43 GB** (99% → 79%).

Tier B (telemetry 4 GB, gbrain temp transcripts 4.6 GB, session-env 1.1 GB, big codex
rollouts 2.5 GB) is untouched and still available; it propagates to the Pro by design.

Gotchas hit: `POST /rest/db/scan` on the 90 GB folder blocks until the scan finishes
(>2 min) — fire it and poll `/rest/db/status` instead; the first `<address>` in
Syncthing's config.xml is the device's (`dynamic`), the GUI address is inside `<gui>`.
