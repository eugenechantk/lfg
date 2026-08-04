# Should the lfg backend leave Bun?

Date: 2026-08-04. Question: "Bun is not a great runtime; can we migrate to Python or Rust?"

## TL;DR

The pain is real. Bun is mostly not the cause. One of the six documented
architecture hazards is genuinely Bun-attributable, and it happens to be the
worst one (event-loop saturation). Fixing that costs ~half a day and does not
require changing runtime.

If you still want off Bun after that, **Node is the only sane target** (~1–2
days, mechanical). Rust and Python are a multi-week rewrite that would
re-introduce every bug already fixed, because five load-bearing dependencies
are JS-only.

## What the codebase actually is

- ~13.8k LOC TypeScript, non-test.
- Hot spots: `src/commands/serve.ts` (2822), `src/sessions.ts` (1833), `src/tmux.ts` (1073).
- Bun-specific surface, by call count:

| Surface | Sites | Node equivalent | Difficulty |
|---|---|---|---|
| `Bun.file` | 44 | `fs.readFile` / `existsSync` | mechanical |
| `Bun.spawnSync` | 38 | `child_process.spawnSync` | mechanical (`.exitCode`→`.status`) |
| `Bun.write` | 18 | `fs.writeFile` | mechanical |
| `Bun.sleep` | 11 | `setTimeout` promise | trivial |
| `Bun.which` | 7 | 5-line helper | trivial |
| `Bun.spawn` | 7 | `child_process.spawn` | mechanical |
| `Bun.serve` | 1 | `node:http` + `ws`, or Hono | 1 file |
| `bun:sqlite` | 2 files | `node:sqlite` (near-identical API) | easy |
| `bun:test` | 24 files | vitest (Jest-ish, near drop-in) | tedious |
| `bun:ffi` | 1 file (`pty.ts`, 204 LOC) | `node-pty` — **deletes the file** | net win |

Note the shape: the Bun coupling is wide but shallow. Nothing here is a design
that depends on Bun.

## Which pains are actually Bun's fault

Auditing the hazards recorded in `.claude/CLAUDE.md`:

| Hazard | Bun's fault? |
|---|---|
| One PTY websocket stalls all HTTP 20s+ | **Yes, indirectly** — see below |
| Running code lags source, restarts drop state | No — Bun has `--hot`; the blocker is in-memory state |
| No `/proc` on macOS | No — platform |
| `tmux send-keys` + screen-scrape fragility | No — design |
| Bun auto-loads `.env`, invisible to `ps eww` | No — Node 20+ does the same with `--env-file` |
| `setInterval` fan-out spawn storms | No — design |

### The one that is Bun's fault

`src/pty.ts:136` — `setInterval(() => this.drain(), 16)`. A 62.5 Hz loop doing
synchronous FFI `read()` syscalls **on the main event loop**, per open terminal.
That is the HTTP stall.

And the reason it is hand-rolled FFI is stated in the file's own header comment:

> node-pty won't load under Bun, and net.Socket refuses to adopt a pty master fd here

So: Bun's weaker native-addon compatibility forced a hand-rolled PTY, and the
hand-rolled PTY is what saturates the loop. Under Node, `node-pty` reads on the
libuv threadpool and delivers data as events — no polling, no main-thread
syscalls, and `src/pty.ts` ceases to exist.

That is one genuine point against Bun. It is not six.

## Why Rust and Python are the wrong answer

Five dependencies anchor this to JS:

- `@whiskeysockets/baileys` (WhatsApp) — no mature Rust or Python equivalent. At all.
- `ai` v6 (Vercel AI SDK) + three provider adapters (`claude-code`, `codex-cli`, `opencode-sdk`) — JS-only.
- `@modelcontextprotocol/sdk`, `@anthropic-ai/sdk`, `opencode-ai`.

Mitigating detail: they are **concentrated**, not spread. Baileys is confined to
`src/commands/whatsapp.ts`; the AI SDK lives in `src/agents/backends/*` plus two
call sites. So a Rust supervisor core (HTTP, tmux, PTY, process enumeration)
with a JS sidecar for agent backends is architecturally coherent — Rust is
genuinely well-suited to a process supervisor: real threads, no event loop to
saturate, one static binary.

It is still the wrong call. It buys a solved problem (event-loop saturation, see
above) at the cost of rewriting 13.8k LOC of hard-won behavior — the tmux
send-path quirks, the pane-collision guard, the sendq confirm heuristics. Every
one of those is scar tissue from a debugging session. A rewrite discards them
and re-earns them.

## Recommendation

**1. Fix the actual problem, stay on Bun (half a day).**

- Move the PTY out of the main process — spawn a small child that owns the
  terminals and speaks a pipe to the server. Event-loop saturation dies with it,
  regardless of runtime.
