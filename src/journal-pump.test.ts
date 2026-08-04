import { test, expect, describe } from "bun:test";
import { appendDisappearanceRetractions } from "./journal-pump.ts";
import { PumpDeltas, type Journal, type JournalEventType } from "./journal.ts";

type Appended = { sid: string; type: JournalEventType; payload: unknown };

function fakeJournal() {
  const events: Appended[] = [];
  const j: Pick<Journal, "append"> = {
    append(sid: string, type: JournalEventType, payload: unknown) {
      events.push({ sid, type, payload });
      return events.length;
    },
  };
  return { j, events };
}

describe("appendDisappearanceRetractions", () => {
  test("retracts a busy session so clients don't latch `running` forever", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true); // the session was last seen working

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([
      { sid: "s1", type: "busy", payload: { sid: "s1", busy: false } },
    ]);
  });

  test("retracts a pending prompt too, so it can't strand as needs-input", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.promptChanged("s1", { question: "Approve?" });

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([
      { sid: "s1", type: "prompt", payload: { sid: "s1", prompt: null } },
    ]);
  });

  test("emits both when the session vanished while busy AND prompting", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true);
    deltas.promptChanged("s1", { question: "Approve?" });

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events.map((e) => e.type)).toEqual(["busy", "prompt"]);
  });

  test("a session already idle when it vanished costs no events", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", false);
    deltas.promptChanged("s1", null);

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([]);
  });

  test("a never-seen session emits nothing (no phantom retraction)", () => {
    const { j, events } = fakeJournal();

    appendDisappearanceRetractions(j, new PumpDeltas(), "unknown");

    // `busyChanged` reports a change against an absent baseline, which would
    // fabricate a busy:false for a session no client ever heard of. Guarding on
    // "we actually knew it was busy" is what keeps the journal honest.
    expect(events).toEqual([]);
  });

  test("forget() after retraction still lets a returning session re-state", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true);

    appendDisappearanceRetractions(j, deltas, "s1");
    deltas.forget("s1");

    // Transfer round-trip: it comes back busy and must re-announce.
    expect(deltas.busyChanged("s1", true)).toBe(true);
    expect(events.length).toBe(1);
  });
});
