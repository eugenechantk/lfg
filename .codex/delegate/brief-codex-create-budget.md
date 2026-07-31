# Delegation Brief: fix codex create-time session id resolution

## Goal

`POST /api/sessions/new` with `agent: "codex"` must return a real `sessionId`. Today it
returns `null` because it stops waiting before codex has written the prompt to its rollout,
so the iOS client throws "Create returned no session id" and the session never appears.

## Evidence (measured on real rollouts from this machine, codex-cli 0.145.0)

`src/commands/serve.ts:1857` polls for the bound id for 6s total (12 iterations × 500ms).
Actual latency from process spawn to the prompt being written into the rollout:

| tmux | spawn → session_meta | session_meta → prompt | total |
|---|---|---|---|
| lfg-4e7b91 | 1.5s | 7.42s | ~9.4s |
| lfg-bb8957 | 1.6s | 5.22s | ~6.8s |

Codex writes `session_meta` at launch but only writes the user prompt once it has assembled
the injected AGENTS.md / instructions context. Both real cases exceed the 6s budget, so
prompt-based binding cannot possibly succeed within the poll window — this is independent of
the binding-correctness fix already landed in `src/sessions.ts`.

Client-side budget: `ios/LFGCore/Sources/LFGCore/LFGClient.swift:81` sets
`req.timeoutInterval = 20` for the POST that creates a session. So the server has ~20s of
headroom, of which it currently uses 6.

## Constraints

- **Only touch `src/commands/serve.ts`** and, if you add tests, the appropriate test file.
  Do not touch `web/`, `ios/`, or `src/sessions.ts` (that file has a separate landed fix).
- Do not restart the lfg server or any tmux session.
- Do not change the poll behavior for `claude`, `aisdk`, `codex-aisdk`, or `opencode` — the
  codex branch is the only one with this problem.
- Total server-side wait must stay safely under the client's 20s timeout. Target ~14s.

## Spec

### Primary — widen the codex poll budget

Raise the codex branch's wait from ~6s to ~14s, keeping the same 500ms cadence and the
existing `dismissCodexUpdatePrompt` call on each iteration. The loop must still exit
immediately once the id resolves, so a fast bind stays fast — this only changes the ceiling,
not the common-case latency. Leave the non-codex branches on their current budgets.

### Secondary — unambiguous fallback when the prompt still hasn't landed

If the budget expires with no bind, apply a last-resort bind, but ONLY when there is exactly
zero ambiguity:

- Consider unclaimed codex rollouts in this session's cwd whose createdAt is at/after this
  spawn, within a bounded window.
- If **exactly one** such candidate exists, bind it.
- If zero or more than one exist, return `sessionId: null` as today.

The single-candidate restriction is deliberate and must not be relaxed. We just fixed a
cross-binding defect where two concurrent same-cwd codex sessions were bound to each other's
transcripts; a fallback that guesses among multiple candidates would reintroduce exactly that
failure. A null id is recoverable (the session still appears on the next list refresh); a
wrong id silently shows the user another session's conversation.

## Verification

1. `bun test` — full suite green (141 tests currently pass; no regressions).
2. `bunx tsc --noEmit` — clean.
3. State the exact iteration count and total budget you chose, and confirm in writing that it
   is under the client's 20s timeout with margin.
4. If the fallback logic is testable without a live server, add a test for both branches
   (exactly-one-candidate binds; two-candidates returns null). If it is not reasonably
   testable in isolation, say so explicitly rather than writing a test that doesn't exercise it.

Do NOT restart the server to test end-to-end — Claude will do that separately with Eugene's OK.

## Definition of done

- [ ] Codex poll budget widened to ~14s, other agents untouched
- [ ] Single-candidate-only fallback implemented, with the ambiguity guard intact
- [ ] `bun test` green; typecheck clean
- [ ] Chosen budget stated and justified against the 20s client timeout

## Report back

Files changed, verification output, the budget you chose, and whether the fallback is covered
by tests or not.
