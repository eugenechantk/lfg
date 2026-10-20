import { describe, expect, test } from "bun:test";
import { parseTaskOutcome, scheduledTaskSystemPrompt } from "./scheduled-task-outcome.ts";

const runId = "run-123";
const report = (status = "completed", summary = "Verified the requested result.", id = runId) =>
  `<lfg_task_result>${JSON.stringify({ run_id: id, status, summary })}</lfg_task_result>`;

describe("scheduled run verdict", () => {
  test("accepts each explicit verdict and its reason", () => {
    for (const status of ["completed", "incomplete", "error"] as const) {
      expect(parseTaskOutcome(`Human report.\n${report(status)}`, runId).outcome).toEqual({ status, summary: "Verified the requested result." });
    }
  });
  test("never infers completion from prose or broken reports", () => {
    for (const text of ["Done.", "Blocked by login.", report("success"), report("completed", ""), report("completed", "ok", "another-run"),
      '<lfg_task_result>{broken}</lfg_task_result>', report() + "\nStill working.", "```\n" + report() + "\n```", report() + report(),
      '<lfg_task_result>{"run_id":"run-123","status":"completed","summary":42}</lfg_task_result>']) {
      expect(parseTaskOutcome(text, runId).outcome).toBeUndefined();
      expect(parseTaskOutcome(text, runId).error).toBeTruthy();
    }
  });
  test("allows mandatory trailing memory citations", () => {
    expect(parseTaskOutcome(report() + "\n<oai-mem-citation>citation</oai-mem-citation>", runId).outcome?.status).toBe("completed");
  });
  test("the execution policy defines evidence, partial work, errors and host-owned schedules", () => {
    const prompt = scheduledTaskSystemPrompt(runId);
    for (const text of [runId, "completed", "incomplete", "error", "saved instructions", "evidence", "Do not create, re-arm, or modify", "lfg_task_result"]) expect(prompt).toContain(text);
  });
});
