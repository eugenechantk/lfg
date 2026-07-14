import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  fleetActivityStatePath,
  loadFleetActivityActive,
  saveFleetActivityActive,
} from "./fleet-active-store.ts";
import type { LiveActivityActive } from "./watcher.ts";

let dir: string | null = null;
const withStore = () => {
  dir = mkdtempSync(join(tmpdir(), "lfg-fleet-active-"));
  process.env.LFG_FLEET_ACTIVITY_STATE = join(dir, "fleet-activity-state.json");
};

afterEach(() => {
  delete process.env.LFG_FLEET_ACTIVITY_STATE;
  if (dir) rmSync(dir, { recursive: true, force: true });
  dir = null;
});

describe("fleet activity active-state persistence", () => {
  test("round-trips the active fleet state across a simulated restart", async () => {
    withStore();
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 1,
        rows: [
          { sid: "s1", title: "Approve", host: "Studio", state: "blocked", since: 1_690 },
          { sid: "s2", title: "Build", host: "Air", state: "working", since: 1_695 },
        ],
        hosts: [{ name: "Studio", online: true }],
        updatedAt: 1_700,
      },
    };

    await saveFleetActivityActive(active);

    expect(await loadFleetActivityActive()).toEqual(active);
  });

  test("missing, removed, or corrupt state loads as empty", async () => {
    withStore();
    expect(await loadFleetActivityActive()).toBeNull();

    await saveFleetActivityActive({ startedAt: 1, contentState: undefined });
    await saveFleetActivityActive(null);
    expect(await loadFleetActivityActive()).toBeNull();

    writeFileSync(fleetActivityStatePath(), "{not json");
    expect(await loadFleetActivityActive()).toBeNull();
  });
});
