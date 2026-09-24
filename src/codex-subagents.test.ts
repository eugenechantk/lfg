import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  codexSubagentTranscriptFor,
  listCodexSubagentSessions,
  type CodexSubagentThread,
} from "./codex-subagents.ts";

const roots: string[] = [];
const T0 = Date.parse("2026-09-23T08:00:00.000Z");

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

function thread(
  id: string,
  parentThreadId: string | null,
  events: Array<Record<string, unknown>>,
  overrides: Partial<CodexSubagentThread> = {},
): CodexSubagentThread {
  const root = mkdtempSync(join(tmpdir(), "lfg-codex-subagent-"));
  roots.push(root);
  const path = join(root, `rollout-${id}.jsonl`);
  writeFileSync(path, events.map((event) => JSON.stringify(event)).join("\n") + "\n");
  return {
    id,
    path,
    parentThreadId,
    agentPath: `/root/${id.replaceAll("-", "_")}`,
    agentNickname: null,
    agentRole: "worker",
    spawnDepth: 1,
    createdAt: T0,
    updatedAt: T0,
    ...overrides,
  };
}

function event(type: string, at: number, payload: Record<string, unknown> = {}) {
  return {
    timestamp: new Date(at).toISOString(),
    type: "event_msg",
    payload: { type, ...payload },
  };
}

describe("native Codex child agents", () => {
  test("collects direct and nested descendants while excluding unrelated threads", async () => {
    const direct = thread("direct-child", "parent", [event("task_started", T0 + 1_000)]);
    const nested = thread("nested-child", "direct-child", [
      event("task_started", T0 + 2_000),
      event("task_complete", T0 + 3_000),
    ], { spawnDepth: 2, agentRole: "explorer" });
    const unrelated = thread("other-child", "other-parent", [event("task_started", T0 + 4_000)]);

    const agents = await listCodexSubagentSessions(
      "parent",
      [direct, nested, unrelated],
      T0 + 10_000,
    );

    expect(agents.map((agent) => agent.id)).toEqual(["nested-child", "direct-child"]);
    expect(agents[0]).toMatchObject({
      description: "nested child",
      agentType: "explorer",
      spawnDepth: 2,
      status: "completed",
      finishedAt: T0 + 3_000,
    });
    expect(agents[1]).toMatchObject({
      description: "direct child",
      agentType: "worker",
      spawnDepth: 1,
      status: "running",
    });
  });

  test("maps terminal errors and interruptions without latching the parent running", async () => {
    const failed = thread("failed-child", "parent", [
      event("task_started", T0 + 1_000),
      event("task_complete", T0 + 2_000, { error: { message: "boom" } }),
    ]);
    const stopped = thread("stopped-child", "parent", [
      event("task_started", T0 + 3_000),
      event("turn_aborted", T0 + 4_000, { reason: "interrupted" }),
    ]);

    const agents = await listCodexSubagentSessions("parent", [failed, stopped], T0 + 10_000);

    expect(agents.map((agent) => agent.status)).toEqual(["stopped", "failed"]);
    expect(agents.every((agent) => agent.finishedAt != null)).toBe(true);
  });

  test("demotes a silent running turn after the staleness backstop", async () => {
    const stale = thread("stale-child", "parent", [event("task_started", T0)], {
      updatedAt: T0,
    });

    const [agent] = await listCodexSubagentSessions(
      "parent",
      [stale],
      T0 + 31 * 60_000,
    );

    expect(agent.status).toBe("unknown");
  });

  test("resolves transcripts only through the requested parent's descendant lineage", () => {
    const direct = thread("direct-child", "parent", []);
    const nested = thread("nested-child", "direct-child", []);
    const unrelated = thread("other-child", "other-parent", []);
    const threads = [direct, nested, unrelated];

    expect(codexSubagentTranscriptFor("parent", "direct-child", threads)).toBe(direct.path);
    expect(codexSubagentTranscriptFor("parent", "nested-child", threads)).toBe(nested.path);
    expect(codexSubagentTranscriptFor("parent", "other-child", threads)).toBeNull();
    expect(codexSubagentTranscriptFor("parent", "missing", threads)).toBeNull();
  });
});