- Persist `RUNS` (`serve.ts:439`) — the only module-level mutable state left, and
  the reason restarts are scary. There is already a SQLite layer (`journal.ts`,
  `sendq-store.ts`) to put it in. Once restarts are cheap, the "running code
  lags source" hazard evaporates too.

Those two changes retire the top two hazards without touching the runtime.

**2. If you still want off Bun, go to Node — and make it cheap first.**

Write `src/rt.ts` exporting `file`/`write`/`spawnSync`/`spawn`/`which`/`sleep`,
mechanically rewrite the ~125 call sites to use it, and ship that **while still
on Bun**. The shim then becomes the only file needing a Node implementation, and
the migration turns into: swap the shim, swap `Bun.serve` for Hono's Node
adapter, `bun:sqlite`→`node:sqlite`, `bun:test`→vitest, delete `pty.ts` for
node-pty. No build step needed — Node 24 strips TypeScript natively.

The shim is worth writing regardless. It makes the runtime a decision you can
defer instead of one you have to commit to now.

**3. Do not rewrite in Rust or Python.** Revisit only if the agent-backend
layer is ever decoupled behind a process boundary anyway — then a Rust core
becomes a small step rather than a rewrite.

---

## Revision — 2026-08-04, after "I don't need WhatsApp or the Vercel AI SDK"

This retires the main argument against Rust. Re-audited the imports.

### The core is already dependency-free

Every non-relative import across `serve.ts`, `sessions.ts`, `tmux.ts`,
`sendq.ts`, `push/*`, `procinfo.ts`, `journal*.ts`, `leases.ts`, `auto/*`,
`actions/index.ts`, `pty.ts`:

```
16 node:path   12 node:fs   9 node:fs/promises   8 node:os   8 node:crypto
 1 node:http2   1 bun:sqlite   1 bun:ffi   1 bun   1 marked
```

`marked` is the *only* npm package in the entire core. Everything else is
stdlib or a Bun builtin. Every JS-only dependency identified in the original
analysis lives in `src/agents/**` (2221 LOC) or `src/commands/whatsapp.ts`
(605 LOC).

The `opencode-ai` hits in `tmux.ts:492` / `sessions.ts:1423` are **not
imports** — they're a subprocess path to a harness. That coupling is already a
process boundary.

### What this means

| | Before | After dropping agents/ + whatsapp |
|---|---|---|
| npm deps in scope | 12 | 1 (`marked`) |
| LOC in scope | 13,789 | ~11,000 |
| Rust viable? | No — five JS anchors | **Yes, no anchors left** |

The dependency lock-in argument is gone. The remaining argument against a
rewrite is the only one that ever really mattered: **11k LOC of scar tissue** —
the bracketed-paste send path, the pane-collision guard, the sendq confirm
heuristics, the procinfo enrichment, the SSE framing the iOS client parses.
Each is a debugging session already paid for. A rewrite re-earns them all.

### Rust mapping (no hard parts left)

| Concern | Crate | Difficulty |
|---|---|---|
| HTTP + SSE + WS | `axum` | easy |
| SQLite | `rusqlite` | easy |
| tmux driving | `std::process::Command` | easy |
| **PTY** | `portable-pty` (wezterm) | **easy — and deletes the whole problem** |
| Process enumeration | `sysinfo`, or keep shelling to `ps` | easy |
| APNs (HTTP/2 + JWT) | `a2` or `hyper` | moderate |
| markdown → HTML | `pulldown-cmark` | easy |

Nothing here is research. The risk is entirely behavioral fidelity, not
capability.

### Python is out

Not a close call. It's a process supervisor and an HTTP server — the workload
Python is worst at and Rust is best at. GIL, venv deployment, no static binary,
and it solves the event-loop problem no better than Node does. It would be a
multi-week rewrite that buys strictly less than either alternative.

### Revised recommendation

1. **Delete `src/agents/**` and `whatsapp.ts` now.** 2,826 LOC, ~17% of the
   codebase, and it removes 10 of 12 npm deps. Pure win independent of any
   runtime decision. Note `serve.ts` imports `agents/registry.ts` and
   `agents/runner.ts` (lines 17–24, 472), so it's a bounded edit, not a clean
   file delete.
2. **Still fix PTY + persist `RUNS` first (half a day).** These retire the top
   two hazards. Do them before deciding — you cannot judge whether the pain
   justifies a rewrite while the two biggest sources of pain are unfixed.
3. **Then, if still unhappy: Rust — not Node, not Python.** Node buys `node-pty`
   and nothing else. Rust structurally removes the entire class of
   event-loop-saturation bug: real threads, no shared loop, one static binary to
   deploy. If you're going to spend the weeks, spend them on the destination
   that changes the architecture rather than the one that changes the logo.
4. The `src/rt.ts` shim from the original recommendation is now **lower value** —
   it was hedging toward Node, and Node is no longer the interesting target.
   Skip it.

