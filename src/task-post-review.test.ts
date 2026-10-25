import { afterEach, expect, test } from "bun:test";
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskStore } from "./scheduled-tasks.ts";
import { taskRuntime } from "./scheduled-task-api.ts";
import { TaskPostReviewQueue } from "./task-post-review.ts";

const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map(dir => rm(dir, { recursive: true, force: true }))); });

async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "task-post-review-")); dirs.push(dir);
  const queue = join(dir, "queue"); await mkdir(queue);
  const store = new TaskStore(join(dir, "tasks.json"));
  const task = await store.save({ name: "Fixture", prompt: "Useful work", cwd: dir, agent: "codex", enabled: false,
    schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } }, 1000);
  const run = (await store.claim(task.id, 2000, true))!;
  await store.record(run.id, { status: "incomplete", sessionId: "session", finishedAt: 5000,
    outcome: { status: "incomplete", summary: "Original judgment." }, summary: "Original report." });
  let now = 100_000, busy = false, messageAt = now, text = "", reads = 0;
  const block = (status = "completed", id = run.id) => `<lfg_task_result>${JSON.stringify({ run_id: id, status, summary: "Useful work verified." })}</lfg_task_result>`;
  text = block();
  const runtime = taskRuntime(store, async path => {
    if (path === "/api/sessions") return { sessions: [{ sessionId: "session", busy }] } as any;
    if (path.includes("/messages")) { reads++; return { messages: [{ role: "assistant", kind: "text", text, ts: messageAt }] } as any; }
    throw Error("Unexpected external action");
  }, () => now);
  const worker = () => new TaskPostReviewQueue(runtime, queue, () => now);
  async function enqueue(extra: Record<string, unknown> = {}) {
    const id = crypto.randomUUID(), name = `session.${id}.json`;
    await writeFile(join(queue, name), JSON.stringify({ id, sessionId: "session", event: "Stop", at: 100_000,
      notBefore: 99_000, expectedVerdict: block(), ...extra }));
    return name;
  }
  return { dir, queue, store, run, runtime, block, worker, enqueue,
    advance: (ms: number) => { now += ms; }, busy: (value: boolean) => { busy = value; },
    message: (value: string, at = now) => { text = value; messageAt = at; }, reads: () => reads,
    receipt: async (name: string) => JSON.parse(await readFile(join(queue, "results", name), "utf8")) };
}

test("Stop triggers an automatic late-outcome review without changing schedules or execution identity", async () => {
  const f = await fixture(), before = await f.store.read(), name = await f.enqueue();
  f.advance(6000); await f.worker().drain();
  const after = await f.store.read();
  expect(after.runs[0]!.status).toBe("succeeded"); expect(after.runs[0]!.outcomeReviews![0]!.previous.status).toBe("incomplete");
  expect(after.tasks).toEqual(before.tasks); expect(after.runs[0]!.finishedAt).toBe(5000);
  expect(await f.receipt(name)).toMatchObject({ status: "reviewed", changed: true, runId: f.run.id });
});

test("events wait for completion, source idleness and the final transcript; retries survive worker restart", async () => {
  const f = await fixture(), name = await f.enqueue();
  await f.worker().drain(); expect(f.reads()).toBe(0);
  f.advance(6000); f.busy(true); await f.worker().drain();
  expect((await f.store.read()).runs[0]!.status).toBe("incomplete");
  f.busy(false); f.message(f.block("incomplete"), 90_000); f.advance(30_000); await f.worker().drain();
  expect((await f.store.read()).runs[0]!.outcomeReviews).toBeUndefined();
  f.message(f.block()); f.advance(30_000); await f.worker().drain();
  expect((await f.receipt(name)).status).toBe("reviewed");
});

test("old verdicts cannot satisfy a new turn even if they contain a valid completed block", async () => {
  const f = await fixture(), name = await f.enqueue({ expectedVerdict: null });
  f.message(f.block(), 98_000); f.advance(6000); await f.worker().drain();
  expect((await f.store.read()).runs[0]!.status).toBe("incomplete");
  f.advance(600_000); await f.worker().drain();
  expect((await f.receipt(name)).status).toBe("needs_review");
  expect((await f.store.read()).runs[0]!.outcomeReviews).toBeUndefined();
});

