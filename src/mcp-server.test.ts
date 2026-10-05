import { test, expect } from "bun:test";
import { createMcpHandler, type McpTool } from "./mcp-server.ts";

const echo: McpTool = {
  name: "echo",
  description: "echo",
  inputSchema: { type: "object", properties: { say: { type: "string" } } },
  run: async (args) => ({ content: [{ type: "text", text: String(args.say) }] }),
};
const boom: McpTool = {
  name: "boom",
  description: "throws",
  inputSchema: { type: "object" },
  run: async () => {
    throw new Error("kaput");
  },
};
const handler = createMcpHandler({ name: "t", version: "0.0.1", tools: [echo, boom] });

const post = (body: unknown) =>
  handler(new Request("http://x/mcp", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } }));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const call = async (body: unknown): Promise<any> => (await post(body)).json();

test("initialize echoes a supported protocol version and advertises tools", async () => {
  const res = await post({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
  const body = (await res.json()) as any;
  expect(res.headers.get("content-type")).toBe("application/json");
  expect(body.result.protocolVersion).toBe("2025-06-18");
  expect(body.result.capabilities.tools).toBeDefined();
  expect(body.result.serverInfo).toEqual({ name: "t", version: "0.0.1" });
});

test("initialize with an unknown version answers with the newest supported one", async () => {
  const body = await call({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "1999-01-01" } });
  expect(body.result.protocolVersion).toBe("2025-11-25");
});

test("notifications get 202 and no body", async () => {
  const res = await post({ jsonrpc: "2.0", method: "notifications/initialized" });
  expect(res.status).toBe(202);
  expect(await res.text()).toBe("");
});

test("tools/list hides the run function", async () => {
  const body = await call({ jsonrpc: "2.0", id: 2, method: "tools/list" });
  expect(body.result.tools.map((t: { name: string }) => t.name)).toEqual(["echo", "boom"]);
  expect(body.result.tools[0].run).toBeUndefined();
});

test("tools/call runs the tool; a throw becomes an isError result, not a protocol error", async () => {
  const ok = await call({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "echo", arguments: { say: "hi" } } });
  expect(ok.result.content[0].text).toBe("hi");
  const bad = await call({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "boom" } });
  expect(bad.result.isError).toBe(true);
  expect(bad.result.content[0].text).toContain("kaput");
  const unknown = await call({ jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "nope" } });
  expect(unknown.error.code).toBe(-32602);
});

test("unknown method, bad JSON, and non-POST", async () => {
  expect((await call({ jsonrpc: "2.0", id: 6, method: "resources/list" })).error.code).toBe(-32601);
  const parse = await handler(new Request("http://x/mcp", { method: "POST", body: "{" }));
  expect(parse.status).toBe(400);
  expect((await handler(new Request("http://x/mcp"))).status).toBe(405);
});

test("batches answer each request and skip notifications", async () => {
  const body = await call([
    { jsonrpc: "2.0", id: 7, method: "ping" },
    { jsonrpc: "2.0", method: "notifications/initialized" },
  ]);
  expect(body).toEqual([{ jsonrpc: "2.0", id: 7, result: {} }]);
});
