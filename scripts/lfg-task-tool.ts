#!/usr/bin/env bun
// Local session tool. All writes pass through the running host's scheduler.
const [command, id] = process.argv.slice(2);
const base = process.env.LFG_TASK_BASE ?? "http://127.0.0.1:8766";
const root = "/api/scheduled-tasks";
if (!command || !["list", "create", "update", "runs", "pause", "resume", "cancel", "run"].includes(command)) {
  console.error("Usage: lfg-task-tool list | create < task.json | update ID < patch.json | runs/pause/resume/cancel/run ID"); process.exit(1);
}
if (!["list", "create"].includes(command) && !/^[0-9a-f-]{36}$/.test(id ?? "")) { console.error("A task ID is required."); process.exit(1); }
const read = command === "list" || command === "runs";
const suffix = command === "runs" ? "/runs" : command === "cancel" || command === "run" ? `/${command}` : "";
const path = root + (id ? `/${id}` : "") + suffix;
try {
  const body = command === "create" || command === "update" ? JSON.parse(await Bun.stdin.text()) : { enabled: command === "resume" };
  const response = await fetch(base + path, { method: read ? "GET" : "POST", ...(!read ? { headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : {}) });
  console.log(await response.text()); if (!response.ok) process.exit(1);
} catch (e) { console.error((e as Error).message); process.exit(1); }
