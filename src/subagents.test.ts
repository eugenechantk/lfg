import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  busyWithRunningWork,
  listSubagentSessions,
  resolveSubagentTranscript,
  runningBackgroundProcessCount,
  runningBackgroundProcessCounts,
  withSessionWorkActivity,
} from "./subagents.ts";
import {
  subagentMessagesResponseForSession,
  subagentsResponseForSession,
} from "./commands/serve.ts";

const roots: string[] = [];

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "lfg-subagents-"));
  roots.push(dir);
  const parent = join(dir, "parent.jsonl");
  const sidecars = join(dir, "parent", "subagents");
  mkdirSync(sidecars, { recursive: true });
  return { dir, parent, sidecars };
}

function line(value: unknown): string {
  return `${JSON.stringify(value)}\n`;
}

function launch(toolUseId: string, description: string, timestamp: string): string {
  return line({
    type: "assistant",
    timestamp,
    message: {
      role: "assistant",
      content: [{
        type: "tool_use",
        id: toolUseId,
        name: "Agent",
        input: {
          description,
          prompt: "private launch prompt that must not leave the transcript",
          subagent_type: "Explore",
        },
      }],
    },
  });
}

function notification(
  agentId: string,
  toolUseId: string,
  status: string,
  timestamp: string,
): string {
  return line({
    type: "queue-operation",
    operation: "enqueue",
    timestamp,
    content: [
      "<task-notification>",
      `<task-id>${agentId}</task-id>`,
      `<tool-use-id>${toolUseId}</tool-use-id>`,
      "<output-file>/private/tmp/secret-output.jsonl</output-file>",
      `<status>${status}</status>`,
      `<summary>${status} summary</summary>`,
      "</task-notification>",
    ].join("\n"),
  });
}