test("duplicates are idempotent and SessionEnd works as a fallback", async () => {
  const f = await fixture(); const first = await f.enqueue(); const second = await f.enqueue({ event: "SessionEnd" });
  f.advance(6000); await f.worker().drain();
  expect((await f.store.read()).runs[0]!.outcomeReviews).toHaveLength(1);
  expect([(await f.receipt(first)).changed, (await f.receipt(second)).changed].sort()).toEqual([false, true]);
});

test("wrong-run, malformed and missing verdicts never alter outcomes; unrelated sessions are ignored", async () => {
  const f = await fixture(), before = await f.store.read();
  await f.enqueue({ sessionId: "unrelated", notBefore: null });
  await f.enqueue({ expectedVerdict: f.block("completed", "wrong-run") });
  f.message("No structured final verdict."); const name = await f.enqueue();
  f.advance(6000); await f.worker().drain();
  f.advance(600_000); await f.worker().drain();
  expect(await f.store.read()).toEqual(before); expect((await f.receipt(name)).status).toBe("needs_review");
});

test("the actual hook queues Stop and normal SessionEnd, preserving no-network lease behavior", async () => {
  const f = await fixture();
  const hook = join(import.meta.dir, "..", "scripts", "lfg-agent-hook.py");
  const fire = async (payload: unknown) => {
    const process = Bun.spawn(["python3", hook], { env: { ...Bun.env, LFG_AGENT_STATE_DIR: join(f.dir, "state"), LFG_TASK_REVIEW_QUEUE_DIR: f.queue },
      stdin: new TextEncoder().encode(JSON.stringify(payload)), stdout: "pipe", stderr: "pipe" });
    expect(await process.exited).toBe(0); expect(await new Response(process.stdout).text()).toBe("");
  };
  await fire({ session_id: "session", hook_event_name: "UserPromptSubmit", turn_id: "turn" });
  await fire({ session_id: "session", hook_event_name: "Stop", turn_id: "turn", last_assistant_message: f.block() });
  await fire({ session_id: "session", hook_event_name: "SessionEnd", reason: "other" });
  const files = (await readdir(f.queue)).filter(name => name.endsWith(".json")); expect(files).toHaveLength(2);
  const events = await Promise.all(files.map(name => readFile(join(f.queue, name), "utf8").then(JSON.parse)));
  expect(events.map(event => event.event).sort()).toEqual(["SessionEnd", "Stop"]);
  expect(events.find(event => event.event === "Stop").expectedVerdict).toBe(f.block());
  expect(events.find(event => event.event === "Stop").notBefore).toBeGreaterThan(0);
  await fire({ session_id: "session", hook_event_name: "SessionEnd", reason: "clear" });
  expect((await readdir(f.queue)).filter(name => name.endsWith(".json"))).toHaveLength(2);
});

test("a Stop event survives late persistence of its source session binding", async () => {
  const f = await fixture();
  await f.store.record(f.run.id, { sessionId: undefined });
  const name = await f.enqueue(); f.advance(6000); await f.worker().drain();
  expect((await readdir(f.queue))).toContain(name);
  await f.store.record(f.run.id, { sessionId: "session" });
  f.advance(11000); await f.worker().drain();
  expect((await f.receipt(name)).status).toBe("reviewed");
});

test("deferred batches do not starve later eligible events", async () => {
  const f = await fixture();
  for (let i = 0; i < 60; i++) {
    await writeFile(join(f.queue, `aaa-${i.toString().padStart(2, "0")}.json`), JSON.stringify({
      id: `unrelated-${i}`, sessionId: "unrelated", event: "Stop", at: 100_000, notBefore: 99_000 }));
  }
  const name = await f.enqueue(); f.advance(6000);
  const worker = f.worker(); await worker.drain(); await worker.drain();
  expect((await f.receipt(name)).status).toBe("reviewed");
});
