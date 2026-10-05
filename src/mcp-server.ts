// A minimal MCP server (Streamable HTTP transport, stateless) that lets a remote
// assistant — Grok Bot, through a custom MCP server entry — see and drive lfg
// sessions. The tools themselves live in `mcp-lfg-tools.ts`.
//
// It runs as its own process (`scripts/lfg-mcp.ts`) behind its own tunnel, and
// reaches lfg only through the loopback HTTP API. The tunnel routes nothing but
// this process, so a policy mistake on that hostname cannot expose the full API.
//
// Transport: every client message is a POST of one JSON-RPC message. Requests get
// an `application/json` reply; notifications get 202 with no body. There is no
// server-initiated stream, so GET/DELETE are 405 (the spec allows both).

export const SUPPORTED_PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"] as const;

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type JsonRpcId = string | number | null;
type JsonRpcMessage = { jsonrpc?: string; id?: JsonRpcId; method?: string; params?: Record<string, unknown> };

export type ToolContent = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };
export type ToolResult = { content: ToolContent[]; isError?: boolean };

export type McpTool = {
  name: string;
  description: string;
  inputSchema: { type: "object"; properties?: Record<string, Json>; required?: string[] };
  annotations?: { title?: string; readOnlyHint?: boolean; destructiveHint?: boolean; idempotentHint?: boolean; openWorldHint?: boolean };
  run: (args: Record<string, unknown>) => Promise<ToolResult>;
};

export type McpServerOptions = {
  name: string;
  version: string;
  instructions?: string;
  tools: McpTool[];
  log?: (line: string) => void;
};

export const text = (t: string, isError = false): ToolResult => ({ content: [{ type: "text", text: t }], ...(isError ? { isError } : {}) });

function rpcResult(id: JsonRpcId, result: Json | Record<string, unknown>) {
  return { jsonrpc: "2.0", id, result };
}

function rpcError(id: JsonRpcId, code: number, message: string) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export function createMcpHandler(opts: McpServerOptions): (req: Request) => Promise<Response> {
  const byName = new Map(opts.tools.map((t) => [t.name, t]));
  const log = opts.log ?? (() => {});

  async function handleOne(msg: JsonRpcMessage): Promise<object | null> {
    const id = msg.id ?? null;
    const isNotification = msg.id === undefined;
    if (msg.jsonrpc !== "2.0" || typeof msg.method !== "string") {
      // A response to a server request (we send none) or garbage. Either way, nothing to answer.
      return isNotification ? null : rpcError(id, -32600, "invalid request");
    }
    log(`rpc ${msg.method}${isNotification ? " (notification)" : ""}`);
    if (isNotification) return null; // notifications/initialized, notifications/cancelled, …

    switch (msg.method) {
      case "initialize": {
        const asked = String(msg.params?.protocolVersion ?? "");
        const client = msg.params?.clientInfo as { name?: string; version?: string } | undefined;
        log(`client ${client?.name ?? "unknown"} ${client?.version ?? ""} asked protocol ${asked || "(none)"}`);
        const protocolVersion = (SUPPORTED_PROTOCOL_VERSIONS as readonly string[]).includes(asked)
          ? asked
          : SUPPORTED_PROTOCOL_VERSIONS[0];
        return rpcResult(id, {
          protocolVersion,
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: opts.name, version: opts.version },
          ...(opts.instructions ? { instructions: opts.instructions } : {}),
        });
      }
      case "ping":
        return rpcResult(id, {});
      case "tools/list":
        return rpcResult(id, {
          tools: opts.tools.map(({ run: _run, ...t }) => t),
        });
      case "tools/call": {
        const name = String(msg.params?.name ?? "");
        const tool = byName.get(name);
        if (!tool) return rpcError(id, -32602, `unknown tool: ${name}`);
        const args = (msg.params?.arguments ?? {}) as Record<string, unknown>;
        const started = Date.now();
        // The args are the audit trail of what a remote assistant asked this Mac to do.
        const argSummary = JSON.stringify(args).slice(0, 300);
        try {
          const result = await tool.run(args);
          log(`tool ${name} ${result.isError ? "error" : "ok"} ${Date.now() - started}ms ${argSummary}`);
          return rpcResult(id, result);
        } catch (e) {
          log(`tool ${name} threw ${Date.now() - started}ms ${argSummary}: ${(e as Error).message}`);
          // Tool failures are results the model can read, not protocol errors.
          return rpcResult(id, text(`${name} failed: ${(e as Error).message}`, true));
        }
      }
      default:
        return rpcError(id, -32601, `method not found: ${msg.method}`);
    }
  }

  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return new Response("method not allowed", { status: 405, headers: { allow: "POST" } });
    }
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(rpcError(null, -32700, "parse error"), 400);
    }
    if (Array.isArray(body)) {
      // Batches were dropped in 2025-06-18 but older clients may still send them.
      const replies = (await Promise.all(body.map((m) => handleOne(m as JsonRpcMessage)))).filter(Boolean);
      return replies.length ? jsonResponse(replies) : new Response(null, { status: 202 });
    }
    const reply = await handleOne(body as JsonRpcMessage);
    return reply ? jsonResponse(reply) : new Response(null, { status: 202 });
  };
}