### Addendum — what `marked` actually does

The one remaining npm dep, in two call sites, both serving the **web** client:

- `msgWithHtml` (`serve.ts:611`) → `web/src/App.tsx:3808`, chat bubbles. Has a
  fallback: `message.html || escapeHtml(message.text)`. Without it, prose renders
  unformatted, not broken.
- `renderReportHtml` (`serve.ts:326`) → `App.tsx:4064`, agent reports. **Dies with
  `src/agents/**`.**

The iOS client declares `html` (`Models.swift:109`) and decodes it but **never
reads it** — nothing in `ios/` references `.html` outside the model. So the
server parses markdown on every page fetch and every SSE frame (`serve.ts:2547`,
`2620`, `2721`, plus 40-message batches at `683`/`2728`) and iOS discards it.

That is synchronous CPU on the same loop the PTY saturates — minor by
comparison, but free to remove, and misplaced: markdown rendering belongs in the
client that displays it.

**Consequence:** delete `agents/` + move rendering into `web/src` and the backend
reaches **zero npm dependencies**. The port question becomes pure stdlib mapping
with no ecosystem risk. If server-side rendering is kept instead, Rust's
`pulldown-cmark` is a direct replacement (GFM tables included).

---

## Revision 2 — scope narrowed to "process watcher + iOS-facing server"

Correcting the previous section: `web/` is a **separate package** (own
`package.json`, own `bun.lock`) and `src/` never imports from it — verified. Its
JS-ness constrains the backend not at all. The only coupling was that `serve.ts`
renders markdown *for* it, which is a placement choice, not a dependency.

### What is actually in scope

| In scope | LOC | What it is |
|---|---|---|
| `sessions.ts` | 1833 | session enumeration + state — the watcher core |
| `tmux.ts` | 1073 | tmux driving |
| `sendq.ts` | 790 | send path + confirm heuristics |
| `push/*` | 1236 | always-on watcher → APNs, Live Activities |
| `actions/index.ts` | 515 | action dispatch |
| `procinfo.ts` | 372 | process enumeration |
| `journal*.ts`, `sendq-store.ts` | 573 | SQLite persistence |
| `pty.ts` | 204 | terminal bridge (the problem child) |
| `leases.ts` | 183 | lease coordination |
| `serve.ts` | ~2822 | HTTP/SSE — iOS-facing subset of 33 routes |

**Out of scope / deletable:** `agents/**` (2221), `aisdk-registry.ts` (137),
`whatsapp.ts` (605), `auto/**` (578 — spawns headless `claude` via subprocess, so
runtime-agnostic regardless), server-side `marked` rendering, static web serving.

Target: **~10.2–10.8k LOC, zero npm dependencies.**

### This scope changes the verdict

Strip the parts that were making JS look necessary and what remains is:
enumerate processes, drive tmux subprocesses, own PTYs, poll session state on
timers across a growing collection, fan out to APNs, serve HTTP/SSE to one
client, write SQLite.

That is a **process supervisor**. It is the workload Rust is best at and a
single-threaded event loop is worst at. Both worst hazards on the list —
event-loop saturation (`pty.ts:136`) and "no bare `setInterval` fan-out over a
collection" — are the *same* problem: one loop, shared by everything. Real
threads do not have that failure mode. It is not a bug you fix carefully in
Rust; it is a bug that cannot be written.

### But the sequencing does not change — and here is the better path

The scar-tissue argument still holds for 10k LOC. Do not big-bang it. The two
components that most need real threads are also the two that are **most
separable**, and neither sits on the iOS API contract's critical path:

1. **PTY → its own process.** Already recommendation #1, needed regardless of
   runtime. Tiny API surface (spawn, read, write, resize, kill). This is the
   single highest-value change in the whole document, and it is half a day.
2. **Watcher → its own process.** `push/watcher.ts:1` describes itself as
   "always-on … independent of any connected client SSE stream." It is *already*
   logically independent — it just happens to share a loop with HTTP. Splitting
   it out is mostly moving code.

Do those two and the event loop stops being contended, on Bun, this week. Then
each extracted process is independently portable to Rust later, behind a pipe,
without touching the iOS contract. `serve.ts` — the part with the real behavioral
risk — can stay on Bun indefinitely, because HTTP request/response is the one
thing an event loop is genuinely good at.

### Revised recommendation

1. Delete `agents/**`, `aisdk-registry.ts`, `whatsapp.ts` (~2,963 LOC, 10 of 12 deps).
2. Extract the PTY to a child process. Persist `RUNS` (`serve.ts:439`).
3. Extract the watcher to a child process.
4. **Then** decide. If a component still hurts, port *that component* to Rust
   behind its existing pipe. Never rewrite `serve.ts` wholesale — that is where
   the scar tissue lives and where the runtime matters least.
5. Python remains out for the reasons in Revision 1.