function child(
  sidecars: string,
  args: {
    id: string;
    toolUseId: string;
    description: string;
    lastTimestamp: string;
    agentType?: string;
    spawnDepth?: number;
  },
): string {
  const transcript = join(sidecars, `agent-${args.id}.jsonl`);
  writeFileSync(
    join(sidecars, `agent-${args.id}.meta.json`),
    JSON.stringify({
      agentType: args.agentType ?? "Explore",
      description: args.description,
      toolUseId: args.toolUseId,
      spawnDepth: args.spawnDepth ?? 1,
    }),
  );
  writeFileSync(transcript, [
    launch(args.toolUseId, args.description, "2026-08-20T04:00:00.000Z"),
    line({
      type: "assistant",
      timestamp: args.lastTimestamp,
      message: { role: "assistant", content: [{ type: "text", text: "Child result" }] },
    }),
  ].join(""));
  return transcript;
}

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("Claude subagent discovery", () => {
  test("child activity can only promote parent busy, never clear it", () => {
    expect(busyWithRunningWork(false, 0, 0)).toBe(false);
    expect(busyWithRunningWork(false, 1, 0)).toBe(true);
    expect(busyWithRunningWork(false, 0, 1)).toBe(true);
    expect(busyWithRunningWork(true, 0, 0)).toBe(true);
  });
  test("running children promote the parent busy state and expose their count", () => {
    const parent = { id: "parent", busy: false };
    const agents = [
      { status: "running" },
      { status: "completed" },
      { status: "running" },
    ] as const;

    expect(withSessionWorkActivity(parent, agents, 0)).toEqual({
      id: "parent",
      busy: true,
      runningChildAgentCount: 2,
      runningBackgroundProcessCount: 0,
    });
  });

  test("terminal children do not clear a parent turn that is already busy", () => {
    expect(withSessionWorkActivity(
      { id: "parent", busy: true },
      [{ status: "completed" }, { status: "stopped" }],
      0,
    )).toEqual({
      id: "parent",
      busy: true,
      runningChildAgentCount: 0,
      runningBackgroundProcessCount: 0,
    });
  });

  test("Claude background Bash lifecycle counts only non-terminal tasks", async () => {
    const f = fixture();
    const runningFile = join(f.dir, "shell-running.output");
    const finishedFile = join(f.dir, "shell-finished.output");
    writeFileSync(f.parent, [
      line({
        type: "user",
        timestamp: "2026-08-20T04:00:00.000Z",
        toolUseResult: { backgroundTaskId: "shell-running" },
        message: {
          content: [{
            type: "tool_result",
            content: `Command running in background. Output is being written to: ${runningFile}.`,
          }],
        },
      }),
      line({
        type: "user",
        timestamp: "2026-08-20T04:00:01.000Z",
        toolUseResult: { backgroundTaskId: "shell-finished" },
        message: {
          content: [{
            type: "tool_result",
            content: `Command running in background. Output is being written to: ${finishedFile}.`,
          }],
        },
      }),
      notification(
        "shell-finished",
        "tool-shell-finished",
        "completed",
        "2026-08-20T04:01:00.000Z",
      ),
    ].join(""));

    expect(await runningBackgroundProcessCount(
      f.parent,
      () => new Set([runningFile, finishedFile]),
    )).toBe(1);

    writeFileSync(f.parent, [
      readFileSync(f.parent, "utf8"),
      notification(
        "shell-running",
        "tool-shell-running",
        "killed",
        "2026-08-20T04:02:00.000Z",
      ),
    ].join(""));
    expect(await runningBackgroundProcessCount(
      f.parent,
      () => new Set([runningFile, finishedFile]),
    )).toBe(0);
  });

  test("a missing Claude terminal notification cannot latch a dead process", async () => {
    const f = fixture();
    const outputFile = join(f.dir, "stale.output");
    writeFileSync(f.parent, line({
      type: "user",
      timestamp: "2026-08-20T04:00:00.000Z",
      toolUseResult: { backgroundTaskId: "shell-stale" },
      message: {
        content: [{
          type: "tool_result",
          content: `Command running in background. Output is being written to: ${outputFile}.`,
        }],
      },
    }));

    expect(await runningBackgroundProcessCount(f.parent, () => new Set())).toBe(0);
  });

  test("background liveness for a session snapshot is proven in one batch", async () => {
    const first = fixture();
    const second = fixture();
    const firstOutput = join(first.dir, "first.output");
    const secondOutput = join(second.dir, "second.output");
    for (const [parent, id, output] of [
      [first.parent, "shell-first", firstOutput],
      [second.parent, "shell-second", secondOutput],
    ]) {
      writeFileSync(parent, line({
        type: "user",
        toolUseResult: { backgroundTaskId: id },
        message: { content: [{
          type: "tool_result",
          content: `Output is being written to: ${output}.`,
        }] },
      }));
    }
    const probes: string[][] = [];
    const counts = await runningBackgroundProcessCounts(
      [first.parent, second.parent],
      (paths) => {
        probes.push(paths);
        return new Set([firstOutput, secondOutput]);
      },
    );

    expect(probes).toHaveLength(1);
    expect(new Set(probes[0])).toEqual(new Set([firstOutput, secondOutput]));
    expect(counts.get(first.parent)).toBe(1);
    expect(counts.get(second.parent)).toBe(1);
  });

  test("background processes promote parent busy independently of children", () => {
    expect(withSessionWorkActivity({ id: "parent", busy: false }, [], 2)).toEqual({
      id: "parent",
      busy: true,
      runningChildAgentCount: 0,
      runningBackgroundProcessCount: 2,
    });
  });

  test("discovers sidecars, lifecycle state, timestamps, and newest-first ordering", async () => {
    const f = fixture();
    child(f.sidecars, {
      id: "older",
      toolUseId: "tool-older",
      description: "Map studio app",
      lastTimestamp: "2026-08-20T04:03:00.000Z",
    });
    child(f.sidecars, {
      id: "newer",
      toolUseId: "tool-newer",
      description: "Map media pipeline",
      lastTimestamp: "2026-08-20T04:05:00.000Z",
      agentType: "general-purpose",
    });
    writeFileSync(f.parent, [
      launch("tool-older", "Map studio app", "2026-08-20T04:01:00.000Z"),
      launch("tool-newer", "Map media pipeline", "2026-08-20T04:02:00.000Z"),
      notification("older", "tool-older", "completed", "2026-08-20T04:04:00.000Z"),
      notification("newer", "tool-newer", "failed", "2026-08-20T04:06:00.000Z"),
    ].join(""));

    const sessions = await listSubagentSessions(f.parent);

    expect(sessions.map((s) => s.id)).toEqual(["newer", "older"]);
    expect(sessions[0]).toMatchObject({
      description: "Map media pipeline",
      agentType: "general-purpose",
      spawnDepth: 1,
      status: "failed",
      startedAt: Date.parse("2026-08-20T04:02:00.000Z"),
      lastActivityAt: Date.parse("2026-08-20T04:06:00.000Z"),
      finishedAt: Date.parse("2026-08-20T04:06:00.000Z"),
    });
    expect(sessions[1].status).toBe("completed");
  });

  test("uses the newest lifecycle event so a stopped child can resume", async () => {
    const f = fixture();
    child(f.sidecars, {
      id: "resumed",
      toolUseId: "tool-resumed",
      description: "Resume audit",
      lastTimestamp: "2026-08-20T04:03:00.000Z",
    });
    writeFileSync(f.parent, [
      launch("tool-resumed", "Resume audit", "2026-08-20T04:01:00.000Z"),
      notification("resumed", "tool-resumed", "killed", "2026-08-20T04:02:00.000Z"),
      notification("resumed", "tool-resumed", "running", "2026-08-20T04:04:00.000Z"),
    ].join(""));

    const [session] = await listSubagentSessions(f.parent);

    expect(session.status).toBe("running");
    expect(session.finishedAt).toBeNull();
    expect(session.lastActivityAt).toBe(Date.parse("2026-08-20T04:04:00.000Z"));
  });

  test("maps killed and stopped to stopped and keeps unknown statuses neutral", async () => {
    for (const [raw, expected] of [
      ["killed", "stopped"],
      ["stopped", "stopped"],
      ["future-value", "unknown"],
    ] as const) {
      const f = fixture();
      child(f.sidecars, {
        id: raw,
        toolUseId: `tool-${raw}`,
        description: raw,
        lastTimestamp: "2026-08-20T04:02:00.000Z",
      });
      writeFileSync(f.parent,
        launch(`tool-${raw}`, raw, "2026-08-20T04:01:00.000Z")
        + notification(raw, `tool-${raw}`, raw, "2026-08-20T04:03:00.000Z"));
      expect((await listSubagentSessions(f.parent))[0].status).toBe(expected);
    }
  });

  test("applies a grouped lifecycle notification to every listed child", async () => {
    const f = fixture();
    for (const id of ["grouped-one", "grouped-two"]) {
      child(f.sidecars, {
        id,
        toolUseId: `tool-${id}`,
        description: id,
        lastTimestamp: "2026-08-20T04:02:00.000Z",
      });
    }
    writeFileSync(f.parent, [
      launch("tool-grouped-one", "grouped-one", "2026-08-20T04:01:00.000Z"),
      launch("tool-grouped-two", "grouped-two", "2026-08-20T04:01:01.000Z"),
      line({
        type: "queue-operation",
        operation: "enqueue",
        timestamp: "2026-08-20T04:03:00.000Z",
        content: [
          "<task-notification>",
          "<task-id>grouped-one</task-id>",
          "<task-id>grouped-two</task-id>",
          "<status>stopped</status>",
          "</task-notification>",
        ].join("\n"),
      }),
    ].join(""));

    const sessions = await listSubagentSessions(f.parent);

    expect(sessions.map((session) => session.status)).toEqual(["stopped", "stopped"]);
  });

  test("returns only safe summary fields and ignores malformed sidecars", async () => {
    const f = fixture();
    child(f.sidecars, {
      id: "safe",
      toolUseId: "tool-safe",
      description: "Safe description",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    writeFileSync(join(f.sidecars, "agent-broken.meta.json"), "not json");
    writeFileSync(join(f.sidecars, "agent-broken.jsonl"), "also not jsonl");
    writeFileSync(f.parent, launch("tool-safe", "Safe description", "2026-08-20T04:01:00.000Z"));

    const sessions = await listSubagentSessions(f.parent);
    const encoded = JSON.stringify(sessions);

    expect(sessions).toHaveLength(1);
    expect(encoded).not.toContain("private launch prompt");
    expect(encoded).not.toContain("/private/tmp");
    expect(Object.keys(sessions[0]).sort()).toEqual([
      "agentType", "description", "finishedAt", "id", "lastActivityAt",
      "spawnDepth", "startedAt", "status",
    ]);
  });

  test("resolves only transcripts that belong to the requested parent", () => {
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "safe-id",
      toolUseId: "tool-safe",
      description: "Safe child",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });

    expect(resolveSubagentTranscript(f.parent, "safe-id")).toBe(transcript);
    expect(resolveSubagentTranscript(f.parent, "../safe-id")).toBeNull();
    expect(resolveSubagentTranscript(f.parent, "missing")).toBeNull();
  });

  test("serves sanitized summaries and normalized child transcript messages", async () => {
    const f = fixture();
    child(f.sidecars, {
      id: "api-child",
      toolUseId: "tool-api",
      description: "API child",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    writeFileSync(f.parent,
      launch("tool-api", "API child", "2026-08-20T04:01:00.000Z")
      + notification("api-child", "tool-api", "completed", "2026-08-20T04:03:00.000Z"));
    const resolve = async () => f.parent;

    const listResponse = await subagentsResponseForSession("parent", resolve);
    const listBody = await listResponse.json() as { agents: Array<Record<string, unknown>> };
    const messageResponse = await subagentMessagesResponseForSession(
      "parent",
      "api-child",
      new URL("http://localhost/api?full=1"),
      resolve,
    );
    const messageBody = await messageResponse.json() as { messages: Array<Record<string, unknown>> };

    expect(listResponse.status).toBe(200);
    expect(listBody.agents[0]).toMatchObject({ description: "API child", status: "completed" });
    expect(JSON.stringify(listBody)).not.toContain("/private/tmp");
    expect(messageResponse.status).toBe(200);
    expect(messageBody.messages.some((message) => message.text === "Child result")).toBe(true);
  });
});
