import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { lastPaneBusy, notePaneBusy, scanStateRoots } from "./activity.ts";

const tempDirs: string[] = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function tempRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), "lfg-activity-"));
  tempDirs.push(dir);
  return dir;
}

function writeState(root: string, slug: string, jobs: unknown[]): void {
  const dir = join(root, slug);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "state.json"), JSON.stringify({ version: 1, jobs }));
}

async function exitedPid(): Promise<number> {
  const proc = Bun.spawn(["sh", "-c", "exit 0"]);
  const pid = proc.pid;
  await proc.exited;
  return pid;
}

describe("scanStateRoots", () => {
  test("running job with a live pid marks the session active", () => {
    const root = tempRoot();
    writeState(root, "workspace-a", [
      { id: "job-1", status: "running", sessionId: "s-live", pid: process.pid },
    ]);

    expect(scanStateRoots([root])).toEqual(new Set(["s-live"]));
  });

  test("running job with a dead pid is excluded", async () => {
    const root = tempRoot();
    writeState(root, "workspace-a", [
      { id: "job-1", status: "running", sessionId: "s-dead", pid: await exitedPid() },
    ]);

    expect(scanStateRoots([root]).has("s-dead")).toBe(false);
  });

  test("running job with a null pid is excluded", () => {
    const root = tempRoot();
    writeState(root, "workspace-a", [
      { id: "job-1", status: "running", sessionId: "s-null", pid: null },
    ]);

    expect(scanStateRoots([root]).has("s-null")).toBe(false);
  });

  test("completed and failed jobs are excluded even with live pids", () => {
    const root = tempRoot();
    writeState(root, "workspace-a", [
      { id: "job-1", status: "completed", sessionId: "s-complete", pid: process.pid },
      { id: "job-2", status: "failed", sessionId: "s-failed", pid: process.pid },
    ]);

    expect(scanStateRoots([root]).size).toBe(0);
  });

  test("job missing sessionId is ignored without throwing", () => {
    const root = tempRoot();
    writeState(root, "workspace-a", [{ id: "job-1", status: "running", pid: process.pid }]);

    expect(scanStateRoots([root]).size).toBe(0);
  });

  test("malformed JSON and missing roots return an empty set", () => {
    const root = tempRoot();
    mkdirSync(join(root, "workspace-a"), { recursive: true });
    writeFileSync(join(root, "workspace-a", "state.json"), "{not json");

    expect(scanStateRoots([root, join(root, "missing")]).size).toBe(0);
  });

  test("multiple slug dirs and roots are unioned", () => {
    const rootA = tempRoot();
    const rootB = tempRoot();
    writeState(rootA, "workspace-a", [
      { id: "job-1", status: "running", sessionId: "s-a", pid: process.pid },
    ]);
    writeState(rootB, "workspace-b", [
      { id: "job-2", status: "running", sessionId: "s-b", pid: process.pid },
    ]);

    expect(scanStateRoots([rootA, rootB])).toEqual(new Set(["s-a", "s-b"]));
  });
});

describe("pane busy cache", () => {
  test("returns recent values and expires entries older than 10s", () => {
    notePaneBusy("s-pane", true, 1000);

    expect(lastPaneBusy("s-pane", 10_999)).toBe(true);
    expect(lastPaneBusy("s-pane", 11_001)).toBeNull();
  });
});
