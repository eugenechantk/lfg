import { normalizeLineMessages, statusForTest, lastAssistantForTest } from "/Users/eugenechan/dev/personal/lfg/src/sessions.ts";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const rec = (payload: unknown) =>
  JSON.stringify({ timestamp: "2026-09-06T17:32:56.605Z", type: "event_msg", payload });

const cases: [string, unknown][] = [
  ["error: null", { type: "task_complete", turn_id: "t", last_agent_message: "done", error: null }],
  ["error absent", { type: "task_complete", turn_id: "t", last_agent_message: "done" }],
  ["error: {}", { type: "task_complete", error: {} }],
  ["error: {message: ''}", { type: "task_complete", error: { message: "", codex_error_info: "other" } }],
  ["error: {message: '   '}", { type: "task_complete", error: { message: "   ", codex_error_info: "other" } }],
  ["error: {message: 123}", { type: "task_complete", error: { message: 123, codex_error_info: "other" } }],
  ["error: 'a string'", { type: "task_complete", error: "a string" }],
  ["error: []", { type: "task_complete", error: [] }],
  ["invalid JSON starting with {", { type: "task_complete", error: { message: "{not valid json: boom", codex_error_info: "other" } }],
  ["valid JSON without message field", { type: "task_complete", error: { message: '{"foo":1}', codex_error_info: "other" } }],
  ["JSON with non-string message", { type: "task_complete", error: { message: '{"error":{"message":42}}', codex_error_info: "other" } }],
  ["codex_error_info missing", { type: "task_complete", error: { message: "something broke" } }],
  ["codex_error_info empty string", { type: "task_complete", error: { message: "something broke", codex_error_info: "" } }],
  ["codex_error_info non-string", { type: "task_complete", error: { message: "something broke", codex_error_info: { nested: true } } }],
  ["usage limit (real)", { type: "task_complete", error: { message: "You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 9:00 PM.", codex_error_info: "usage_limit_exceeded" } }],
  ["standalone error event (unchanged path)", { type: "error", message: "stream disconnected" }],
  ["only markup", { type: "task_complete", error: { message: "<html><body>x</body></html>", codex_error_info: "other" } }],
];

let threw = 0;
for (const [name, payload] of cases) {
  try {
    const msgs = normalizeLineMessages(rec(payload));
    const status = statusForTest(msgs[msgs.length - 1] ?? null, null);
    console.log(`[${name}] -> ${msgs.length} msg(s)`, msgs.map((m) => ({ role: m.role, kind: m.kind, apiError: m.apiError, errorCode: m.errorCode, text: m.text })), "status:", status);
  } catch (e) {
    threw++;
    console.log(`[${name}] THREW`, e);
  }
}

// Non-error assistant message must classify ok
const good = normalizeLineMessages(JSON.stringify({ timestamp: "2026-09-06T17:32:56.605Z", type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "All done." }] } }));
console.log("[non-error assistant] ->", good, "status:", statusForTest(good[good.length - 1] ?? null, null));

// SC3 selection over a rollout fixture: error, then user_message, then thread_settings_applied
const dir = mkdtempSync(join(process.env.TMPDIR ?? "/tmp", "aud-"));
const p = join(dir, "rollout.jsonl");
writeFileSync(p, [
  rec({ type: "task_complete", error: { message: "You've hit your usage limit. try again at 9:00 PM.", codex_error_info: "usage_limit_exceeded" } }),
  rec({ type: "user_message", message: "are you there?" }),
  rec({ type: "thread_settings_applied" }),
].join("\n") + "\n");
const la = await lastAssistantForTest(p);
console.log("[SC3 fixture] lastAssistant:", la && { role: la.role, apiError: la.apiError, errorCode: la.errorCode }, "status:", statusForTest(la, null));
// And recovery: a good assistant reply after the error clears it
writeFileSync(p, [
  rec({ type: "task_complete", error: { message: "limit", codex_error_info: "usage_limit_exceeded" } }),
  rec({ type: "user_message", message: "retry" }),
  JSON.stringify({ timestamp: "2026-09-06T17:40:00.000Z", type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Back." }] } }),
  rec({ type: "task_complete", error: null }),
].join("\n") + "\n");
const la2 = await lastAssistantForTest(p);
console.log("[SC3 recovery] lastAssistant:", la2 && { role: la2.role, apiError: la2.apiError, text: la2.text }, "status:", statusForTest(la2, null));
console.log(`THREW COUNT: ${threw}`);
