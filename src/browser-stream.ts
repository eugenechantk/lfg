import { existsSync } from "node:fs";
import { resolve } from "node:path";

export type StreamCommand = Record<string, any> & { type: string };
const specialKeys = new Set(["enter", "tab", "backspace", "escape", "left", "right", "up", "down", "selectAll"]);
const integer = (x: unknown) => Number.isSafeInteger(x) && (x as number) > 0;
const unit = (x: unknown) => typeof x === "number" && Number.isFinite(x) && x >= 0 && x <= 1;
export function parseStreamCommand(raw: string): StreamCommand | null {
  if (Buffer.byteLength(raw) > 8192) return null;
  try {
    const c = JSON.parse(raw);
    if (!c || Array.isArray(c)) return null;
    if (c.type === "ping") return {type:"ping"};
    if (c.type === "ack" && integer(c.frameId)) return {type:"ack",frameId:c.frameId};
    if (c.type === "select" && integer(c.windowId)) return {type:"select",windowId:c.windowId};
    if (c.type === "control" && typeof c.enabled === "boolean") return {type:"control",enabled:c.enabled};
    if (!integer(c.seq) || !integer(c.frameId)) return null;
    const base = {type:c.type,seq:c.seq,frameId:c.frameId};
    if (c.type === "text" && typeof c.text === "string" && c.text.length > 0 && Buffer.byteLength(c.text) <= 4096)
      return {...base,text:c.text};
    if (c.type === "key" && specialKeys.has(c.key)) return {...base,key:c.key};
    if (c.type === "pointer" && unit(c.x) && unit(c.y) && ["move","down","up"].includes(c.action) && [undefined,"left","right"].includes(c.button))
      return {...base,x:c.x,y:c.y,action:c.action,button:c.button ?? "left"};
    if (c.type === "scroll" && unit(c.x) && unit(c.y) && typeof c.dy === "number" && Number.isFinite(c.dy) && Math.abs(c.dy) <= 1000)
      return {...base,x:c.x,y:c.y,dy:c.dy};
    return null;
  } catch { return null; }
}

export class StreamProtocol {
  private controlling = false;
  private sequence = 0;
  private frameID = 0;
  frame(id: number) { this.frameID = id; }
  accept(c: StreamCommand): boolean {
    if (c.type === "select") { this.controlling = false; this.frameID = 0; return true; }
    if (c.type === "control") { this.controlling = c.enabled && this.frameID > 0; return true; }
    if (c.type === "ping" || c.type === "ack") return true;
    if (!this.controlling || c.seq <= this.sequence || c.frameId !== this.frameID) return false;
    this.sequence = c.seq;
    return true;
  }
}

type Socket = {send(data: string): number; close(code?: number, reason?: string): void};
type Helper = {write(command: StreamCommand): void; stop(): void};
type Factory = (output: (line: string) => void, exit: () => void) => Helper;
export function streamHelperPath(): string {
  return process.env.LFG_STREAM_HELPER ?? resolve(import.meta.dir, "../desktop/stream-host/build/Build/Products/Debug/LFGStreamHost.app/Contents/MacOS/LFGStreamHost");
}
function spawnHelper(output: (line: string) => void, exit: () => void): Helper {
  const path = streamHelperPath();
  if (!existsSync(path)) throw new Error("Browser Stream is not installed on this Mac yet.");
  const child = Bun.spawn([path, "--stdio"], {stdin:"pipe",stdout:"pipe",stderr:"ignore"});
  let stopped = false;
  void (async () => {
    const reader = child.stdout.getReader();
    const decoder = new TextDecoder();
    let pending = "";
    try {
      while (!stopped) {
        const {value,done} = await reader.read();
        if (done) break;
        pending += decoder.decode(value,{stream:true});
        if (pending.length > 4 * 1024 * 1024) throw new Error("oversized helper output");
        let i: number;
        while ((i = pending.indexOf("\n")) >= 0) {
          const line = pending.slice(0,i); pending = pending.slice(i+1);
          if (!stopped) output(line);
        }
      }
    } catch {} finally { if (!stopped) { child.kill(); exit(); } }
  })();
  return {
    write(command) { if (!stopped) child.stdin.write(JSON.stringify(command)+"\n"); },
    stop() {
      stopped = true; child.stdin.end(); child.kill();
      // Give the main-actor shutdown a chance to release held buttons, but don't
      // leave a hung capture process behind if WindowServer stops responding.
      setTimeout(() => { if (child.exitCode === null) child.kill("SIGKILL"); }, 1500);
    },
  };
}

/** One helper/controller per host. Neither frames nor input enter the journal. */
export class BrowserStreamBridge {
  private owner?: Socket;
  private helper?: Helper;
  private protocol = new StreamProtocol();
  private timer?: ReturnType<typeof setInterval>;
  private lastSeen = 0;
  private rateStart = 0;
  private rateBytes = 0;
  private rateCount = 0;
  constructor(private factory: Factory = spawnHelper) {}
  open(socket: Socket): boolean {
    if (this.owner) {
      socket.send(JSON.stringify({type:"error",message:"Another device is using Browser Stream on this Mac."}));
      socket.close(1008,"Already in use"); return false;
    }
    this.owner = socket; this.protocol = new StreamProtocol(); this.lastSeen = Date.now();
    try {
      this.helper = this.factory(line => {
        if (this.owner !== socket) return;
        try {
          const message = JSON.parse(line);
          if (message.type === "frame") this.protocol.frame(message.frameId);
          if (message.type === "control") this.protocol.accept(message);
          socket.send(line);
        } catch { this.close(socket); socket.close(1011,"Invalid helper output"); }
      }, () => {
        socket.send(JSON.stringify({type:"error",message:"The Mac stream helper stopped. Reconnect to retry."}));
        this.close(socket); socket.close(1011,"Helper stopped");
      });
      this.timer = setInterval(() => {
        if (Date.now() - this.lastSeen > 15000) { this.close(socket); socket.close(1001,"Connection expired"); }
      }, 5000);
      return true;
    } catch (error) {
      socket.send(JSON.stringify({type:"error",message:(error as Error).message}));
      this.close(socket); socket.close(1011,"Helper unavailable"); return false;
    }
  }
  message(socket: Socket, raw: string | Uint8Array) {
    if (this.owner !== socket || typeof raw !== "string") return;
    const now = Date.now();
    if (now - this.rateStart >= 1000) { this.rateStart = now; this.rateBytes = 0; this.rateCount = 0; }
    this.rateBytes += Buffer.byteLength(raw); this.rateCount++;
    if (this.rateCount > 120 || this.rateBytes > 32768) {
      this.close(socket); socket.close(1008,"Input rate exceeded"); return;
    }
    const command = parseStreamCommand(raw);
    if (!command) { socket.send(JSON.stringify({type:"error",message:"Invalid remote input."})); return; }
    this.lastSeen = Date.now();
    if (command.type === "ping") { socket.send('{"type":"pong"}'); return; }
    if (!this.protocol.accept(command)) return;
    this.helper?.write(command);
  }
  close(socket: Socket) {
    if (this.owner !== socket) return;
    this.owner = undefined;
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.helper?.stop(); this.helper = undefined;
  }
}
