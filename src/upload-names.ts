// Naming for client-uploaded attachments.
//
// The iOS client sanitizes filenames before it sends them, but this is the side
// that actually opens a file descriptor, so it re-does the work from scratch:
// the header is attacker-controlled as far as this process is concerned, and a
// name like `../../.ssh/authorized_keys` must not be able to steer where bytes
// land. Kept in its own module so the edges are testable without booting a
// server.

/** Longest stored component. Well inside every filesystem's 255-byte limit. */
export const MAX_FILENAME = 120;

const ALLOWED = /[^A-Za-z0-9._-]/g;

function scrub(s: string): string {
  return s
    .replace(ALLOWED, "_")
    .replace(/_+/g, "_") // collapse runs, so "a   b" isn't "a___b"
    .replace(/^\.+/, "") // a leading dot hides the file and `.`/`..` are traversal
    .replace(/_+$/, "");
}

/**
 * Reduce an arbitrary client-supplied filename to a single safe path component,
 * preserving the extension (it drives content type, the client's icon, and
 * whether the agent can read the file at all).
 */
export function sanitizeUploadFilename(raw: string, fallbackExt = "dat"): string {
  // Last component only — both separators, because a Windows-shaped name is
  // still a traversal attempt.
  const last = (raw || "").replace(/\\/g, "/").split("/").pop() ?? "";

  const dot = last.lastIndexOf(".");
  // A leading dot means a dotfile, not an extension (`.gitignore` is all name).
  let base = dot > 0 ? last.slice(0, dot) : last;
  let ext = dot > 0 ? last.slice(dot + 1) : "";

  base = scrub(base);
  ext = scrub(ext).toLowerCase();

  if (!base || /^[._]*$/.test(base)) base = "file";
  if (!ext) ext = scrub(fallbackExt).toLowerCase() || "dat";
  if (ext.length > 12) ext = ext.slice(0, 12);

  const budget = MAX_FILENAME - ext.length - 1;
  if (budget > 0 && base.length > budget) base = base.slice(0, budget);

  return `${base}.${ext}`;
}

/**
 * The filename arrives in a header, which is latin-1 only, so the client
 * percent-encodes it. A malformed encoding is the client's problem, not a
 * reason to drop the upload — fall back to the raw bytes.
 */
export function decodeFilenameHeader(value: string | null): string {
  if (!value) return "";
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/** Extension implied by a Content-Type, for uploads that carry no filename. */
export function extForContentType(ct: string): string {
  const t = (ct || "").toLowerCase().split(";")[0].trim();
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/heic": "heic",
    "image/heif": "heif",
    "image/bmp": "bmp",
    "image/tiff": "tiff",
    "video/mp4": "mp4",
    "video/quicktime": "mov",
    "video/x-m4v": "m4v",
    "video/webm": "webm",
    "application/pdf": "pdf",
    "text/plain": "txt",
    "text/markdown": "md",
    "text/csv": "csv",
    "text/html": "html",
    "application/json": "json",
    "application/xml": "xml",
    "application/zip": "zip",
    "audio/mpeg": "mp3",
    "audio/mp4": "m4a",
    "audio/wav": "wav",
  };
  if (map[t]) return map[t];
  // Legacy clients sent only `image/<something>`; keep them landing as images.
  if (t.startsWith("image/")) return "jpg";
  return "";
}

/**
 * Resolve the stored name for an upload from whatever the client gave us.
 *
 * The filename wins when present because it is what the user will see on the
 * transcript card; Content-Type only fills in a missing extension.
 */
export function storedUploadName(rawFilename: string, contentType: string): string {
  const fallback = extForContentType(contentType) || "dat";
  const name = sanitizeUploadFilename(rawFilename, fallback);
  // A name that arrived with no usable extension at all but whose Content-Type
  // is unambiguous should follow the Content-Type rather than land as `.dat`.
  if (name.endsWith(".dat") && fallback !== "dat") {
    return `${name.slice(0, -4)}.${fallback}`;
  }
  return name;
}
