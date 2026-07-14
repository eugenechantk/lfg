import { dirname, join } from "node:path";
import { mkdir, unlink } from "node:fs/promises";
import { PATHS } from "../config.ts";
import type { LiveActivityActive } from "./watcher.ts";

export const fleetActivityStatePath = () =>
  process.env.LFG_FLEET_ACTIVITY_STATE ?? join(PATHS.data, "fleet-activity-state.json");

export async function loadFleetActivityActive(): Promise<LiveActivityActive | null> {
  const f = Bun.file(fleetActivityStatePath());
  if (!(await f.exists())) return null;
  try {
    const parsed = JSON.parse(await f.text()) as LiveActivityActive;
    if (!parsed || typeof parsed.startedAt !== "number" || !Number.isFinite(parsed.startedAt)) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export async function saveFleetActivityActive(active: LiveActivityActive | null): Promise<void> {
  const path = fleetActivityStatePath();
  if (!active) {
    try {
      await unlink(path);
    } catch {
      // Missing/corrupt state is equivalent to no active fleet activity.
    }
    return;
  }
  await mkdir(dirname(path), { recursive: true });
  await Bun.write(path, JSON.stringify(active, null, 2));
}
