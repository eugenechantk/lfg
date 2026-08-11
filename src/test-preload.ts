// Loaded before every test file (see `bunfig.toml`). Its only job is to make it
// impossible for the suite to touch this machine's REAL lfg state.
//
// The hazard is subtle and it bit for real: `PATHS` is resolved the first time
// `config.ts` is imported, and `PATHS.data` falls back to `~/.lfg` when
// `LFG_DATA` is unset. Test files that isolate themselves do so by setting
// `LFG_DATA` before their own dynamic import — but only the file that imports
// `config.ts` FIRST gets to decide. Every other file then reads a `PATHS`
// pointing somewhere it did not choose, and the ones that `rmSync(PATHS.…)` in
// a `beforeEach`/`afterEach` delete whatever is actually there.
//
// Under the full suite that resolved to the real `~/.lfg`, and running
// `bun test` silently deleted `~/.lfg/session-titles.json` — every session title
// the user had renamed by hand. (It came back looking intact, which is what made
// it hard to see: `config.ts`'s legacy-data migration re-copied the stale
// `<repo>/data/session-titles.json` on the next server boot, so the file existed
// again with old contents rather than being obviously missing.)
//
// Setting LFG_DATA here closes the whole class: by the time any test file runs,
// the fallback is already a throwaway directory. Files that set their own
// LFG_DATA still win for themselves — this only replaces the dangerous default.

import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

if (!process.env.LFG_DATA) {
  process.env.LFG_DATA = mkdtempSync(join(tmpdir(), "lfg-test-data-"));
}
