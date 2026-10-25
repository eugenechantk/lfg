import { mkdir, readFile, readdir, rename, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { TaskScheduler } from "./scheduled-tasks.ts";
import { parseTaskOutcome } from "./scheduled-task-outcome.ts";

type ReviewEvent = { id: string; sessionId: string; event: "Stop" | "SessionEnd"; at: number;
  notBefore?: number | null; expectedVerdict?: string | null; attempts?: number; nextAt?: number };
const TTL = 10 * 60_000;

/** Hooks enqueue immutable events; retries and receipts survive host restarts. */
export class TaskPostReviewQueue {
  private draining = false;
  constructor(private runtime: TaskScheduler, readonly root: string, private now = () => Date.now()) {}
  private async write(path: string, value: unknown) {
    const temp = `${path}.${crypto.randomUUID()}.tmp`;
    await writeFile(temp, JSON.stringify(value) + "\n", { mode: 0o600 });
    await rename(temp, path);
  }
  private async finish(name: string, event: ReviewEvent, result: Record<string, unknown>) {
    await mkdir(join(this.root, "results"), { recursive: true });
    await this.write(join(this.root, "results", name), { eventId: event.id, sessionId: event.sessionId,
      event: event.event, queuedAt: event.at, reviewedAt: this.now(), ...result });
    await unlink(join(this.root, name));
  }
  async drain() {
    if (this.draining) return;
    this.draining = true;
    try {
      let files;
      try { files = await readdir(this.root, { withFileTypes: true }); }
      catch (e: any) { if (e.code === "ENOENT") return; throw e; }
      let eligible = 0;
      for (const file of files.filter(f => f.isFile() && f.name.endsWith(".json"))) {
        const path = join(this.root, file.name);
        let event: ReviewEvent;
        try { event = JSON.parse(await readFile(path, "utf8")); } catch { continue; }
        if (!event || typeof event.sessionId !== "string" || typeof event.id !== "string" ||
            !["Stop", "SessionEnd"].includes(event.event) || !Number.isFinite(event.at)) {
          await this.finish(file.name, event ?? {} as ReviewEvent, { status: "needs_review", error: "Invalid hook event." });
          continue;
        }
        if (this.now() < Math.max(event.at + 5000, event.nextAt ?? 0)) continue;
        if (eligible++ >= 50) break;
        const state = await this.runtime.store.read();
        const matches = state.runs.filter(r => r.sessionId === event.sessionId);
        // A very short task can stop before launch() persists its session binding.
        if (matches.length === 0) {
          if (this.now() - event.at >= TTL) await unlink(path);
          else await this.write(path, { ...event, nextAt: this.now() + 10_000 });
          continue;
        }
        const run = matches[0]!;
        if (matches.length !== 1 || !state.tasks.some(t => t.id === run.taskId)) {
          await this.finish(file.name, event, { status: "needs_review", error: "No unique saved task run for the source session." });
          continue;
        }
        const parsed = typeof event.expectedVerdict === "string" ? parseTaskOutcome(event.expectedVerdict, run.id) : undefined;
        const notBefore = typeof event.notBefore === "number" && Number.isFinite(event.notBefore) ? event.notBefore : undefined;
        if ((event.expectedVerdict && !parsed?.outcome) || (!parsed?.outcome && notBefore == null)) {
          await this.finish(file.name, event, { status: "needs_review", runId: run.id, error: "Missing or invalid triggering-turn identity." });
          continue;
        }
        try {
          const result = await this.runtime.reviewOutcome(run.taskId, run.id, `Automatic post-session review (${event.event}).`,
            { verdictAtOrAfter: notBefore, outcome: parsed?.outcome });
          await this.finish(file.name, event, { status: "reviewed", runId: run.id, changed: result.changed });
        } catch (error) {
          if (this.now() - event.at >= TTL) {
            await this.finish(file.name, event, { status: "needs_review", runId: run.id, error: String(error) });
          } else {
            await this.write(path, { ...event, attempts: (event.attempts ?? 0) + 1, nextAt: this.now() + 10_000 });
          }
        }
      }
    } finally { this.draining = false; }
  }
  start(log: (message: string) => void = console.log) {
    let stopped = false, timer: ReturnType<typeof setTimeout>;
    const loop = async () => {
      try { await this.drain(); } catch (error) { log(`[task-post-review] ${error}`); }
      if (!stopped) timer = setTimeout(loop, 2000);
    };
    void loop();
    return () => { stopped = true; clearTimeout(timer); };
  }
}
