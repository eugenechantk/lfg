import { describe, expect, test } from "bun:test";

describe("iOS file preview toolbar", () => {
  test("Share and Done are separate native toolbar controls", async () => {
    const source = await Bun.file(
      import.meta.dir + "/../ios/LFG/RichContent.swift",
    ).text();
    const start = source.indexOf("struct FileViewerSheet: View");
    const end = source.indexOf("private struct FileViewerPage", start);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(end).toBeGreaterThan(start);

    const viewer = source.slice(start, end);
    expect(viewer).not.toContain("ToolbarItemGroup(placement: .topBarTrailing)");
    expect(viewer.match(/ToolbarItem\(placement: \.topBarTrailing\)/g)?.length)
      .toBeGreaterThanOrEqual(2);
    expect(viewer).toContain("#available(iOS 26.0, *)");
    expect(viewer).toContain("ToolbarSpacer(.fixed, placement: .topBarTrailing)");
    expect(viewer).toContain('accessibilityIdentifier("filePreviewShareButton")');
    expect(viewer).toContain('accessibilityIdentifier("filePreviewDoneButton")');
  });
});
