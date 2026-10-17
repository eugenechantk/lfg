import { describe, expect, test } from "bun:test";
import { parseThreadForkResponse, withCodexDaemonRequest } from "./codex-app-server.ts";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const source = "00000000-0000-4000-8000-000000000001";
const fork = "00000000-0000-4000-8000-000000000002";

test("native queue RPC uses the existing daemon's WebSocket control socket", async () => {
  const dir = mkdtempSync(join(tmpdir(), "lfg-codex-rpc-"));
  const socket = join(dir, "daemon.sock");
  const calls: any[] = [];
  const server = Bun.serve({
    unix: socket,
    fetch(request, server) { return server.upgrade(request) ? undefined : new Response("upgrade", { status: 400 }); },
    websocket: {
      message(ws, message) {
        const request = JSON.parse(String(message));
        calls.push(request);
        if (request.id == null) return;
        ws.send(JSON.stringify({ method: "thread/queue/changed", params: { threadId: "s" } }));
        ws.send(JSON.stringify({ id: request.id, result: request.method.endsWith("delete")
          ? { deleted: true } : { data: [], nextCursor: null } }));
      },
    },
  });
  try {
    const result = await withCodexDaemonRequest(async request => {
      expect(await request("thread/queue/list", { threadId: "s" })).toEqual({ data: [], nextCursor: null });
      return request("thread/queue/delete", { threadId: "s", queuedSubmissionId: "q" });
    }, `ws+unix://${socket}`);
    expect(result).toEqual({ deleted: true });
    expect(calls[0].params.capabilities.experimentalApi).toBe(true);
    expect(calls.map(x => x.method)).toEqual(["initialize", "initialized", "thread/queue/list", "thread/queue/delete"]);
  } finally {
    await server.stop(true);
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("Codex app-server thread fork", () => {
  test("accepts a distinct lineage-preserving fork id", () => {
    expect(parseThreadForkResponse({
      id: 2,
      result: { thread: { id: fork, forkedFromId: source } },
    }, source)).toBe(fork);
  });

  test("rejects errors, reused ids, and wrong lineage", () => {
    expect(() => parseThreadForkResponse({ id: 2, error: { message: "locked" } }, source))
      .toThrow("locked");
    expect(() => parseThreadForkResponse({
      id: 2,
      result: { thread: { id: source, forkedFromId: source } },
    }, source)).toThrow("distinct thread ID");
    expect(() => parseThreadForkResponse({
      id: 2,
      result: { thread: { id: fork, forkedFromId: "00000000-0000-4000-8000-000000000003" } },
    }, source)).toThrow("unexpected source");
  });
});
