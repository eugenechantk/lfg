import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  busyWithRunningWork,
  listSubagentSessions,
  resetSubagentCacheForTests,
  resolveSubagentTranscript,
  runningBackgroundProcessCount,
  runningBackgroundProcessCounts,
  withChildSessionActivity,
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
    expect(busyWithRunningWork(false, 0)).toBe(false);
    expect(busyWithRunningWork(false, 1)).toBe(true);
    expect(busyWithRunningWork(true, 0)).toBe(true);
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
      // The row carries the agents themselves, not only their count: the
      // client's detail view seeds from this when the owner host is not live
      // and the per-session /subagents read would land on a peer whose synced
      // sidecars lag by minutes (diagnosis 2026-09-07).
      childAgents: [...agents],
    });
  });

  test("a session without child agents keeps the row shape byte-identical", () => {
    const row = withSessionWorkActivity({ id: "parent", busy: false }, [], 0);
    expect("childAgents" in row).toBe(false);
    expect(row).toEqual({
      id: "parent",
      busy: false,
      runningChildAgentCount: 0,
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
      childAgents: [{ status: "completed" }, { status: "stopped" }],
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

  test("background processes surface as a badge and never promote parent busy", () => {
    // A dev server started with run_in_background stays alive for hours;
    // folding it into busy pinned idle sessions "Working" forever and
    // suppressed their finished/needs-input pushes (bug 010).
    expect(withSessionWorkActivity({ id: "parent", busy: false }, [], 2)).toEqual({
      id: "parent",
      busy: false,
      runningChildAgentCount: 0,
      runningBackgroundProcessCount: 2,
    });
  });

  test("a busy spawned child session promotes its parent (Eugene: parent read Idle while its delegate ran)", () => {
    const rows = withChildSessionActivity([
      { sessionId: "parent", parentSessionId: null, busy: false },
      { sessionId: "delegate", parentSessionId: "parent", busy: true },
      { sessionId: "bystander", parentSessionId: null, busy: false },
    ]);

    expect(rows.find((r) => r.sessionId === "parent")).toMatchObject({
      busy: true,
      runningChildSessionCount: 1,
    });
    expect(rows.find((r) => r.sessionId === "bystander")?.busy).toBe(false);
  });

  test("an idle child session does not promote, and completion releases the parent", () => {
    const rows: Array<{
      sessionId: string;
      parentSessionId: string | null;
      busy: boolean;
      runningChildSessionCount?: number;
    }> = withChildSessionActivity([
      { sessionId: "parent", parentSessionId: null, busy: false },
      { sessionId: "delegate", parentSessionId: "parent", busy: false },
    ]);

    expect(rows.find((r) => r.sessionId === "parent")).toMatchObject({ busy: false });
    expect(rows.find((r) => r.sessionId === "parent")?.runningChildSessionCount).toBeUndefined();
  });

  test("a row claiming itself as parent cannot count itself as its own child", () => {
    const input: Array<{
      sessionId: string;
      parentSessionId: string | null;
      busy: boolean;
      runningChildSessionCount?: number;
    }> = [{ sessionId: "loop", parentSessionId: "loop", busy: true }];

    const rows = withChildSessionActivity(input);

    expect(rows[0].runningChildSessionCount).toBeUndefined();
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

    const [session] = await listSubagentSessions(
      f.parent,
      Date.parse("2026-08-20T04:05:00.000Z"),
    );

    expect(session.status).toBe("running");
    expect(session.finishedAt).toBeNull();
    expect(session.lastActivityAt).toBe(Date.parse("2026-08-20T04:04:00.000Z"));
  });

  // The child's own transcript is the authority on whether it is working. The
  // parent's lifecycle record only stands while the child has been silent
  // since it: a SendMessage resume writes `{resumedAgentId}` to the parent,
  // which no lifecycle reader understood, so a resumed verifier read
  // "completed" from its first notification while it worked for 15 minutes
  // (2026-10-16).
  function append(transcript: string, ...rows: unknown[]): void {
    writeFileSync(transcript, readFileSync(transcript, "utf8") + rows.map(line).join(""));
  }

  function endTurn(text: string, timestamp: string) {
    return {
      type: "assistant",
      timestamp,
      message: { role: "assistant", stop_reason: "end_turn", content: [{ type: "text", text }] },
    };
  }

  test("a resumed child reads running from its own transcript, whatever the parent last said", async () => {
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "resumed-verifier",
      toolUseId: "tool-verifier",
      description: "Verify the session view",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript, endTurn("PARTIAL: could not fetch the board", "2026-08-20T04:03:00.000Z"));
    writeFileSync(f.parent, [
      launch("tool-verifier", "Verify the session view", "2026-08-20T04:01:00.000Z"),
      notification("resumed-verifier", "tool-verifier", "completed", "2026-08-20T04:03:01.000Z"),
      // What SendMessage writes: no agentId, no status.
      line({
        type: "user",
        timestamp: "2026-08-20T04:05:00.000Z",
        toolUseResult: { success: true, message: "Resuming agent", resumedAgentId: "resumed-verifier" },
        message: { content: [{ type: "tool_result", tool_use_id: "tool-send", content: "ok" }] },
      }),
    ].join(""));
    append(transcript,
      { type: "user", timestamp: "2026-08-20T04:05:00.000Z", message: { role: "user", content: "The coordinator sent a message while you were working:\nThe board is ready." } },
      { type: "assistant", timestamp: "2026-08-20T04:06:00.000Z", message: { role: "assistant", stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "Bash", input: {} }] } },
      { type: "user", timestamp: "2026-08-20T04:06:05.000Z", message: { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "ok" }] } },
    );

    const [working] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:07:00.000Z"));
    expect(working.status).toBe("running");
    expect(working.finishedAt).toBeNull();
    expect(working.result).toBeNull();
    expect(withSessionWorkActivity({ busy: false }, [working], 0)).toMatchObject({
      busy: true,
      runningChildAgentCount: 1,
    });

    // It finishes again before the second notification lands: done at once.
    append(transcript, endTurn("PASS on every property", "2026-08-20T04:08:00.000Z"));
    const [done] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:08:30.000Z"));
    expect(done.status).toBe("completed");
    expect(done.finishedAt).toBe(Date.parse("2026-08-20T04:08:00.000Z"));
    expect(done.result).toBe("PASS on every property");

    // The notification that follows agrees and owns the finish time.
    writeFileSync(f.parent, readFileSync(f.parent, "utf8")
      + notification("resumed-verifier", "tool-verifier", "completed", "2026-08-20T04:08:01.000Z"));
    const [notified] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:09:00.000Z"));
    expect(notified.status).toBe("completed");
    expect(notified.finishedAt).toBe(Date.parse("2026-08-20T04:08:01.000Z"));
  });

  test("a child whose turn ended reads completed before the parent's notification lands", async () => {
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "quick",
      toolUseId: "tool-quick",
      description: "Count callers",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript, endTurn("Found 6 callers", "2026-08-20T04:03:00.000Z"));
    writeFileSync(f.parent, [
      launch("tool-quick", "Count callers", "2026-08-20T04:01:00.000Z"),
      line({
        type: "user",
        timestamp: "2026-08-20T04:01:01.000Z",
        toolUseResult: { isAsync: true, status: "async_launched", agentId: "quick" },
        message: { content: [{ type: "tool_result", tool_use_id: "tool-quick", content: "launched" }] },
      }),
    ].join(""));

    const [session] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:03:10.000Z"));

    expect(session.status).toBe("completed");
    expect(session.finishedAt).toBe(Date.parse("2026-08-20T04:03:00.000Z"));
    expect(session.result).toBe("Found 6 callers");
  });

  test("a system notification delivered into a finished child is not work until it answers", async () => {
    // Four real children got a background-task notice a day after they
    // finished and never ran again.
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "noticed",
      toolUseId: "tool-noticed",
      description: "Scrape posts",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript, endTurn("Zeta has 199 posts", "2026-08-20T04:03:00.000Z"));
    writeFileSync(f.parent, [
      launch("tool-noticed", "Scrape posts", "2026-08-20T04:01:00.000Z"),
      notification("noticed", "tool-noticed", "completed", "2026-08-20T04:03:01.000Z"),
    ].join(""));
    append(transcript,
      {
        type: "user",
        timestamp: "2026-08-21T19:30:05.000Z",
        message: { role: "user", content: "[SYSTEM NOTIFICATION - NOT USER INPUT]\n<task-notification>\n<status>completed</status>\n</task-notification>" },
      },
      { type: "attachment", timestamp: "2026-08-21T19:30:05.000Z", attachment: { type: "date" } },
    );

    const [idle] = await listSubagentSessions(f.parent, Date.parse("2026-08-21T19:31:00.000Z"));
    expect(idle.status).toBe("completed");

    // If it does answer, it is working again.
    append(transcript, {
      type: "assistant",
      timestamp: "2026-08-21T19:31:10.000Z",
      message: { role: "assistant", stop_reason: null, content: [{ type: "thinking", thinking: "" }] },
    });
    const [answering] = await listSubagentSessions(f.parent, Date.parse("2026-08-21T19:31:20.000Z"));
    expect(answering.status).toBe("running");
  });

  test("an interrupted child reads stopped without a parent notification", async () => {
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "cut",
      toolUseId: "tool-cut",
      description: "Long sweep",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript, {
      type: "user",
      timestamp: "2026-08-20T04:03:00.000Z",
      message: { role: "user", content: [{ type: "text", text: "[Request interrupted by user for tool use]" }] },
    });
    writeFileSync(f.parent, launch("tool-cut", "Long sweep", "2026-08-20T04:01:00.000Z"));

    const [session] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:04:00.000Z"));

    expect(session.status).toBe("stopped");
    expect(session.finishedAt).toBe(Date.parse("2026-08-20T04:03:00.000Z"));
  });

  test("a child that ended its turn while its own background command runs is still working", async () => {
    // Live probe 2026-10-16: a resumed child pushed `sleep 90` to the
    // background and ended its turn; Claude Code notified "completed — stopped
    // with background work of its own still running" and resumed it 87s later.
    const f = fixture();
    const outputFile = join(f.dir, "child-shell.output");
    const transcript = child(f.sidecars, {
      id: "waiting",
      toolUseId: "tool-waiting",
      description: "Wait for the build",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript,
      {
        type: "user",
        timestamp: "2026-08-20T04:02:30.000Z",
        toolUseResult: { backgroundTaskId: "child-shell" },
        message: {
          role: "user",
          content: [{ type: "tool_result", content: `Command running in background with ID: child-shell. Output is being written to: ${outputFile}` }],
        },
      },
      endTurn("Waiting for the build to finish...", "2026-08-20T04:03:00.000Z"),
    );
    writeFileSync(f.parent, [
      launch("tool-waiting", "Wait for the build", "2026-08-20T04:01:00.000Z"),
      notification("waiting", "tool-waiting", "completed", "2026-08-20T04:03:01.000Z"),
    ].join(""));
    const at = Date.parse("2026-08-20T04:04:00.000Z");

    const [waiting] = await listSubagentSessions(f.parent, at, () => new Set([outputFile]));
    expect(waiting.status).toBe("running");
    expect(waiting.finishedAt).toBeNull();
    expect(waiting.result).toBeNull();

    // Its command exits (output file closed): done.
    resetSubagentCacheForTests();
    const [exited] = await listSubagentSessions(f.parent, at, () => new Set());
    expect(exited.status).toBe("completed");

    // The command's notice lands in the child: no candidates left, no probe.
    append(transcript, {
      type: "user",
      timestamp: "2026-08-20T04:05:00.000Z",
      message: {
        role: "user",
        content: "[SYSTEM NOTIFICATION - NOT USER INPUT]\n<task-notification>\n<task-id>child-shell</task-id>\n<status>completed</status>\n</task-notification>",
      },
    });
    let probed = false;
    const [notified] = await listSubagentSessions(f.parent, at, () => {
      probed = true;
      return new Set([outputFile]);
    });
    expect(notified.status).toBe("completed");
    expect(probed).toBe(false);
  });

  test("a notification is dated when it was queued, not when it was delivered", async () => {
    // The parent records each notification twice: queue-operation enqueue,
    // then remove when it reaches the model. A remove after a resume must not
    // re-date the old "completed" past the resumed child's turn.
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "redated",
      toolUseId: "tool-redated",
      description: "Verify again",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    append(transcript,
      endTurn("first pass", "2026-08-20T04:03:00.000Z"),
      { type: "user", timestamp: "2026-08-20T04:05:00.000Z", message: { role: "user", content: "The coordinator sent a message while you were working:\nagain" } },
    );
    const removed = JSON.parse(notification("redated", "tool-redated", "completed", "2026-08-20T04:05:30.000Z"));
    removed.operation = "remove";
    writeFileSync(f.parent, [
      launch("tool-redated", "Verify again", "2026-08-20T04:01:00.000Z"),
      notification("redated", "tool-redated", "completed", "2026-08-20T04:03:01.000Z"),
      line(removed),
    ].join(""));

    const [session] = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:06:00.000Z"));

    expect(session.status).toBe("running");
  });

  test("a synchronous subagent's tool_result completion terminates its status", async () => {
    // Claude Code writes <task-notification> rows only for ASYNC agent
    // launches. A foreground Agent call records its completion solely as the
    // tool_result's toolUseResult — before bug 010 that row was filtered out
    // and the child read "running" forever, latching the parent busy.
    const f = fixture();
    child(f.sidecars, {
      id: "sync-child",
      toolUseId: "tool-sync",
      description: "Sync explore",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    writeFileSync(f.parent, [
      launch("tool-sync", "Sync explore", "2026-08-20T04:01:00.000Z"),
      line({
        type: "user",
        timestamp: "2026-08-20T04:03:00.000Z",
        toolUseResult: {
          status: "completed",
          agentId: "sync-child",
          agentType: "Explore",
          totalDurationMs: 120_000,
        },
        message: {
          content: [{ type: "tool_result", tool_use_id: "tool-sync", content: "done" }],
        },
      }),
    ].join(""));

    const [session] = await listSubagentSessions(
      f.parent,
      Date.parse("2026-08-20T04:04:00.000Z"),
    );

    expect(session.status).toBe("completed");
    expect(session.finishedAt).toBe(Date.parse("2026-08-20T04:03:00.000Z"));
  });

  test("an async launch receipt leaves the child running until it actually finishes", async () => {
    // A BACKGROUND Agent launch records `{agentId, status: "async_launched"}`
    // in the very same toolUseResult shape a synchronous completion uses. Read
    // as a lifecycle it maps to "unknown", so every live background agent was
    // reported finished the moment it started: runningChildAgentCount 0, the
    // parent idle while three agents worked, and nothing to nest in the client.
    const f = fixture();
    child(f.sidecars, {
      id: "async-child",
      toolUseId: "tool-async",
      description: "Evidence sweep",
      lastTimestamp: "2026-08-20T04:04:00.000Z",
    });
    writeFileSync(f.parent, [
      launch("tool-async", "Evidence sweep", "2026-08-20T04:01:00.000Z"),
      line({
        type: "user",
        timestamp: "2026-08-20T04:02:00.000Z",
        toolUseResult: {
          isAsync: true,
          status: "async_launched",
          agentId: "async-child",
          description: "Evidence sweep",
        },
        message: {
          content: [{ type: "tool_result", tool_use_id: "tool-async", content: "launched" }],
        },
      }),
    ].join(""));

    const [running] = await listSubagentSessions(
      f.parent,
      Date.parse("2026-08-20T04:05:00.000Z"),
    );
    expect(running.status).toBe("running");
    expect(running.finishedAt).toBeNull();
    expect(withSessionWorkActivity({ busy: false }, [running], 0)).toMatchObject({
      busy: true,
      runningChildAgentCount: 1,
    });

    // The real outcome still arrives as a notification and must win.
    const g = fixture();
    child(g.sidecars, {
      id: "async-child",
      toolUseId: "tool-async",
      description: "Evidence sweep",
      lastTimestamp: "2026-08-20T04:04:00.000Z",
    });
    writeFileSync(g.parent, [
      launch("tool-async", "Evidence sweep", "2026-08-20T04:01:00.000Z"),
      line({
        type: "user",
        timestamp: "2026-08-20T04:02:00.000Z",
        toolUseResult: { isAsync: true, status: "async_launched", agentId: "async-child" },
        message: {
          content: [{ type: "tool_result", tool_use_id: "tool-async", content: "launched" }],
        },
      }),
      notification("async-child", "tool-async", "completed", "2026-08-20T04:06:00.000Z"),
    ].join(""));

    const [finished] = await listSubagentSessions(
      g.parent,
      Date.parse("2026-08-20T04:07:00.000Z"),
    );
    expect(finished.status).toBe("completed");
    expect(finished.finishedAt).toBe(Date.parse("2026-08-20T04:06:00.000Z"));
  });

  test("a running child with no completion record and no recent activity degrades to unknown", async () => {
    // Parent killed mid-agent: no notification and no tool_result will ever
    // arrive, so without a clock backstop the child latches "running" across
    // every /resume. The stale read must also flip WITHOUT a file change —
    // i.e. through the sidecar cache — so read once fresh, then again stale.
    const f = fixture();
    child(f.sidecars, {
      id: "orphan",
      toolUseId: "tool-orphan",
      description: "Orphaned agent",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    writeFileSync(f.parent, launch("tool-orphan", "Orphaned agent", "2026-08-20T04:01:00.000Z"));

    const fresh = await listSubagentSessions(f.parent, Date.parse("2026-08-20T04:10:00.000Z"));
    expect(fresh[0].status).toBe("running");

    const stale = await listSubagentSessions(f.parent, Date.parse("2026-08-20T05:00:00.000Z"));
    expect(stale[0].status).toBe("unknown");
    expect(stale[0].finishedAt).toBeNull();
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
      "result", "spawnDepth", "startedAt", "status",
    ]);
  });

  // S2 Subagents sheet (B8): a finished subagent's row shows the first line of
  // its final report ("Found 6 callers in 4 files"). The report is the child's
  // last assistant text; markdown marks go, and the line is capped.
  test("a finished child carries the first line of its final report as its result", async () => {
    const f = fixture();
    const transcript = child(f.sidecars, {
      id: "done",
      toolUseId: "tool-done",
      description: "Find every fork caller",
      lastTimestamp: "2026-08-20T04:02:00.000Z",
    });
    writeFileSync(transcript, readFileSync(transcript, "utf8") + line({
      type: "assistant",
      timestamp: "2026-08-20T04:03:00.000Z",
      message: { role: "assistant", content: [{ type: "text", text: "## **Found 6 callers** in 4 files\n\nDetails follow." }] },
    }));
    writeFileSync(f.parent, [
      launch("tool-done", "Find every fork caller", "2026-08-20T04:01:00.000Z"),
      notification("done", "tool-done", "completed", "2026-08-20T04:04:00.000Z"),
    ].join(""));

    const [session] = await listSubagentSessions(f.parent);

    expect(session.result).toBe("Found 6 callers in 4 files");
    expect(JSON.stringify(session)).not.toContain("Details follow");
  });

  test("a running child has no result yet", async () => {
    const f = fixture();
    child(f.sidecars, {
      id: "live",
      toolUseId: "tool-live",
      description: "Check the desktop fork menu",
      lastTimestamp: new Date().toISOString(),
    });
    writeFileSync(f.parent, launch("tool-live", "Check the desktop fork menu", "2026-08-20T04:01:00.000Z"));

    const [session] = await listSubagentSessions(f.parent);

    expect(session.status).toBe("running");
    expect(session.result).toBeNull();
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
