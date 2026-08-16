import { describe, expect, test } from "bun:test";
import {
  MAX_FILENAME,
  decodeFilenameHeader,
  extForContentType,
  sanitizeUploadFilename,
  storedUploadName,
} from "./upload-names";

describe("sanitizeUploadFilename", () => {
  test("leaves an ordinary name alone", () => {
    expect(sanitizeUploadFilename("report.pdf")).toBe("report.pdf");
    expect(sanitizeUploadFilename("my-notes_v2.md")).toBe("my-notes_v2.md");
  });

  test("traversal cannot escape the upload directory", () => {
    // This is the whole reason the module exists: the header is untrusted.
    for (const evil of [
      "../../etc/passwd",
      "../../../.ssh/authorized_keys",
      "/etc/shadow",
      "..",
      ".",
      "....//....//x",
      String.raw`C:\Users\e\evil.exe`,
    ]) {
      const out = sanitizeUploadFilename(evil);
      expect(out).not.toContain("/");
      expect(out).not.toContain("\\");
      expect(out).not.toContain("..");
      expect(out.startsWith(".")).toBe(false);
    }
    expect(sanitizeUploadFilename("../../etc/passwd")).toBe("passwd.dat");
    expect(sanitizeUploadFilename("..")).toBe("file.dat");
  });

  test("whitespace collapses so the stored path stays a single token", () => {
    // The path is appended to the message text bare; a space truncates it for
    // the client's scanner and for the agent reading it.
    expect(sanitizeUploadFilename("Q3 sales report.pdf")).toBe("Q3_sales_report.pdf");
    expect(sanitizeUploadFilename("my  long   name.csv")).toBe("my_long_name.csv");
  });

  test("control characters, quotes and shell metacharacters are scrubbed", () => {
    expect(sanitizeUploadFilename("we\u0000ird\n.txt")).toBe("we_ird.txt");
    expect(sanitizeUploadFilename('a";rm -rf b.txt')).toBe("a_rm_-rf_b.txt");
    expect(sanitizeUploadFilename("emoji😀.png")).toBe("emoji.png");
    expect(sanitizeUploadFilename("a😀b.png")).toBe("a_b.png");
    // A metacharacter payload containing a separator loses everything before
    // it — the last component is all that survives, by design.
    expect(sanitizeUploadFilename('a";rm -rf /;.txt')).toBe("file.txt");
  });

  test("a missing extension takes the fallback", () => {
    expect(sanitizeUploadFilename("LICENSE")).toBe("LICENSE.dat");
    expect(sanitizeUploadFilename("notes", "txt")).toBe("notes.txt");
    // A dotfile is all name and no extension, and must not stay hidden.
    expect(sanitizeUploadFilename(".gitignore")).toBe("gitignore.dat");
  });

  test("long names truncate but keep their extension", () => {
    const out = sanitizeUploadFilename("a".repeat(400) + ".pdf");
    expect(out.length).toBeLessThanOrEqual(MAX_FILENAME);
    expect(out.endsWith(".pdf")).toBe(true);
  });

  test("empty input still yields a usable name", () => {
    expect(sanitizeUploadFilename("")).toBe("file.dat");
    expect(sanitizeUploadFilename("///")).toBe("file.dat");
  });

  test("extension case is normalised", () => {
    expect(sanitizeUploadFilename("IMG_0042.HEIC")).toBe("IMG_0042.heic");
  });
});

describe("decodeFilenameHeader", () => {
  test("decodes the percent-encoding the client applies for non-ASCII", () => {
    expect(decodeFilenameHeader("rapport%20final.pdf")).toBe("rapport final.pdf");
    expect(decodeFilenameHeader("%E5%A0%B1%E5%91%8A.pdf")).toBe("報告.pdf");
  });

  test("a malformed encoding falls back rather than dropping the upload", () => {
    expect(decodeFilenameHeader("100%.pdf")).toBe("100%.pdf");
    expect(decodeFilenameHeader(null)).toBe("");
  });
});

describe("extForContentType", () => {
  test("maps the types clients actually send", () => {
    expect(extForContentType("application/pdf")).toBe("pdf");
    expect(extForContentType("video/quicktime")).toBe("mov");
    expect(extForContentType("text/plain; charset=utf-8")).toBe("txt");
  });

  test("an unrecognised image type still lands as an image", () => {
    // The shipped client sent bare image/* types; they must keep working.
    expect(extForContentType("image/x-weird")).toBe("jpg");
    expect(extForContentType("image/png")).toBe("png");
  });

  test("truly unknown types yield nothing so the filename decides", () => {
    expect(extForContentType("application/x-nonsense")).toBe("");
    expect(extForContentType("")).toBe("");
  });
});

describe("storedUploadName", () => {
  test("the filename wins — it is what the transcript card shows", () => {
    expect(storedUploadName("Quarterly Report.pdf", "application/pdf")).toBe(
      "Quarterly_Report.pdf",
    );
  });

  test("content type fills in a missing extension", () => {
    expect(storedUploadName("scan", "application/pdf")).toBe("scan.pdf");
    expect(storedUploadName("", "image/png")).toBe("file.png");
  });

  test("no filename and no known type is honestly named", () => {
    expect(storedUploadName("", "application/x-nonsense")).toBe("file.dat");
  });

  test("a traversal filename with a legit content type is still contained", () => {
    const out = storedUploadName("../../etc/passwd", "image/png");
    expect(out).toBe("passwd.png");
    expect(out).not.toContain("/");
  });
});
