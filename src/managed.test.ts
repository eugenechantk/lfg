import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  addManaged,
  forkLineageForSession,
  listManaged,
  normalizeParentSessionId,
  patchManaged,
  type ManagedSession,
} from "./managed.ts";
import { managedFieldsForTmuxName } from "./sessions.ts";

const prevData = process.env.LFG_DATA;
const dataDir = mkdtempSync(join(tmpdir(), "lfg-managed-test-"));

beforeEach(() => {
  process.env.LFG_DATA = dataDir;
  rmSync(dataDir, { recursive: true, force: true });
});

afterAll(() => {
  if (prevData === undefined) delete process.env.LFG_DATA;
  else process.env.LFG_DATA = prevData;
  rmSync(dataDir, { recursive: true, force: true });
});

describe("managed session parent tags", () => {
  test("normalizes optional parentSessionId without failing invalid values", () => {
    expect(normalizeParentSessionId("  parent-123  ")).toBe("parent-123");
    expect(normalizeParentSessionId("")).toBeUndefined();
    expect(normalizeParentSessionId("   ")).toBeUndefined();
    expect(normalizeParentSessionId("x".repeat(64))).toBe("x".repeat(64));
    expect(normalizeParentSessionId("x".repeat(65))).toBeUndefined();
    expect(normalizeParentSessionId(42)).toBeUndefined();
  });

  test("persists parentSessionId on managed records when present", () => {
    addManaged({
      tmuxName: "lfg-child",
      cwd: "/repo",
      createdAt: 123,
      agent: "claude",
      parentSessionId: "parent-123",
    });

    expect(listManaged()).toEqual([
      {
        tmuxName: "lfg-child",
        cwd: "/repo",
        createdAt: 123,
        agent: "claude",
        parentSessionId: "parent-123",
      },
    ]);
  });

  test("persists fork lineage fields through a write/read round trip", () => {
    addManaged({
      tmuxName: "lfg-fork",
      cwd: "/repo",
      createdAt: 123,
      agent: "claude",
    });

    expect(
      patchManaged("lfg-fork", {
        sessionId: "00000000-0000-4000-8000-0000000000f0",
        forkedFrom: "00000000-0000-4000-8000-0000000000a0",
        forkSourceBytes: 456,
      }),
    ).toEqual({
      tmuxName: "lfg-fork",
      cwd: "/repo",
      createdAt: 123,
      agent: "claude",
      sessionId: "00000000-0000-4000-8000-0000000000f0",
      forkedFrom: "00000000-0000-4000-8000-0000000000a0",
      forkSourceBytes: 456,
    });

    expect(listManaged()).toEqual([
      {
        tmuxName: "lfg-fork",
        cwd: "/repo",
        createdAt: 123,
        agent: "claude",
        sessionId: "00000000-0000-4000-8000-0000000000f0",
        forkedFrom: "00000000-0000-4000-8000-0000000000a0",
        forkSourceBytes: 456,
      },
    ]);
    expect(forkLineageForSession("00000000-0000-4000-8000-0000000000f0")?.forkedFrom).toBe(
      "00000000-0000-4000-8000-0000000000a0",
    );
  });

  test("listSessions managed join emits parentSessionId only for tagged rows", () => {
    const managedByName = new Map<string, ManagedSession>([
      ["lfg-child", { tmuxName: "lfg-child", cwd: "/repo", createdAt: 1, parentSessionId: "parent-123" }],
      ["lfg-plain", { tmuxName: "lfg-plain", cwd: "/repo", createdAt: 2 }],
    ]);

    expect(managedFieldsForTmuxName("lfg-child", managedByName)).toEqual({
      managed: true,
      parentSessionId: "parent-123",
    });

    const plain = managedFieldsForTmuxName("lfg-plain", managedByName);
    expect(plain).toEqual({ managed: true });
    expect("parentSessionId" in plain).toBe(false);

    const unmanaged = managedFieldsForTmuxName("outside", managedByName);
    expect(unmanaged).toEqual({ managed: false });
    expect("parentSessionId" in unmanaged).toBe(false);
  });
});
