import { dirname, join } from "node:path";
import { mkdir, unlink } from "node:fs/promises";
import { PATHS } from "../config.ts";
import type { LiveActivityActive } from "./watcher.ts";

export const sessionActivityStatePath = () =>
  process.env.LFG_SESSION_ACTIVITY_STATE ?? join(PATHS.data, "session-live-activities.json");

export async function loadSessionLiveActivitiesActive(): Promise<Map<string, LiveActivityActive>> {
  const f = Bun.file(sessionActivityStatePath());
  if (!(await f.exists())) return new Map();
  try {
    const parsed = JSON.parse(await f.text()) as Record<string, LiveActivityActive>;
    const entries = Object.entries(parsed).filter(
      ([sid, active]) =>
        !!sid &&
        !!active &&
        active.sessionId === sid &&
        typeof active.startedAt === "number" &&
        Number.isFinite(active.startedAt),
    );
    return new Map(entries);
  } catch {
    return new Map();
  }
}

export async function saveSessionLiveActivitiesActive(active: Map<string, LiveActivityActive>): Promise<void> {
  const path = sessionActivityStatePath();
  if (active.size === 0) {
    try {
      await unlink(path);
    } catch {
      // Missing/corrupt state is equivalent to no active session activities.
    }
    return;
  }
  await mkdir(dirname(path), { recursive: true });
  await Bun.write(path, JSON.stringify(Object.fromEntries(active), null, 2));
}
