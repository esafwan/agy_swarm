# Swarm state — <run name> (coordinator-maintained; recover from here after any crash/network loss)
Plan: <path to PLAN.md> (v2 AMENDMENTS override). Integration branch: <branch> (worktree <path>), base: <base>, draft PR: <#>.
Worker rules: commit after EVERY logical step (`wip(<WP>): ...` + `Track-Item: <WP>`), append one line to progress/<WP>.md after each step, push the WP branch after each commit batch. On resume: read progress file, `git log`, `git status`, `git diff`, verify consistency, continue.
Recovery: `~/.claude/skills/agy_swarm/scripts/swarm_status.sh <repo-root> <integration-branch> <run-dir>`

| WP | Wave | Tier (model) | Worktree | Branch | Conversation id | State | Merged? | Live verified? |
|---|---|---|---|---|---|---|---|---|
| WP-1 ... | 1 | Sonnet | | wp/1-... | | todo | no | no |

## Event log (newest last)
- <date>: plan vetted by Opus 5.5 (Low); integration branch created; wave 1 dispatched.
