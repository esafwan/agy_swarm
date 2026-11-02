---
name: agy_swarm
description: Orchestrate a large task as a dependency-mapped TODO graph executed by a swarm of cheap Gemini 3.8 Flash workers launched through the Antigravity CLI (`agy`), steered by Flash (High), cross-reviewed by GPT-OSS 120B, with one final fresh-context adversarial review. Claude models are an opt-in stuck handoff only. Use when a task decomposes into independently verifiable subtasks (multi-file features, refactors, migrations, bulk audits, test buildouts). Triggers on: "agy swarm this", "use agy_swarm", "swarm this with agy", "farm this out to agy workers".
---

# agy_swarm

You (the calling agent) own the execution graph, TODO tracker, dispatch, steering, integration and acceptance. You plan, launch `agy` workers, inspect diffs/evidence, unblock. Same algorithm as `claude_swarm`; workers are `agy` processes, not Agent-tool sub-agents.

**Model names drift. Run `agy models` first and use the exact strings it prints.** Verified list: Gemini 4 Argon, Gemini 3.8 Flash, Claude Opus 5.5, Claude Sonnet 5.5 (each Low/Medium/High), GPT-OSS 120B (Medium). **Never use Argon in this skill.**

## Roles and models

| Role | `--model` string |
|---|---|
| Default worker; first-pass self-review | `"Gemini 3.8 Flash (Medium)"` (`(Low)` for trivial nodes) |
| Steering layer: conflicts, redirects, reasoning-hard escalations; cheap reviewer for read-only checks | `"Gemini 3.8 Flash (High)"` |
| Second escalation tier; independent cross-review of peer diffs; plan vetting | `"GPT-OSS 120B (Medium)"` |
| Final adversarial review (once, fresh context, new `--new-project`) | `"Gemini 3.8 Flash (High)"` |
| OPTIONAL stuck handoff (not a default tier) | `"Claude Sonnet 5.5 (Medium)"`, then `"Claude Opus 5.5 (Low)"` |

Stuck handoff: only when a node has failed the whole default ladder (Flash Medium -> Flash High -> GPT-OSS) and stays blocked. Hand it over for investigation and a first concrete step, then drop remaining bounded work back to Flash. Never route a well-specified node to Claude "to be safe".

## Launching a worker

Always from the worktree cwd, with the guard prefix (the helper `scripts/agy_dispatch.sh` does all of this):

```bash
cd <abs-worktree> && agy --new-project --model "Gemini 3.8 Flash (Medium)" \
  --dangerously-skip-permissions --print-timeout 30m --output-format json \
  -p "FIRST run: pwd && git rev-parse --show-toplevel. If not exactly <abs-worktree>, STOP and report WRONG DIRECTORY. <task prompt>"
```

- **Parallelism:** one background process per worktree (`scripts/agy_dispatch.sh ... &` or run_in_background); keep the slot pool full per the invariants. `--print-timeout` bounds each call.
- **After EVERY call**, independently run `git status --short` and `git diff --stat` in the intended worktree. Empty diff = probable wrong-directory edit (agy gotcha): check `file://` paths in the response, move the patch, revert the stray checkout.
- **Resume:** `--output-format json` returns `conversation_id`; record it in SWARM_STATE and resume with `agy --conversation <id> ...` from the same worktree.
- Read-only nodes (research/review): say "read-only, do not edit" in the prompt; agy has `--mode plan` if you want it enforced.

## Algorithm

0. **Run state first.** Run dir (outside any repo) with `SWARM_STATE.md` (`templates/`) and `progress/`; cut integration branch + worktrees per the shared invariants. Update the state file after every event.
1. **Plan.** Dependency-mapped TODO graph with acceptance criteria; classify overlap at function level plus hidden shared artefacts; order into waves.
1b. **Vet the plan once** with `"GPT-OSS 120B (Medium)"` using the Plan vetting checklist; apply as "v2 AMENDMENTS" before dispatch.
2. **Dispatch to Flash (Medium), maximally parallel.** Each worker gets exact scope (may / must not touch), minimal context, constraints, acceptance criteria, `Track-Item:` trailer + commit/progress/push rules, and a requirement to self-check its diff.
3. **Cross-review** with a different model (`GPT-OSS 120B (Medium)`) of the first worker's diff before you look at it.
4. **Steer continuously:** track done/blocked/in-flight, inspect diffs not transcripts, resolve conflicts between parallel workers immediately.
5. **Escalate on demonstrated difficulty only, per node:** `Flash Medium -> Flash High -> GPT-OSS 120B (Medium) -> (opt-in) Claude stuck handoff`. Decompose first if a node is merely large.
6. **Broad verification fan-out (Flash):** tests, regressions, security, edge cases, dead code, contracts, lint/types, cross-module consistency; bounded and independent.
7. **Final adversarial review (Flash High, once, fresh `--new-project`).** Give goal, plan, significant diffs, verification results, unresolved concerns, risky decisions. Hunt architectural mistakes, hidden regressions, wrong assumptions, missing requirements, shared blind spots. Bounded; not a full re-review.
8. **Close the loop:** each finding becomes a new scoped task to the cheapest capable worker; revalidate; accept only when all criteria pass.
9. **Merge wave by wave** (coordinator only, planned order, full suite after each merge), then live verification, per the invariants.
10. **After any interruption:** `scripts/swarm_status.sh <repo-root> <integration-branch> <run-dir>`, read SWARM_STATE, resume workers with `agy --conversation <id>`; never re-dispatch onto a worktree with partial work.

## Shared invariants

Read `~/.claude/skills/_agy_swarm_shared/invariants.md` (adjust path to wherever you installed it) before any parallel dispatch: worker pool, overlap classification, worktrees, `Track-Item:` trailers, durable state, plan vetting, live verification, dispatch contract, agy-specific rules.
