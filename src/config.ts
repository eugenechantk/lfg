import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { existsSync, mkdirSync, cpSync, readdirSync } from "node:fs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// Per-machine state (host identity, managed-session registry, push devices,
// queues, reports). This must NEVER live inside a synced folder: the repo is
// synced between hosts, and keeping it at <repo>/data produced Syncthing
// conflict files on data/host-id and data/managed-sessions.json — i.e. the
// state that makes each host unique was being overwritten by the other host.
// ~/.lfg is outside every synced path (only ~/.claude is synced).
const LEGACY_DATA = join(ROOT, "data");
const DATA = process.env.LFG_DATA ?? join(homedir(), ".lfg");

// One-time migration, per entry: copy anything from the legacy repo data/ that
// ~/.lfg doesn't already have (the dir may pre-exist — it holds the APNs key —
// so an all-or-nothing guard would silently skip host-id and mint a new
// identity). Existing files always win; Syncthing conflict artifacts are
// skipped. The legacy dir is left in place — the other machine migrates itself
// on its own next boot, and a stale copy is harmless once nothing reads it.
if (!process.env.LFG_DATA && existsSync(LEGACY_DATA)) {
  mkdirSync(DATA, { recursive: true });
  for (const entry of readdirSync(LEGACY_DATA)) {
    if (entry.includes(".sync-conflict-")) continue;
    const dst = join(DATA, entry);
    if (existsSync(dst)) continue;
    cpSync(join(LEGACY_DATA, entry), dst, {
      recursive: true,
      filter: (src) => !basename(src).includes(".sync-conflict-"),
    });
  }
}

export const PATHS = {
  root: ROOT,
  data: DATA,
  sessionTitles: join(DATA, "session-titles.json"),
};
