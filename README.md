# agy_swarm

Two agent skills that run a dependency-mapped swarm of coding workers through the [Antigravity CLI](https://antigravity.google) (`agy`) instead of an in-process Agent tool. Adapted from `claude_swarm` / `claude_swarm_deep`: same algorithm, roles and escalation ladder, different launcher and model set.

- `agy_swarm`: cheap Gemini 3.8 Flash workers, Flash (High) steering, GPT-OSS 120B cross-review, one final fresh-context adversarial review. Claude models only as an opt-in "stuck handoff".
- `agy_swarm_deep`: research before decomposition, a blocking plan-review gate, an Argon orchestrator that never executes, Argon (Medium) reviews, two-key acceptance.
- `_agy_swarm_shared/invariants.md`: worker pool, overlap classification, worktrees, `Track-Item:` trailers, crash-safe state, plan vetting, agy-specific rules.

## Install

Symlink (or copy) all three directories into your agent's skills dir:

```bash
for d in agy_swarm agy_swarm_deep _agy_swarm_shared; do
  ln -s "$PWD/$d" ~/.claude/skills/$d     # or ~/.agents/skills, ~/.gemini/..., etc.
done
```

Requires `agy` on PATH, `git`, `jq`, `rg`. The skills reference `~/.claude/skills/_agy_swarm_shared/invariants.md`; adjust if you install elsewhere.

## How workers run

```bash
cd <worktree> && agy --new-project --model "Gemini 3.8 Flash (Medium)" --dangerously-skip-permissions \
  --print-timeout 30m --output-format json -p "FIRST run pwd && git rev-parse --show-toplevel ... <task>"
```

Parallelism is background processes, one per git worktree. Every call is followed by an independent `git diff --stat` (agy can silently edit the wrong directory). `--output-format json` returns `conversation_id`; resume with `agy --conversation <id>`. `agy_swarm/scripts/agy_dispatch.sh` wraps this.

## Default model mapping

These are defaults; see "Configuring models". Run `agy models` first; names drift. Strings were verified against real output.

| claude_swarm role | agy_swarm | agy_swarm_deep |
|---|---|---|
| Orchestrator | the calling agent | `Gemini 4 Argon (High)` |
| Plan review gate | `GPT-OSS 120B (Medium)` (vetting) | `Gemini 4 Argon (Medium)` |
| Haiku / default worker | `Gemini 3.8 Flash (Medium)` (Low trivial, High hardest) | same |
| Steering (Sonnet 5 Low) | `Gemini 3.8 Flash (High)` | n/a |
| 2nd escalation / cross-review | `GPT-OSS 120B (Medium)` | optional second opinion |
| Reviews (per-node, fan-out) | `GPT-OSS 120B (Medium)` | `Gemini 4 Argon (Medium)` |
| Final adversarial (Opus 5 Low) | `Gemini 3.8 Flash (High)`, once, fresh context | `Gemini 4 Argon (Medium)`, once |
| Stuck handoff (opt-in only) | `Claude Sonnet 5.5 (Medium)` then `Claude Opus 5.5 (Low)` | `Claude Opus 5.5 (Low)` |

`agy_swarm` never uses Argon.

## The TODO graph

Weaker instruction-followers need mechanics, not prose. The plan is a JSON file (`agy_swarm/templates/TODO_GRAPH.template.json`, worked example `agy_swarm/examples/TODO_GRAPH.example.json`) with per task: id, title, depends_on, wave, scope allowed/forbidden, role, acceptance commands, status, attempts, branch, worktree, commit. `agy_swarm/scripts/swarm_graph.sh` (bash + python3 stdlib) operates on it:

```bash
swarm_graph.sh validate G.json   # unknown deps, cycles, missing acceptance, same-wave scope overlap
swarm_graph.sh ready G.json      # pending tasks whose deps are all done
swarm_graph.sh waves G.json      # computed topological waves
swarm_graph.sh next G.json       # dispatch command per ready task (role escalates with attempts)
swarm_graph.sh set G.json T1 done <sha>
swarm_graph.sh prompt G.json T1  # worker prompt with fixed sections
```

The SKILL.md files run it as a checklist loop: validate -> ready -> dispatch -> diff check -> acceptance -> cross-review -> done, with an attempts-based escalation table and a DO NOT list.

## Configuring models

Every role's model is configurable globally. Precedence: **env var (same name as role) > config file > built-in default.**

- `agy_swarm`: `~/.config/agy_swarm/models.env` (template `config/models.env.example`)
- `agy_swarm_deep`: `~/.config/agy_swarm/models.deep.env` (template `config/models.deep.env.example`)

| Role | Meaning |
|---|---|
| MAIN | orchestrator/coordinator |
| PLANNER | plan + plan vetting / review gate |
| EXECUTOR / EXECUTOR_LIGHT / EXECUTOR_HARD | default / trivial / hardest worker nodes |
| STEERING | conflict resolution, redirects |
| CROSS_REVIEW | peer and per-node review, second escalation |
| FINAL_REVIEW | one-shot final adversarial review |
| STUCK_HANDOFF | optional Claude handoff; empty disables |

```bash
agy_swarm/scripts/agy_models.sh init            # copy example to ~/.config/agy_swarm/
agy_swarm/scripts/agy_models.sh --deep show     # resolved models
agy_swarm/scripts/agy_models.sh check           # validate against `agy models`
EXECUTOR="Gemini 3.8 Flash (High)" agy_swarm/scripts/agy_dispatch.sh --role EXECUTOR <worktree> <prompt-file> <log-dir>
```

Example file:

```bash
EXECUTOR="Gemini 3.8 Flash (Medium)"
CROSS_REVIEW="GPT-OSS 120B (Medium)"
STUCK_HANDOFF="Claude Opus 5.5 (Low)"
```

`agy_dispatch.sh` fails loudly if the resolved model is empty or absent from `agy models`. The `agy_swarm` defaults never use Argon.

## Differences from claude_swarm

- Launch via `agy` CLI in a worktree cwd, not the Agent tool; no `model` param, `SendMessage` or `isolation: "worktree"`; use `--model`, `agy --conversation <id>`, and `git worktree add`.
- No structured return: worktree, progress file and commits are the return channel; diff check after every call is mandatory.
- Different model families, so cross-review is cross-vendor rather than same-family tiering.
- Claude models are an opt-in escape hatch rather than part of the ladder.

MIT licensed.
