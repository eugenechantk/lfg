import { join } from "node:path";
import { PATHS } from "./config";

/** Give managed agents the actual local command; preserve caller instructions. */
export function withNotificationInstructions(systemPrompt: string | undefined, tmuxName: string): string {
  const cli = "bun run '" + join(PATHS.root, "src/cli.ts").replace(/'/g, "'\\''") + "' notify";
  return [systemPrompt, `LFG session notifications: At completion or when user input is required, send one concise, descriptive alert through the local host. Include the concrete result, blocker, or action needed; do not say only done. Use ${cli} sessions to find this session's UUID by its exact tmuxName ${JSON.stringify(tmuxName)}. Then run ${cli} --session <UUID> --status <completed|needs-input|blocked|reminder|working> --message <quoted text> --request-id <unique stable ID>. Keep the same request ID for retries. Do not guess a session ID. The host fans the message out to all LFG clients. Report APNs acceptance accurately; it does not prove physical delivery. Avoid routine progress alerts. Future reminders belong in scheduled Tasks.`].filter(Boolean).join("\n\n");
}

export function chatNotificationInstructions(sessionId: string): string {
  const cli = "bun run '" + join(PATHS.root, "src/cli.ts").replace(/'/g, "'\\''") + "' notify";
  return `For a substantial completed request or when input is needed, send one descriptive LFG alert using ${cli} --session ${sessionId} --status <completed|needs-input|blocked|reminder|working> --message <quoted text> --request-id <unique stable ID>. Explain the result or next action. Reuse the request ID after a timeout. Avoid routine progress alerts. Scheduled jobs already own their notification policy; do not send an extra alert for a scheduled job.`;
}
