// Adversarial fixture probes against the real modules (no source edits).
// Each case prints: what a correct layer should say vs what sessionTurnState says.
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, truncateSync, utimesSync, statSync, symlinkSync } from "node:fs";
import { join } from "node:path";

const root = mkdtempSync(join(import.meta.dir, "audit-adv-"));
process.env.LFG_AGENT_STATE_DIR = join(root, "agent-state");
mkdirSync(process.env.LFG_AGENT_STATE_DIR, { recursive: true });

const { sessionTurnState } = await import("/Users/eugenechan/dev/personal/lfg/src/session-state.ts");
const { noteConfirmedInterrupt, interruptStands, __resetInterruptMarks } = await import("/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts");
const { __resetTurnStateCache } = await import("/Users/eugenechan/dev/personal/lfg/src/turn-state.ts");
const { __resetHookStateCache } = await import("/Users/eugenechan/dev/personal/lfg/src/hook-state.ts");

let n = 0;
const J = (x: unknown) => JSON.stringify(x);
const prompt = (t = "cut a new build") => ({ type: "user", message: { role: "user", content: t } });
const assistant = { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "ok" }] } };
const aiTitle = (pad = 0) => ({ type: "ai-title", aiTitle: "Cut a build" + "x".repeat(pad) });
const lastPrompt = { type: "last-prompt", lastPrompt: "cut a new build" };
const mk = (lines: unknown[], ext = ".jsonl") => {
  const sid = `0000000${n++}-0000-4000-8000-000000000000`.slice(-36);
  const tp = join(root, `${sid}${ext}`);
  writeFileSync(tp, lines.map(J).join("\n") + "\n");
  return { sid, tp };
};
const app = (tp: string, ...lines: unknown[]) => appendFileSync(tp, lines.map(J).join("\n") + "\n");
const reset = () => { __resetInterruptMarks(); __resetTurnStateCache(); __resetHookStateCache(); };
const v = async (sid: string, tp: string) => J(await sessionTurnState({ sessionId: sid, transcriptPath: tp }));
const out = (id: string, desc: string, expectState: string, got: string) =>
  console.log(`${got.includes(`"state":"${expectState}"`) ? "OK  " : "BAD "} ${id} ${desc}\n       expect ${expectState} | got ${got}`);

// A1. Two consumers (pump + push watcher / REST) consult the same mark concurrently
//     after non-decisive metadata lands. Then nothing else is written.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, aiTitle(), lastPrompt);
  const [a, b] = await Promise.all([interruptStands(sid, tp, null), interruptStands(sid, tp, null)]);
  const third = await v(sid, tp);
  out("A1", `concurrent consults (got ${a},${b}) then a quiet tick — stop should still stand`, "idle", third);
}

// A2. Same race, then a NEW PROMPT lands inside the double-counted (skipped) window,
//     followed by more metadata. A genuinely running new turn.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, aiTitle(400)); // ~450 bytes of metadata
  await Promise.all([interruptStands(sid, tp, null), interruptStands(sid, tp, null)]);
  app(tp, prompt("next")); // new turn opens (short line, inside the skipped window)
  app(tp, aiTitle(400)); // more metadata pushes the size past the over-counted offset
  out("A2", "new prompt inside the bytes a concurrent double-count skipped", "running", await v(sid, tp));
}

// A3. Sequential consults (no race) — the control for A1/A2.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, aiTitle(400));
  await interruptStands(sid, tp, null);
  await interruptStands(sid, tp, null);
  app(tp, prompt("next"));
  app(tp, aiTitle(400));
  out("A3", "control: same writes, sequential consults", "running", await v(sid, tp));
}

// B. A line straddles the size snapshot: the new turn's prompt was half-written
//    when the endpoint recorded the mark.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  const line = J(prompt("next")) + "\n";
  appendFileSync(tp, line.slice(0, 20));
  noteConfirmedInterrupt(sid, tp);
  appendFileSync(tp, line.slice(20));
  out("B ", "new prompt straddling the snapshot (fragment at the front of the tail)", "running", await v(sid, tp));
  app(tp, assistant);
  out("B'", "…self-heals on the next decisive line", "running", await v(sid, tp));
}

// B2. A complete new prompt lands between the last idle pane capture and the
//     size snapshot (it is already inside checkedSize).
{
  reset();
  const { sid, tp } = mk([prompt()]);
  app(tp, prompt("next"));
  noteConfirmedInterrupt(sid, tp);
  out("B2", "new prompt written just BEFORE the snapshot", "running", await v(sid, tp));
}

