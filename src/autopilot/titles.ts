// Title overrides, with provenance.
//
// `session-titles.json` used to be a flat `Record<sessionId, string>` — a title
// and nothing else. That was fine while renaming was exclusively something the
// human did from the client. The autopilot changes that: it renames sessions on
// its own, and the one rule it must never break is "don't clobber a name Eugene
// chose". Inferring that from the string is impossible, so the file now stores a
// record per session and the source is written down at the moment of the rename.
//
// Reading is deliberately lenient in both directions: a legacy string value
// upgrades to `{ source: "user" }` (every override that predates this module WAS
// set by hand, so that classification is correct, not a guess), and any row that
// is malformed is dropped rather than throwing. The file exists to decorate a
// session list — a corrupt one should cost a title, never a request.

export type TitleSource = "user" | "auto";

export type TitleRecord = {
  title: string;
  source: TitleSource;
  /** ms epoch of the rename. */
  setAt: number;
  /** One line on why autopilot picked this. Absent for human renames. */
  basis?: string;
};

export type TitleFile = Record<string, TitleRecord>;

const MAX_TITLE = 200;
const MAX_BASIS = 300;

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

/** One row, or null if there's nothing usable in it. */
export function parseTitleRecord(raw: unknown): TitleRecord | null {
  if (typeof raw === "string") {
    const t = raw.trim();
    // Legacy shape. Everything written before provenance existed came from the
    // client's rename affordance, i.e. from Eugene — so "user" is a fact here.
    return t ? { title: t.slice(0, MAX_TITLE), source: "user", setAt: 0 } : null;
  }
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Partial<TitleRecord>;
  const t = typeof r.title === "string" ? r.title.trim() : "";
  if (!t) return null;
  return {
    title: t.slice(0, MAX_TITLE),
    // Anything that isn't explicitly "auto" is treated as human-set. The failure
    // we care about is autopilot overwriting a human title, so an unreadable
    // source must fall on the side that makes autopilot keep its hands off.
    source: r.source === "auto" ? "auto" : "user",
    setAt: num(r.setAt) ?? 0,
    ...(typeof r.basis === "string" && r.basis.trim()
      ? { basis: r.basis.trim().slice(0, MAX_BASIS) }
      : {}),
  };
}

/** Whole file. Accepts the legacy string-valued shape row by row. */
export function parseTitleFile(raw: unknown): TitleFile {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: TitleFile = {};
  for (const [id, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!id) continue;
    const rec = parseTitleRecord(value);
    if (rec) out[id] = rec;
  }
  return out;
}

/**
 * The flat `id → title` map every existing consumer already expects. Keeping
 * this shape is what lets provenance land without touching `enrichCandidate`,
 * `applyTitleOverrides`, or the session list.
 */
export function flattenTitles(file: TitleFile): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [id, rec] of Object.entries(file)) out[id] = rec.title;
  return out;
}

/** May the autopilot rename this session? Absent record = yes (no human claim). */
export function autopilotMayRename(rec: TitleRecord | undefined): boolean {
  return !rec || rec.source === "auto";
}
