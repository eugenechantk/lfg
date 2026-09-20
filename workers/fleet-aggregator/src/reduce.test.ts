import { describe, expect, test } from "bun:test";
import { buildStart, buildUpdate } from "../../../src/push/liveactivity";
import { SLICE_TTL_S, contentFor, decide, endBody, startBody, unionRows, updateBody, type Row, type Slice } from "./reduce";

const row = (sid: string, state: Row["state"] = "working", since = 1_000): Row => ({ sid, title: sid, state, since });
const slice = (hostId: string, rows: Row[], receivedAt = 2_000): Slice => ({ hostId, rows, receivedAt });

describe("unionRows — the merge iOS cannot do", () => {
  test("two hosts' slices become one population", () => {
    const rows = unionRows([slice("pro", [row("a")]), slice("air", [row("b"), row("c")])], 2_010);
    expect(rows.map((r) => r.sid).sort()).toEqual(["a", "b", "c"]);
  });

  test("a host that stopped heartbeating drops off after the TTL", () => {
    const slices = [slice("pro", [row("a")], 2_000), slice("air", [row("b")], 2_000 + SLICE_TTL_S)];
    expect(unionRows(slices, 2_000 + SLICE_TTL_S).map((r) => r.sid).sort()).toEqual(["a", "b"]);
    expect(unionRows(slices, 2_001 + SLICE_TTL_S).map((r) => r.sid)).toEqual(["b"]);
  });

  test("the same sid on two hosts (mid-move) counts once, newest slice wins", () => {
    const rows = unionRows(
      [slice("pro", [row("a", "working", 100)], 2_000), slice("air", [row("a", "needsInput", 900)], 2_005)],
      2_010,
    );
    expect(rows).toEqual([row("a", "needsInput", 900)]);
  });

  test("rows that are not card states are ignored", () => {
    const rows = unionRows([slice("pro", [{ ...row("a"), state: "idle" as never }, row("b")])], 2_010);
    expect(rows.map((r) => r.sid)).toEqual(["b"]);
  });
});

describe("contentFor", () => {
  test("needs-input first, then oldest, three rows and a remainder", () => {
    const c = contentFor(
      [row("w-old", "working", 10), row("n-new", "needsInput", 50), row("w-new", "working", 40), row("n-old", "needsInput", 20), row("w-mid", "working", 30)],
      3_000,
    );
    expect(c.rows.map((r) => r.sid)).toEqual(["n-old", "n-new", "w-old"]);
    expect(c).toMatchObject({ working: 3, needsInput: 2, more: 2, updatedAt: 3_000 });
  });
});

describe("decide", () => {
  test("no card + work on ANY host → start", () => {
    const d = decide({ slices: [slice("pro", []), slice("air", [row("b")])], card: null, now: 2_010 });
    expect(d.action).toEqual({ event: "start", priority: 10 });
    expect(d.nextCard?.startedAt).toBe(2_010);
    expect(d.population).toEqual(["b"]);
  });

  test("one host reaching zero does NOT end a card the other host still needs", () => {
    const first = decide({ slices: [slice("pro", [row("a")]), slice("air", [row("b")])], card: null, now: 2_010 });
    const d = decide({ slices: [slice("pro", [], 2_020), slice("air", [row("b")], 2_020)], card: first.nextCard, now: 2_021 });
    expect(d.action?.event).toBe("update");
    expect(d.content).toMatchObject({ working: 1, rows: [{ sid: "b" }] });
  });

  test("the whole fleet empty → end at once", () => {
    const first = decide({ slices: [slice("air", [row("b")])], card: null, now: 2_010 });
    const d = decide({ slices: [slice("pro", [], 2_020), slice("air", [], 2_020)], card: first.nextCard, now: 2_021 });
    expect(d.action).toEqual({ event: "end", priority: 10 });
    expect(d.nextCard).toBeNull();
  });

  test("the last publishing host going silent ends the card after the TTL", () => {
    const first = decide({ slices: [slice("air", [row("b")], 2_000)], card: null, now: 2_001 });
    const d = decide({ slices: [slice("air", [row("b")], 2_000)], card: first.nextCard, now: 2_001 + SLICE_TTL_S });
    expect(d.action?.event).toBe("end");
  });

  test("unchanged content sends nothing", () => {
    const first = decide({ slices: [slice("air", [row("b")])], card: null, now: 2_010 });
    const d = decide({ slices: [slice("air", [row("b")], 2_040)], card: first.nextCard, now: 2_041 });
    expect(d.action).toBeNull();
    expect(d.nextCard).toEqual(first.nextCard);
  });

  test("a card the phone created (adopted, no content yet) gets filled at priority 10", () => {
    const d = decide({ slices: [slice("air", [row("b")])], card: { startedAt: 2_000 }, now: 2_010 });
    expect(d.action).toEqual({ event: "update", priority: 10 });
  });

  test("routine count changes ride at priority 5; a new question at 10", () => {
    const first = decide({ slices: [slice("air", [row("b")])], card: null, now: 2_010 });
    const more = decide({ slices: [slice("air", [row("b"), row("c")], 2_020)], card: first.nextCard, now: 2_021 });
    expect(more.action).toEqual({ event: "update", priority: 5 });
    const asks = decide({ slices: [slice("air", [row("b"), row("c", "needsInput")], 2_030)], card: more.nextCard, now: 2_031 });
    expect(asks.action).toEqual({ event: "update", priority: 10 });
  });

  test("client-ended veto: same population → no restart; a new sid lifts it; empty veto blocks nothing", () => {
    const same = decide({ slices: [slice("air", [row("b")])], card: null, clientEnded: { population: ["b", "z"] }, now: 2_010 });
    expect(same.action).toBeNull();
    expect(same.vetoed).toBe(true);
    const lifted = decide({ slices: [slice("air", [row("b"), row("new")])], card: null, clientEnded: { population: ["b"] }, now: 2_010 });
    expect(lifted.action?.event).toBe("start");
    const empty = decide({ slices: [slice("air", [row("b")])], card: null, clientEnded: { population: [] }, now: 2_010 });
    expect(empty.action?.event).toBe("start");
  });
});

describe("wire payloads match the lfg server's builders", () => {
  const content = contentFor([row("a", "needsInput", 10), row("b", "working", 20)], 5_000);

  test("start", () => {
    const server = buildStart({ contentState: content, inputPushChannel: "chan==" });
    expect(startBody(content, "LFGFleetAttributes", "chan==")).toEqual(server.body as never);
  });

  test("start without a channel omits the key rather than sending it empty", () => {
    expect("input-push-channel" in startBody(content, "LFGFleetAttributes", undefined).aps).toBe(false);
  });

  test("update", () => {
    expect(updateBody(content)).toEqual(buildUpdate(content).body as never);
  });

  test("end dismisses immediately", () => {
    expect(endBody(content, 5_050).aps).toMatchObject({ event: "end", "dismissal-date": 5_050 });
  });
});
