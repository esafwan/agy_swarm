# Swarm invariants (shared by agy_swarm and agy_swarm_deep)

These rules are flow-independent. Read them before any parallel dispatch, in either
flow. Where they say "the default worker tier", substitute whatever your flow's
ladder starts at (Gemini 3.8 Flash (Medium) for `agy_swarm`, Gemini 3.8 Flash (Medium) for `agy_swarm_deep`).

## Worker pool discipline

Treat worker slots (concurrent `agy` processes) as a continuously replenished pool, not phase-locked batches:
- Keep every slot filled with the highest-priority dependency-ready task.
- The instant a slot frees up, refill it — don't wait for a whole wave to land.
- Never block later, already-safe work behind an earlier wave that's still running.

## Filesystem isolation — mandatory before any parallel dispatch

Step 1 of the Algorithm ("decompose into a TODO graph") is incomplete without this: a
dependency edge is not just "task B needs task A's output," it is also "task B and task A
touch the same file." **Before dispatching anything in parallel, classify every pair of
ready tasks by file-scope overlap:**

1. **List the files/interfaces each task is expected to touch** as part of writing its
   scope (Algorithm step 2 already requires this — reuse it for this check, don't skip it
   because it feels redundant).
2. **Disjoint scopes → dispatch normally**, same shared working directory, no isolation
   needed. This is the common case and most of this skill's cost model depends on it
   staying cheap — don't over-isolate.
