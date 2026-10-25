/** The execution agent's assessment of one run, separate from process health. */
export type TaskOutcome = { status: "completed" | "incomplete" | "error"; summary: string };

export function scheduledTaskSystemPrompt(runId: string): string {
  return `This is one execution of an LFG scheduled task. The user message contains the saved instructions for this run.
Carry out those instructions within the existing permissions. The host owns scheduling. Do not create, re-arm, or modify this task's schedule. Do not treat a manual trigger or a missed slot as permission to skip the requested work unless the saved instructions require that.
Before ending, assess whether THIS RUN achieved the saved instructions. Judge the requested result, required duration, deliverables, and verification using evidence from this run. Ending a session, attempting the work, or safely stopping does not mean the task is completed. A recovered hiccup does not prevent completion if all required results were achieved and verified.
Choose exactly one verdict:
- completed: all required work for this run was achieved and verified. Cite the evidence in your summary.
- incomplete: work remains, the run was partial or skipped, a prerequisite or approval is missing, or success could not be verified. State what was achieved, what remains, and why.
- error: a tool, service, or execution failure prevented the requested result. State the failure and remaining work. A recoverable error that you fixed is not itself an error verdict.
Do not claim success based on intent, a clean exit, or unverified assumptions. Keep unknowns explicit. A live question may wait for the user's answer; when you actually end the run, report its outcome honestly.
Use the same completion decision in your canonical report and structured verdict. At the end of the turn, the installed lifecycle hook queues automatic outcome reconciliation after the final verdict is saved and the source session is idle. If this does not synchronize a later correction, request an explicit outcome review through review_scheduled_task_run. Editing a report file alone does not update the stored scheduler outcome. Review preserves the original assessment and never reruns or reschedules the task.
Write a normal human-readable final report. Finish that final response with this machine-readable block, using valid JSON, the exact run_id below, your chosen status, and a concise non-empty summary of the evidence or remaining work. Do not put the block in a code fence or quote it as an example. Include it even when blocked or unsuccessful. Mandatory memory citations may follow the block.
<lfg_task_result>{"run_id":${JSON.stringify(runId)},"status":"completed|incomplete|error","summary":"Evidence for the result, or remaining work and its cause."}</lfg_task_result>`;
}

/** A truncated example must not become a real verdict just because it ends the reply. */
function insideExample(prefix: string): boolean {
  // JavaScript's multiline marker matcher recognizes each of these boundaries.
  const source = prefix.replace(/\r\n?|\u2028|\u2029/g, "\n");
  let fence: string | undefined;
  let comment = false;
  let inline = 0;
  let offset = 0;
  for (const line of source.split("\n")) {
    const lineOffset = offset;
    offset += line.length + 1;
    if (fence) {
      const close = line.match(/^ {0,3}(`{3,}|~{3,})[ \t]*$/)?.[1];
      if (close && close[0] === fence[0] && close.length >= fence.length) fence = undefined;
      continue;
    }
    // Fence info is literal text, including any comment-like tokens in it.
    const open = !comment && line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (open && !(open[1]![0] === "`" && open[2]!.includes("`"))) {
      fence = open[1]; inline = 0; continue;
    }
    // A line-leading HTML comment starts a block before inline Markdown is
    // parsed, even when a previous line contains an unmatched backtick.
    if (!comment && /^ {0,3}<!--/.test(line)) inline = 0;
    if (!line.trim()) inline = 0;
    let cursor = 0;
    while (cursor < line.length) {
      if (comment) {
        const end = line.indexOf("-->", cursor);
        if (end < 0) break;
        cursor = end + 3;
        comment = false;
        continue;
      }
      if (!inline && line[cursor] === "\\") { cursor += 2; continue; }
      if (line[cursor] === "`") {
        let end = cursor + 1;
        while (line[end] === "`") end++;
        const width = end - cursor;
        if (inline === width) inline = 0;
        else if (!inline) {
          // An unmatched backtick run is ordinary Markdown text. Code spans
          // may cross a line, but cannot cross a paragraph boundary.
          const rest = source.slice(lineOffset + end).split(/\n[ \t]*\n/, 1)[0]!;
          for (const match of rest.matchAll(/`+/g)) {
            if (match[0].length === width) { inline = width; break; }
          }
        }
        cursor = end;
        continue;
      }
      if (!inline && line.startsWith("<!--", cursor)) { comment = true; cursor += 4; continue; }
      cursor++;
    }
  }
  return fence != null || comment;
}

/** Fail closed: prose, tool output, another run's result, or a partial block is never success. */
export function parseTaskOutcome(text: string, runId: string): { outcome?: TaskOutcome; error?: string; report?: string } {
  const body = text.replace(/\s*<oai-mem-citation>[\s\S]*?<\/oai-mem-citation>\s*$/, "").trimEnd();
  const blocks = [...body.matchAll(/^<lfg_task_result>([^]*?)<\/lfg_task_result>/gm)];
  const block = blocks[0];
  if (blocks.length !== 1 || !block || block.index! + block[0].length !== body.length
    || insideExample(body.slice(0, block.index))) {
    return { error: "The agent ended without a valid final completion verdict. Open the session to review what remains." };
  }
  try {
    const value = JSON.parse(block[1]!);
    if (value?.run_id !== runId || !["completed", "incomplete", "error"].includes(value?.status)
      || typeof value?.summary !== "string" || !value.summary.trim() || value.summary.length > 8000) throw Error();
    return { outcome: { status: value.status, summary: value.summary.trim() }, report: body.slice(0, block.index).trim() || value.summary.trim() };
  } catch {
    return { error: "The agent's completion verdict is invalid or belongs to another run. Open the session to review the result." };
  }
}
