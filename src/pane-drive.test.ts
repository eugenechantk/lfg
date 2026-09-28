import { describe, expect, it } from "bun:test";
import { beginPaneDrive, endPaneDrive, paneDriveInProgress, panePromptSuppressed } from "./pane-drive.ts";

describe("panes lfg is driving", () => {
  it("suppresses scraped prompts during a drive and for a grace window after", () => {
    const t = "drive-a:0.0";
    expect(panePromptSuppressed(t)).toBe(false);
    beginPaneDrive(t);
    expect(paneDriveInProgress(t)).toBe(true);
    expect(panePromptSuppressed(t)).toBe(true);
    endPaneDrive(t, 1_000);
    expect(paneDriveInProgress(t)).toBe(false);
    // A capture taken mid-drive can be read just after the drive ends.
    expect(panePromptSuppressed(t, 3_999)).toBe(true);
    expect(panePromptSuppressed(t, 4_000)).toBe(false);
    // Past the window a real question on that pane surfaces again.
    expect(panePromptSuppressed(t, 4_001)).toBe(false);
  });

  it("is per pane and ignores pane-less sessions", () => {
    beginPaneDrive("drive-b:0.0");
    expect(panePromptSuppressed("drive-c:0.0")).toBe(false);
    expect(panePromptSuppressed(null)).toBe(false);
    expect(panePromptSuppressed(undefined)).toBe(false);
    endPaneDrive("drive-b:0.0");
  });
});
