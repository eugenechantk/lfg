import { join } from "node:path";
import { existsSync } from "node:fs";

function cuaExecutable() {
  if (process.env.LFG_CUA_BIN) return process.env.LFG_CUA_BIN;
  return [
    join(import.meta.dir, "../.codex/tools/cua/Applications/Cua Spaces.app/Contents/MacOS/cua"),
    "/Applications/Cua Spaces.app/Contents/MacOS/cua",
    join(process.env.HOME || "", "Applications/Cua Spaces.app/Contents/MacOS/cua"),
    join(import.meta.dir, "../.codex/tools/cua/bin/cua"),
  ].find(existsSync) || "cua";
}

export interface CuaTools { call(name: string, args: Record<string, unknown>): Promise<any> }

/** One MCP connection per host process. Never retries an uncertain mutation. */
export class CuaMCP implements CuaTools {
  private process?: ReturnType<typeof Bun.spawn>;
  private ready?: Promise<void>;
  private nextID = 0;
  private pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  constructor(private executable = cuaExecutable()) {}
  private async connect() {
    if (this.ready) return this.ready;
    this.ready = (async () => {
      try {
        const child = Bun.spawn([this.executable, "daemon", "mcp"], {
          stdin: "pipe", stdout: "pipe", stderr: "ignore",
          env: { ...process.env, DO_NOT_TRACK: "1" },
        });
        this.process = child;
        void this.read(child);
        await this.request("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "lfg", version: "1" } }, 30_000);
        (child.stdin as any).write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
      } catch (error) { this.close(); throw error; }
    })();
    return this.ready;
  }
  private async read(child: ReturnType<typeof Bun.spawn>) {
    let buffer = "";
    const decoder = new TextDecoder();
    try {
      for await (const chunk of child.stdout as any) {
        buffer += decoder.decode(chunk, { stream: true });
        if (buffer.length > 32 * 1024 * 1024) throw Error("Cua response exceeded the size limit");
        let end: number;
        while ((end = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
          if (!line.trim()) continue;
          const message = JSON.parse(line);
          const entry = this.pending.get(message.id);
          if (!entry) continue;
          clearTimeout(entry.timer); this.pending.delete(message.id);
          if (message.error) entry.reject(Error(message.error.message || "Cua request failed"));
          else entry.resolve(message.result);
        }
      }
    } catch {} finally {
      if (this.process === child) this.close();
    }
  }
  private request(method: string, params: unknown, timeout: number): Promise<any> {
    const child = this.process;
    if (!child) return Promise.reject(Error("Cua CLI is unavailable. Install Cua on this host or set LFG_CUA_BIN."));
    const id = ++this.nextID;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Error("Cua did not confirm the operation. Refresh its state before trying again; it may still be running."));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      try { (child.stdin as any).write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"); }
      catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  async call(name: string, args: Record<string, unknown>) {
    await this.connect();
    const result = await this.request("tools/call", { name, arguments: args }, name === "create_space" ? 660_000 : name === "agent_start" ? 180_000 : 60_000);
    const content = result?.content ?? [];
    const text = content.filter((part: any) => part.type === "text").map((part: any) => part.text).join("\n");
    if (result?.isError) throw Error(text || "Cua rejected the operation");
    if (result?.structuredContent !== undefined) {
      const value = result.structuredContent;
      return value && typeof value === "object" && !Array.isArray(value) && content.some((p: any) => p.type === "image")
        ? { ...value, content } : value;
    }
    try { return JSON.parse(text); } catch { return { text, content }; }
  }
  close() {
    const child = this.process; this.process = undefined; this.ready = undefined;
    for (const entry of this.pending.values()) { clearTimeout(entry.timer); entry.reject(Error("Cua connection closed. Refresh state before repeating an operation.")); }
    this.pending.clear();
    child?.kill();
  }
}
