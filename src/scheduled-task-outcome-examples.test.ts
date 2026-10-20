import { expect, test } from "bun:test";
import { parseTaskOutcome } from "./scheduled-task-outcome.ts";

const runId = "example-run";
const verdict = `<lfg_task_result>${JSON.stringify({ run_id: runId, status: "completed", summary: "Verified the deliverable." })}</lfg_task_result>`;

test("a verdict inside an unfinished Markdown example cannot complete a run", () => {
  for (const prefix of ["```json\n", "~~~json\n", "   ````\n```\n", "<!-- closed -->\n```\n"]) {
    const result = parseTaskOutcome(`The work is incomplete. Example:\n${prefix}${verdict}`, runId);
    expect(result.outcome).toBeUndefined();
    expect(result.error).toBeTruthy();
  }
});

test("a verdict inside an unfinished HTML comment cannot complete a run", () => {
  for (const prefix of ["<!--\n", "<!-- closed -->\n<!--\n", "<!-- ```\n"]) {
    expect(parseTaskOutcome(prefix + verdict, runId).outcome).toBeUndefined();
  }
});

test("closed examples and comments before a real verdict remain valid", () => {
  for (const prefix of ["```json\nAn example.\n```\n", "~~~\nAn example.\n~~~~\n", "<!-- closed -->\n", "```\n<!-- literal, not a comment.\n```\n"]) {
    expect(parseTaskOutcome(prefix + verdict, runId).outcome?.status).toBe("completed");
  }
});

test("all line boundaries used by the verdict matcher also apply to examples", () => {
  for (const newline of ["\r", "\r\n", "\n", "\u2028", "\u2029"]) {
    for (const fence of ["```json", "~~~json"]) {
      expect(parseTaskOutcome(["Incomplete. Example:", fence, verdict].join(newline), runId).outcome).toBeUndefined();
    }
  }
});

test("literal comment tokens cannot hide a later unfinished fence", () => {
  for (const literal of ["`<!--`", "``<!--``", "\\<!--", "`line\ntext <!--`", "``line\ntext <!--``"]) {
    expect(parseTaskOutcome(`The token is ${literal}.\n\x60\x60\x60json\n-->\n${verdict}`, runId).outcome).toBeUndefined();
  }
});

test("a block comment interrupts an unfinished inline span", () => {
  for (const ticks of ["`", "``"]) for (const spaces of ["", " ", "   "]) {
    expect(parseTaskOutcome(`The token is ${ticks}\n${spaces}<!--\n${ticks}\n${verdict}`, runId).outcome).toBeUndefined();
  }
});

test("comment tokens in fence info do not leak outside closed examples", () => {
  for (const fence of ["```", "~~~"]) {
    expect(parseTaskOutcome(`${fence}text <!--\nExample.\n${fence}\n${verdict}`, runId).outcome?.status).toBe("completed");
  }
});
