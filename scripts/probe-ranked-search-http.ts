/** Isolated real HTTP route probe. Run with LFG_PORT set to a checked spare port. */
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const port = Number(process.env.LFG_PORT);
const keepServing = process.argv.includes("--serve");
if (!Number.isInteger(port) || port < 1024 || port === 8766)
  throw new Error("Set LFG_PORT to a checked spare port other than 8766");
const root = mkdtempSync(join(tmpdir(), "lfg-search-http-"));
const projects = join(root, "projects", "p");
const data = join(root, "data");
mkdirSync(projects, { recursive: true });
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "http-probe\n");
const old = { home: process.env.HOME, data: process.env.LFG_DATA,
  projects: process.env.LFG_CLAUDE_PROJECTS_DIR, host: process.env.LFG_HOST };
process.env.HOME = root;
process.env.LFG_DATA = data;
process.env.LFG_CLAUDE_PROJECTS_DIR = join(root, "projects");
process.env.LFG_HOST = "127.0.0.1";
for (let n = 1; n <= (keepServing ? 125 : 3); n++) {
  const sid = `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  writeFileSync(join(projects, `${sid}.jsonl`), [
    { type: "user", cwd: "/tmp/noto", message: { role: "user", content: n === 1 ? "ultramarine plan" : `ordinary ${n}` } },
    { type: "assistant", cwd: "/tmp/noto", message: { role: "assistant", content: `The ultramarine answer ${n}` } },
  ].map((row) => JSON.stringify(row)).join("\n") + "\n");
}
let server: Awaited<ReturnType<typeof import("../src/commands/serve")["cmdServe"]>> | null = null;
try {
  const { cmdServe } = await import("../src/commands/serve");
  server = await cmdServe({ backgroundTasks: false });
  const base = `http://127.0.0.1:${server.port}/api/sessions/search`;
  const firstResponse = await fetch(`${base}?q=ultramarine&limit=1`);
  const first = await firstResponse.json() as { sessions: Array<{ sessionId: string; lastUserText: string; searchMatched: boolean }>; nextCursor: string | null };
  if (!firstResponse.ok || first.sessions.length !== 1 || !first.nextCursor)
    throw new Error(`Bad first page: ${JSON.stringify(first)}`);
  const secondResponse = await fetch(`${base}?q=ultramarine&limit=1&cursor=${encodeURIComponent(first.nextCursor)}`);
  const second = await secondResponse.json() as typeof first;
  if (!secondResponse.ok || second.sessions.length !== 1 ||
      first.sessions[0].sessionId === second.sessions[0].sessionId ||
      !second.sessions[0].searchMatched)
    throw new Error(`Bad second page: ${JSON.stringify(second)}`);
  console.log(JSON.stringify({ status: "PASS", first: first.sessions[0], second: second.sessions[0],
    nextCursor: second.nextCursor }, null, 2));
  if (keepServing) {
    console.log(`Fixture host ready at http://127.0.0.1:${server.port}`);
    await new Promise<void>((resolve) => {
      process.once("SIGINT", () => resolve());
      process.once("SIGTERM", () => resolve());
    });
  }
} finally {
  server?.stop(true);
  if (old.home == null) delete process.env.HOME; else process.env.HOME = old.home;
  if (old.data == null) delete process.env.LFG_DATA; else process.env.LFG_DATA = old.data;
  if (old.projects == null) delete process.env.LFG_CLAUDE_PROJECTS_DIR; else process.env.LFG_CLAUDE_PROJECTS_DIR = old.projects;
  if (old.host == null) delete process.env.LFG_HOST; else process.env.LFG_HOST = old.host;
  rmSync(root, { recursive: true, force: true });
}
