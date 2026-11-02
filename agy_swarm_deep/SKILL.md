---
name: agy_swarm_deep
description: Deep-research variant of agy_swarm for the Antigravity CLI (`agy`). An Argon (High) orchestrator never executes; evidence is gathered before decomposition; the plan passes an Argon (Medium) review gate before any worker launches; Gemini 3.8 Flash workers do the work; Argon (Medium) reviews every node and the final pass; Claude Opus 5.5 (Low) is an opt-in stuck handoff. Use when a wrong plan would be expensive, or the task needs investigation first (architecture-sensitive migrations, deep audits, unfamiliar codebases). Triggers on: "deep agy swarm", "use agy_swarm_deep", "agy swarm with deep research", "research then agy swarm".
---

# agy_swarm_deep

Use `agy_swarm` when decomposition is obvious; use this when getting the *plan* wrong is the main risk. Two gates: evidence before decomposition, plan review before the first worker launches.

**Run `agy models` first; names drift.** Use exact strings.

## Roles and models

| Role | `--model` string |
|---|---|
| Orchestrator (you / the session; if relaunching it via agy) | `"Gemini 4 Argon (High)"` |
| Plan review gate (one-shot, blocking) | `"Gemini 4 Argon (Medium)"` |
| Default worker and read-only research nodes | `"Gemini 3.8 Flash (Medium)"` (`(Low)` trivial, `(High)` hardest nodes) |
| Per-node review, cross-review, verification fan-out, final adversarial pass (once, fresh context) | `"Gemini 4 Argon (Medium)"` |
| Escalation after Flash High | `"GPT-OSS 120B (Medium)"` as a second opinion, optional |
| OPTIONAL stuck handoff (not a default tier) | `"Claude Opus 5.5 (Low)"` |

Floor is Flash Medium, not Low: deep research nodes fail silently at the lowest tier (skimmed files, confident summaries).

## The orchestrator never executes

No edits, builds, tests or commits by you. Reading (`git diff/log/status`, opening files) is how you steer; everything that changes state is dispatched, even a one-line fix (a cheap Flash node). You adjudicate reviews; a reviewer model judges diffs.

## Launching any agy node

From the worktree cwd, guard prefix, then independent diff check; use `agy_swarm/scripts/agy_dispatch.sh`:

```bash
cd <abs-worktree> && agy --new-project --model "<name>" --dangerously-skip-permissions \
  --print-timeout 30m --output-format json -p "FIRST run: pwd && git rev-parse --show-toplevel; abort if not <abs-worktree>. <prompt>"
```

Background processes for parallelism; `conversation_id` from the JSON output goes in SWARM_STATE; resume with `agy --conversation <id>`. After every call run `git status --short` and `git diff --stat` in the intended worktree (wrong-directory gotcha). Reviewers are read-only: say so, or pass `--mode plan`. Write long prompts to a file and capture each review's stdout to a log file.

## Algorithm

1. **Research first, in parallel (Flash Medium, read-only).** Name specific questions per node; each returns a written findings file on disk (run dir), not just a chat summary. Bound the phase.
2. **Decompose against the evidence.** Graph with edges, falsifiable acceptance criteria, file/function scope per node; cite findings; record unevidenced assumptions explicitly; do the overlap classification from the invariants.
3. **Plan review gate (Argon Medium, once, blocking).** Give goal, graph, criteria, scope map, assumptions, findings paths. Ask for: missing nodes, wrong/missing edges or false disjointness, non-falsifiable criteria, unsupported nodes/assumptions that should be research, risky work deferred to the end. No worker launches until every finding is fixed or rejected with a recorded reason; re-run the gate if the shape changes. A third re-plan means the goal is underspecified: go back to the user.
4. **Dispatch to Flash Medium, maximally parallel** (never phase-lock): exact scope, only needed context (point at findings files), constraints, criteria, `Track-Item:` trailer, self-check.
5. **Monitor and diff-check every return before spending review tokens:** `git log --grep "Track-Item: <id>"`, `git diff`, check scope and that criteria are met, not asserted. Failures bounce back to the worker; do not forward them to a reviewer or fix them yourself.
6. **Per-node review (Argon Medium)** of diffs that passed the mechanical check; batch coupled nodes.
7. **Two-key acceptance:** a node closes only when your scope/traceability check AND its Argon review pass.
8. **Escalate per node on demonstrated difficulty:** `Flash Medium -> Flash High -> GPT-OSS 120B (Medium) (optional second opinion) -> opt-in Claude Opus 5.5 (Low) stuck handoff`. For the handoff: investigate until confident, make and validate the first concrete step, then hand bounded work back to Flash.
9. **Verification fan-out (Argon Medium):** bounded one-dimension, one-scope reviews (tests, regressions, security, edge cases, dead code, contracts, lint/types, consistency).
10. **Final adversarial pass (Argon Medium, once, fresh `--new-project`):** goal, plan, plan-review findings, significant diffs, verification results, open concerns, risky decisions; hunt architecture errors, hidden regressions, wrong assumptions, missing requirements, shared blind spots. Not a full re-review.
11. **Close the loop:** surviving findings become new Flash nodes, diff-checked and re-reviewed. Accepting with a known-open finding is the user's call.

Durable state, worktrees, merge order, live verification: `~/.claude/skills/_agy_swarm_shared/invariants.md` (adjust path to your install) and `agy_swarm/templates` + `agy_swarm/scripts`.

If step 1 shows the decomposition is obvious, say so and drop to `agy_swarm`.
