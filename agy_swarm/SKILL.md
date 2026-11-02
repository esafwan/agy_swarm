---
name: agy_swarm
description: Orchestrate a large task as a dependency-mapped TODO graph executed by a swarm of cheap Gemini 3.8 Flash workers launched through the Antigravity CLI (`agy`), steered by Flash (High), cross-reviewed by GPT-OSS 120B, with one final fresh-context adversarial review. Claude models are an opt-in stuck handoff only. Use when a task decomposes into independently verifiable subtasks (multi-file features, refactors, migrations, bulk audits, test buildouts). Triggers on: "agy swarm this", "use agy_swarm", "swarm this with agy", "farm this out to agy workers".
---

# agy_swarm

You (the calling agent) own the execution graph, TODO tracker, dispatch, steering, integration and acceptance. You plan, launch `agy` workers, inspect diffs/evidence, unblock. Same algorithm as `claude_swarm`; workers are `agy` processes, not Agent-tool sub-agents.

**Model names drift. Run `scripts/agy_models.sh check` (validates against `agy models`) before a run.** Known list: Gemini 4 Argon, Gemini 3.8 Flash, Claude Opus 5.5, Claude Sonnet 5.5 (each Low/Medium/High), GPT-OSS 120B (Medium). **Do not configure Argon here; use `agy_swarm_deep` for that.**

## Roles and models (configurable)

Models are resolved per role: env var of the role name > `~/.config/agy_swarm/models.env` > built-in default. Inspect with `scripts/agy_models.sh show`, validate with `check`, create the file with `init`. Pass `--role <ROLE>` to `agy_dispatch.sh`; never hardcode a model string in a prompt or command.

| Role | Used for | Default |
|---|---|---|
| MAIN | orchestrator/coordinator (the calling agent) | `Gemini 3.8 Flash (High)` |
| PLANNER | plan vetting | `GPT-OSS 120B (Medium)` |
| EXECUTOR | default worker, first-pass self-review | `Gemini 3.8 Flash (Medium)` |
| EXECUTOR_LIGHT | trivial nodes | `Gemini 3.8 Flash (Low)` |
| EXECUTOR_HARD | hardest worker nodes | `Gemini 3.8 Flash (High)` |
| STEERING | conflicts, redirects, reasoning-hard escalations | `Gemini 3.8 Flash (High)` |
| CROSS_REVIEW | independent peer-diff review, second escalation tier | `GPT-OSS 120B (Medium)` |
| FINAL_REVIEW | final adversarial review (once, fresh `--new-project`) | `Gemini 3.8 Flash (High)` |
| STUCK_HANDOFF | OPTIONAL Claude handoff; empty = disabled | (empty) |

Defaults never use Argon. STUCK_HANDOFF is opt-in only (e.g. `Claude Sonnet 5.5 (Medium)`, then `Claude Opus 5.5 (Low)`): use it only when a node failed the whole default ladder and stays blocked; hand it over for investigation and a first concrete step, then return bounded work to EXECUTOR. Never route a well-specified node there "to be safe".

## Launching a worker

Always from the worktree cwd, with the guard prefix (the helper `scripts/agy_dispatch.sh` does all of this):

```bash
scripts/agy_dispatch.sh --role EXECUTOR <abs-worktree> <prompt-file> <log-dir> [conversation-id]
# equivalent to, with $MODEL = scripts/agy_models.sh get EXECUTOR (validated against `agy models`):
cd <abs-worktree> && agy --new-project --model "$MODEL" --dangerously-skip-permissions \
  --print-timeout 30m --output-format json \
  -p "FIRST run: pwd && git rev-parse --show-toplevel. If not exactly <abs-worktree>, STOP and report WRONG DIRECTORY. <task prompt>"
```

- **Parallelism:** one background process per worktree (`scripts/agy_dispatch.sh ... &` or run_in_background); keep the slot pool full per the invariants. `--print-timeout` bounds each call.
- **After EVERY call**, independently run `git status --short` and `git diff --stat` in the intended worktree. Empty diff = probable wrong-directory edit (agy gotcha): check `file://` paths in the response, move the patch, revert the stray checkout.
- **Resume:** `--output-format json` returns `conversation_id`; record it in SWARM_STATE and resume with `agy --conversation <id> ...` from the same worktree.
- Read-only nodes (research/review): say "read-only, do not edit" in the prompt; agy has `--mode plan` if you want it enforced.

## The graph (source of truth)

All state lives in `<run>/TODO_GRAPH.json` (template: `templates/TODO_GRAPH.template.json`, worked example: `examples/TODO_GRAPH.example.json`). Per task: `id, title, depends_on[], wave, scope{allowed[],forbidden[]}, role, context, acceptance[] (shell commands that exit 0), status (pending|ready|running|review|done|blocked|escalated), attempts, branch, worktree, commit`. Only `scripts/swarm_graph.sh` mutates status. Commands: `validate | ready | waves | next | set <id> <status> [sha] | prompt <id>` (all take the graph path first after the command).

