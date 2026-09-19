import { describe, expect, test } from "bun:test";
import { reduceFleetLiveActivity, type SessionState } from "./watcher";

// The client-ended veto: after the phone reports its card ended, the server may
// push-to-start again only for a population that differs from the one the phone
// ended against. See `.claude/diagnosis-live-activity-duplicate-cards-20260918.md`.

function obs(busy: boolean, promptPresent: boolean): SessionState {
  return { busy, promptPresent };
}

const working = (sid: string) => ({ session: { sessionId: sid, title: sid }, observed: obs(true, false) });

describe("reduceFleetLiveActivity — client-ended veto", () => {
  test("reports the active population on every decision", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s1"), working("s2")],
      active: null,
      now: 1_700,
    });
    expect(r.action?.event).toBe("start");
    expect(r.population.sort()).toEqual(["s1", "s2"]);
  });

  test("SC2: no start while every active sid is inside the veto population", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s1")],
      active: null,
      clientEnded: { population: ["s1"] },
      now: 1_700,
    });
    expect(r.action).toBeNull();
    expect(r.nextActive).toBeNull();
    expect(r.vetoed).toBe(true);
    expect(r.population).toEqual(["s1"]);
  });

  test("SC2: a subset of the vetoed population is still vetoed", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s2")],
      active: null,
      clientEnded: { population: ["s1", "s2", "s3"] },
      now: 1_700,
    });
    expect(r.action).toBeNull();
    expect(r.vetoed).toBe(true);
  });

  test("SC3: a session outside the veto population lifts it and starts", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s1"), working("s9")],
      active: null,
      clientEnded: { population: ["s1"] },
      now: 1_700,
    });
    expect(r.action?.event).toBe("start");
    expect(r.vetoed).toBe(false);
    expect(r.nextActive?.startedAt).toBe(1_700);
  });

  test("SC4: an empty veto population blocks nothing", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s1")],
      active: null,
      clientEnded: { population: [] },
      now: 1_700,
    });
    expect(r.action?.event).toBe("start");
    expect(r.vetoed).toBe(false);
  });

  test("SC4: no veto at all behaves exactly as before", () => {
    const r = reduceFleetLiveActivity({
      observations: [working("s1")],
      active: null,
      now: 1_700,
    });
    expect(r.action?.event).toBe("start");
    expect(r.vetoed).toBe(false);
  });

  test("the veto is irrelevant while a card is already tracked", () => {
    const first = reduceFleetLiveActivity({ observations: [working("s1")], active: null, now: 1_700 });
    const r = reduceFleetLiveActivity({
      observations: [working("s1"), working("s2")],
      active: first.nextActive,
      clientEnded: { population: ["s1", "s2"] },
      now: 1_710,
    });
    expect(r.action?.event).toBe("update");
    expect(r.vetoed).toBe(false);
  });

  test("an empty fleet under a veto is still 'nothing to do', not vetoed", () => {
    const r = reduceFleetLiveActivity({
      observations: [],
      active: null,
      clientEnded: { population: ["s1"] },
      now: 1_700,
    });
    expect(r.action).toBeNull();
    expect(r.vetoed).toBe(false);
    expect(r.population).toEqual([]);
  });
});
