import { hostname } from "node:os";
import { join } from "node:path";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { PATHS } from "./config.ts";

// Multi-host identity. Each machine running `lfg serve` reports a stable id +
// a friendly name so the iOS client (which fans out to several hosts) can label
// sessions by machine and, critically, DEDUPE a host reached via two URLs
// (Tailscale IP vs MagicDNS name) — same hostId → same machine.
export type HostInfo = { hostId: string; hostName: string };

// hostId is a uuid persisted in `data/host-id`, minted once and reused. A uuid
// (not the raw hostname) survives a machine rename and never collides. If the
// file can't be read/written (permissions, read-only fs) we fall back to the
// hostname so the endpoint still answers — dedupe just degrades to url-based.
export function readOrCreateHostId(dataDir: string): string {
  const file = join(dataDir, "host-id");
  try {
    const existing = readFileSync(file, "utf8").trim();
    if (existing) return existing;
  } catch {
    // not created yet
  }
  const id = randomUUID();
  try {
    mkdirSync(dataDir, { recursive: true });
    writeFileSync(file, id + "\n");
  } catch {
    return hostname(); // best-effort fallback
  }
  return id;
}

export function hostInfo(): HostInfo {
  return { hostId: readOrCreateHostId(PATHS.data), hostName: hostname() };
}