// C. Path mismatch (symlinked dir / different spelling) — fail-safe direction?
{
  reset();
  const { sid, tp } = mk([prompt()]);
  const alias = join(root, "alias");
  try { symlinkSync(root, alias); } catch {}
  noteConfirmedInterrupt(sid, join(alias, tp.split("/").pop()!));
  out("C ", "mark under an aliased path, consulted under the real path (fails safe = running)", "running", await v(sid, tp));
}

// E. Truncation / rewrite after the stop.
{
  reset();
  const { sid, tp } = mk([prompt(), prompt("x".repeat(200))]);
  noteConfirmedInterrupt(sid, tp);
  truncateSync(tp, statSync(tp).size - 50);
  app(tp, prompt());
  out("E ", "transcript shrank after the stop (fails safe = running)", "running", await v(sid, tp));
}

// F. >1 MiB of non-decisive bytes after the stop.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, aiTitle(1 << 20));
  out("F ", ">1 MiB non-decisive appended (mark dropped → running; fail-safe, re-latches)", "running", await v(sid, tp));
}

// G. codex rollout: an open task_started, stop "confirmed", but the turn keeps going
//    (mid-turn codex traffic is non-decisive by design in classifyTurnLine).
{
  reset();
  const ev = (t: string, extra = {}) => ({ type: "event_msg", payload: { type: t, ...extra } });
  const { sid, tp } = mk([{ type: "session_meta", payload: {} }, ev("task_started")]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, ev("agent_message", { message: "still working" }), { type: "response_item", payload: { type: "message" } }, ev("token_count"), ev("exec_command_end"));
  out("G ", "codex: falsely-confirmed stop, turn continues with only mid-turn records", "running", await v(sid, tp));
  app(tp, ev("task_started"));
  out("G'", "codex: a new task_started supersedes", "running", await v(sid, tp));
}

// H1. Hook writes AFTER the mark with a non-turn transition (e.g. a late write of `running`).
{
  reset();
  const { sid, tp } = mk([prompt()]);
  utimesSync(tp, new Date(Date.now() - 8000), new Date(Date.now() - 8000));
  const hook = (state: string, at: number) => writeFileSync(join(root, `${sid}.lease.json`), J({ hostId: "h", pid: 1, acquiredAt: 1, heartbeatAt: 1, state, stateAt: at }));
  hook("running", Date.now() - 6000);
  noteConfirmedInterrupt(sid, tp, Date.now() - 4000);
  out("H1", "hook spoke before the stop, nothing after → idle", "idle", await v(sid, tp));
  __resetHookStateCache();
  hook("running", Date.now() - 1000);
  out("H1'", "hook speaks after the stop → running", "running", await v(sid, tp));
}

// H2. Hook heartbeat only (heartbeatAt moves, stateAt does not) must NOT supersede.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  utimesSync(tp, new Date(Date.now() - 8000), new Date(Date.now() - 8000));
  writeFileSync(join(root, `${sid}.lease.json`), J({ hostId: "h", pid: 1, acquiredAt: 1, heartbeatAt: Date.now(), state: "running", stateAt: Date.now() - 6000 }));
  noteConfirmedInterrupt(sid, tp, Date.now() - 4000);
  out("H2", "lease heartbeat newer than the stop, stateAt older → stop still stands", "idle", await v(sid, tp));
}

// I. Stop WITH an interrupt marker (transcript already idle): mark is never consulted,
//    so it lingers. Next turn must still read running, also after a long idle gap.
{
  reset();
  const { sid, tp } = mk([prompt(), assistant]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, { type: "user", message: { role: "user", content: "[Request interrupted by user]" } });
  out("I ", "marker written → transcript idle", "idle", await v(sid, tp));
  app(tp, lastPrompt, prompt("next"));
  out("I'", "lingering mark + next prompt → running", "running", await v(sid, tp));
}

// J. Mark recorded with transcriptPath null (endpoint row without a transcript),
//    consulted later once the transcript appears.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, null);
  out("J ", "mark with null path, consulted with a real path (fails safe = running)", "running", await v(sid, tp));
}

// K. Repeated stops: second stop re-snapshots; a decisive line between the stops
//    must not matter once the second stop is confirmed.
{
  reset();
  const { sid, tp } = mk([prompt()]);
  noteConfirmedInterrupt(sid, tp);
  app(tp, prompt("again"));
  noteConfirmedInterrupt(sid, tp);
  out("K ", "re-prompt then a second confirmed stop → idle", "idle", await v(sid, tp));
}
process.exit(0);
