import { describe, expect, test } from "bun:test";

describe("iOS queued-message action menu anchoring", () => {
  test("each pending row owns the Menu that presents its actions", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/Components.swift",
    ).text();
    const start = source.indexOf("struct PendingStripView");
    const end = source.indexOf("/// A finished-looking user bubble", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);

    const pendingStrip = source.slice(start, end);
    expect(pendingStrip).toContain("Menu {");
    expect(pendingStrip).toContain("queuedMessageActions(for: item)");
    expect(pendingStrip).not.toContain("onTapGesture");
    expect(pendingStrip).toContain('"pendingStripRow');
  });

  test("the session root no longer presents queued-message actions", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/SessionDetailView.swift",
    ).text();
    const bodyStart = source.indexOf("var body: some View");
    const surfaceStart = source.indexOf("private var sessionSurface", bodyStart);
    expect(bodyStart).toBeGreaterThanOrEqual(0);
    expect(surfaceStart).toBeGreaterThan(bodyStart);

    const rootPresentation = source.slice(bodyStart, surfaceStart);
    expect(rootPresentation).not.toContain('"Queued message"');
    expect(rootPresentation).not.toContain("queueAction");
  });
});