3. **Overlapping scopes (especially anything touching shared/global files — a design
   system's shared component library, a shared config, a shared schema/types file) →
   you MUST do one of:**
   - **Serialize** the overlapping tasks (run them one after another, not concurrently) if
     the overlap is small and the tasks are cheap, or
   - **Isolate** each overlapping task in its own git worktree (`git worktree add`, then run the
     `agy` worker with that worktree as its cwd) and merge the results back yourself once each returns —
     this is the default choice once more than ~2 tasks share risky overlap, or the shared
     file is large/central enough that a silent last-writer-wins clobber would be expensive
     to detect.
   - Never dispatch overlapping-scope tasks concurrently onto the same shared working
     directory and rely on each worker "being careful" or on a later diff review to catch
     collisions. Two agents editing, `git add`-ing, and committing in the same working tree
     at the same time can interleave in ways a post-hoc diff review will not reliably catch
     — this is not a theoretical risk, it is the normal failure mode of shared-checkout
     concurrency.
4. **A task that runs its own internal agy_swarm** (i.e. a sub-agent you dispatched is
   itself decomposing further and spawning its own workers) inherits this same
   obligation one level down — tell it explicitly, in its dispatch prompt, to run this same
   overlap classification before its own parallel fan-out, not just at your top level.
5. When in doubt about whether two tasks overlap (e.g. both touch "the design system" in
   some vague sense but you haven't confirmed the exact files), **default to isolating** —
   the cost of an unnecessary worktree is small; the cost of a missed collision on a shared
   checkout is a silently corrupted or half-clobbered file that may not surface until much
   later.

## Commit traceability — tag every commit with its task ID

When multiple tasks land commits into the same shared checkout (the common case when you
chose "serialize" over "isolate" in the previous section, or whenever several tasks finish
close together), give every task's dispatch prompt this instruction: **append a trailer
line at the very end of its commit message** (after the body, on its own line, still plain
human-readable text) naming the task:

```
Track-Item: <task-id-or-number>
```

Use whatever ID scheme your TODO graph already uses (a number, a short slug — anything
stable and unique within this run). This costs nothing and pays for itself the moment you
need to reconcile: `git log --grep "Track-Item: 7"` instantly answers "which commit(s) came
from task 7," without you having to remember timing, diff through unrelated commits, or ask
a completed (and possibly gone) worker to remind you. It also lets a task that runs its own
internal commit (e.g. after amending to fix a review finding) keep the same trailer, so the
final `git log` reads as a task-indexed history of the whole run, not an anonymous stream of
"fix" commits. Tell each dispatched task about this requirement explicitly — it will not
happen by default, and a task that already committed before receiving the instruction should
`git commit --amend` to add the trailer rather than leave it untagged.

## Durable state and crash recovery — mandatory for any run longer than a few minutes

Workers and the coordinator WILL be interrupted (network outage, API error, context loss, user restarts). Design every run so an interruption costs minutes, not work.

0. **Run-dir is never inside a repo.** `<run-dir>` MUST be an absolute path in the workspace track (e.g. `/Users/<you>/Code/Huf/workspace/Tracks/<Track>/ongoing/<effort>/`), never repo-relative and never inside a worktree. Progress notes, SWARM_STATE, plans, findings, logs, probes and scratch scripts live there only. Workers stage files by explicit path (never `git add -A` / `git add .`) and run `python3 scripts/check_repo_layout.py` (if the repo has it) before every commit; a worker that sees workspace files in `git status` of the product repo stops and moves them out.
1. **State file.** Before dispatching anything, create `<run-dir>/SWARM_STATE.md` (template: `~/.claude/skills/agy_swarm/templates/SWARM_STATE.md`): one table row per work package (WP) with wave, tier, worktree path, branch, conversation id, state, merged?, live-verified?, plus an append-only event log. **The coordinator updates it after every event** (dispatch, completion, failure, merge, live check). It is the single recovery document: after any crash, read it first.
2. **Granular worker persistence.** Every dispatch prompt must say: commit after EVERY logical step (WIP commits are fine: `wip(<WP>): <what>` + the `Track-Item:` trailer), append one line to `<run-dir>/progress/<WP>.md` after each step (timestamp, done, next, test status), and push the WP branch after each commit batch. Uncommitted work in a worktree is the only thing an outage can lose — keep it to minutes.
3. **Resume protocol.** A failed/interrupted worker is resumed with `agy --conversation <id>` from its worktree (it keeps its context; the id is `conversation_id` in the worker's JSON log): tell it the cause was external, to read its progress file + `git log` + `git status` + `git diff` first, verify the partial edits are consistent (py_compile, valid JSON, no half-applied hunks), then continue. Never re-dispatch a fresh agent onto a worktree that has partial work without first inspecting it.
4. **Status script.** Keep `~/.claude/skills/agy_swarm/scripts/swarm_status.sh <repo-root> <integration-branch> <run-dir>` available: it prints every WP worktree (branch, commits ahead of the integration branch, uncommitted files, pushed or not, progress-file tail). Run it right after any outage and before every wave merge.
5. **Failure triage.** Distinguish external failures (network/API errors → resume), tool/permission denials (do NOT work around; re-plan or ask the owner), and genuine worker failures (→ escalate the tier per the ladder). Record which in the event log.

## Integration-branch and worktree protocol (parallel code changes)

- Cut ONE integration branch from the agreed base; ONE draft PR for the whole effort. Every WP is cut from the integration branch into its OWN worktree + branch (`wp/<n>-<name>`); the worker creates it itself (`git -C <integration-worktree> worktree add ../<wp-dir> -b wp/... <integration-branch>`), never shares one with another worker, never uses `git stash`.
- The coordinator alone merges WP branches into the integration branch, in a planned order (safety/foundation first), and runs the full relevant suite after EACH merge, not once per wave. Conflicts are resolved by the coordinator.
- **Overlap classification must go below file level.** List the FUNCTIONS/regions each WP edits, plus hidden shared artefacts: doctype JSON (`field_order`, new fields), `hooks.py`, shared test files and fixtures, error maps, enums/status option lists, registries. Assign each contested function to exactly one WP; other WPs add helpers only. Rules for shared JSON: one field-add commit per WP, targeted 1-line edits (never reformat a file), never reorder, coordinator resolves ordering. New test files per WP; append-only to shared ones.
- A WP that depends on another's merge is cut AFTER that merge (state it in the plan). Split any WP that is too big for its tier (huge files, multi-subsystem scope).

## Shared environment protocol (benches, DBs, ports, tunnels)

- Exactly ONE script owns the shared environment and holds the lock across the whole critical section: sync code -> migrate -> run tests -> restore the integration state. Workers never call ad-hoc sync/restore commands. A restore that races another worker's sync silently corrupts both (seen in practice).
- **Test the harness itself** before trusting it: run it once with two modules and confirm both ran (an argument-shift bug once silently skipped every worker's first module). Require workers to report which modules actually executed.
- Before any live window the coordinator runs migrate + a tree-hash check (environment tree == integration HEAD) and restarts workers that cache code.
- Never kill shared processes or stop shared containers to simulate failures; simulate with scripts (stale rows, fake status in the DB).
- Pre-release repos: no backcompat/migration patches; dev-data fix-ups are done by the coordinator on the disposable environment only.

## Plan vetting (one-shot reviewer: "GPT-OSS 120B (Medium)" in agy_swarm, "Gemini 4 Argon (Medium)" in agy_swarm_deep; once, before workers start)

Give the vetting model: the plan, the source finding list, the code paths. Ask it adversarially for: hidden function-level collisions and shared artefacts; wave order and mis-sized/mis-tiered WPs; acceptance criteria that do not actually close the source rows (list uncovered rows); live checks that cannot prove what they claim or cannot be produced in this environment (propose substitutes: signed webhook replays, bench scripts, DB fixtures); harness/merge/token/override hazards; safety (allow-lists for outbound targets, production guards); anything missing (docs, status updates, data fix-ups). Apply its amendments as a versioned "v2 AMENDMENTS" section that overrides the plan, then dispatch.

## Live verification stage (after each wave, before the next)

Plans that change behaviour visible to real users end with a live check, not just unit tests: per WP, define the exact scenario, the evidence (log rows + screenshots) and the substitute when the real trigger cannot be produced. Budget short-lived credentials (check expiry first, never persist them), record any config you override (webhook URLs, flags) BEFORE changing it and revert it in a checklist step even when verification fails, hard-assert allow-listed recipients/sites in every verification script, and send failures back to the owning WP. Owner-only steps (phone actions) are scheduled explicitly with a stated moment and a running watcher.

## Dispatch prompt contract (every worker)

Scope (files AND functions), the exact finding rows, acceptance criteria, failing tests first, how to run tests (the one harness script), commit/trailer/push/progress rules above, "report: SHAs, tests executed per module, unfinished items, anything the code contradicted, shared-file edits". Tell workers what NOT to touch and who owns it. Tell them not to work around tool/permission denials. Prefer an unproven model only after a one-line probe proves it is usable (account/region/privacy blocks fail late); never change account settings to make it work without the owner's say-so.

## agy-specific rules (apply to every worker launch)

- Launch: `cd <worktree> && agy --new-project --model "<name>" --dangerously-skip-permissions --print-timeout 30m --output-format json -p "<prompt>"`. `scripts/agy_dispatch.sh` in `agy_swarm` wraps this. Parallelism = background processes (one per worktree); `--print-timeout` bounds each.
- Every prompt starts with the self-verifying guard: run `pwd && git rev-parse --show-toplevel`, abort if it is not the expected absolute worktree path. `--new-project` alone is not trusted.
- After EVERY call, independently run `git status --short` and `git diff --stat` in the intended worktree. Empty diff on a "successful" run means a wrong-directory edit: look at the `file://` paths in the response, capture with `git diff > patch`, revert there, `git apply` in the right worktree.
- Capture `conversation_id` from the `--output-format json` result into SWARM_STATE; resume with `agy --conversation <id> ...` run from the same worktree.
- `agy` workers have no tool-level worktree isolation or structured return; the worktree + progress file + commits ARE the return channel.
- Model names drift: run `agy models` before a run and use exact strings.
