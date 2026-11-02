#!/usr/bin/env bash
# Usage: swarm_graph.sh <validate|ready|waves|next|set|prompt> <TODO_GRAPH.json> [args]
#   validate           unknown deps, cycles, missing acceptance/scope, same-wave scope overlap, wave order
#   ready              ids of pending/escalated tasks whose deps are all done
#   waves              computed topological waves
#   next               dispatch command for every ready task (role escalates: attempts>=2 => next role up)
#   set <id> <status> [commit-sha]   status: pending|ready|running|review|done|blocked|escalated (running bumps attempts)
#   prompt <id>        worker prompt for the task, fixed sections
# Requires python3 (stdlib only).
exec python3 "$(dirname "${BASH_SOURCE[0]}")/swarm_graph.py" "$@"