## Algorithm (follow in order, do not improvise)

Setup
1. [ ] Run `scripts/agy_models.sh check`. Fix any FAIL before continuing.
2. [ ] Create `<run>/` (outside any repo) with `TODO_GRAPH.json`, `progress/`, `prompts/`, `logs/`, and `SWARM_STATE.md` from `templates/`. Cut the integration branch and one worktree per task per the shared invariants.
3. [ ] Write the graph: one task per independently verifiable unit, `depends_on` for real data/file dependencies, scope at file/function level, 1+ checkable acceptance command each.
4. [ ] `scripts/swarm_graph.sh validate <graph>` must print `graph OK`. Fix every ERROR (cycles, unknown deps, missing acceptance, same-wave scope overlap) and re-run.
5. [ ] Vet the plan once with the PLANNER role over the graph; apply amendments to the graph; `validate` again.

Loop (repeat until no task is pending/running/review/escalated)
6. [ ] `swarm_graph.sh validate`, then `swarm_graph.sh ready`. If empty and tasks remain: stop and look for `blocked` tasks.
7. [ ] `swarm_graph.sh next <graph>` prints one command per ready task: it writes the worker prompt, sets `running` (attempts+1) and calls `agy_dispatch.sh --role <effective role>`. Run each in the background, one per worktree.
8. [ ] When a call returns, read the printed `git status`/`git diff --stat`. Empty diff or files outside `scope.allowed` => the task failed: revert stray edits, `set <id> escalated` (or `blocked`), go to step 6.
9. [ ] Run every acceptance command yourself in the worktree. Any failure => `set <id> escalated`, go to step 6.
10. [ ] `set <id> review`. Dispatch a CROSS_REVIEW read-only review of the diff (`agy_dispatch.sh --role CROSS_REVIEW`). Findings => `set <id> escalated` with the findings in `context`; clean => continue.
11. [ ] `set <id> done <commit-sha>`. Update `SWARM_STATE.md`. Merge into the integration branch in wave order (coordinator only), running the suite after each merge.
12. [ ] Back to step 6.

Finish
13. [ ] Verification fan-out (bounded, one dimension each: tests, regressions, security, edge cases, lint/types) as new graph tasks.
14. [ ] FINAL_REVIEW once, fresh `--new-project`, read-only: goal, graph, diffs, verification results, risks. Each finding becomes a new graph task; loop again.
15. [ ] Accept only when every task is `done` and every acceptance command passes.

After any interruption: `scripts/swarm_status.sh <repo-root> <integration-branch> <run-dir>`, read the graph and SWARM_STATE, resume running tasks with `agy --conversation <id>` from their worktree; never re-dispatch onto a worktree with partial work.

## Escalation table (computed by `next`)

Role comes from the task's `role`, shifted up the ladder by `attempts // 2`:

| attempts so far | effective role |
|---|---|
| 0-1 | the task's own role |
| 2-3 | one step up |
| 4-5 | two steps up |

Ladder: `EXECUTOR_LIGHT -> EXECUTOR -> EXECUTOR_HARD -> STEERING -> CROSS_REVIEW -> STUCK_HANDOFF`. STUCK_HANDOFF is opt-in: if it is empty, `agy_dispatch.sh` fails; then mark the task `blocked` and ask the user. If a task is merely large, split it into new tasks instead of escalating.

## DO NOT

- Do not skip `validate`; do not dispatch a task whose dependencies are not all `done`.
- Do not let a worker edit outside `scope.allowed`; do not put two tasks with overlapping scope in the same wave.
- Do not trust a worker's report: always check `git diff --stat` (and the acceptance commands) in the worktree yourself.
- Do not edit status in the JSON by hand; use `set`.
- Do not hardcode model strings; use roles. Do not work around permission denials.
- Do not use Argon or Claude roles unless the user configured them.

## Worker prompt template (generated by `swarm_graph.sh prompt <id>`)

Fixed sections, in this order: `## Scope` (task, allowed files, verified working dir), `## Forbidden`, `## Context`, `## Acceptance` (commands), `## Self-check` (run acceptance, `git diff --stat`, commit with `Track-Item:` trailer, progress line), `## Output format` (STATUS / COMMITS / ACCEPTANCE / FILES / NOTES). `agy_dispatch.sh` prepends the pwd/toplevel guard.

## Shared invariants

Read `~/.claude/skills/_agy_swarm_shared/invariants.md` (adjust path to wherever you installed it) before any parallel dispatch: worker pool, overlap classification, worktrees, `Track-Item:` trailers, durable state, plan vetting, live verification, dispatch contract, agy-specific rules.
