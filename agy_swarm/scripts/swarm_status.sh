#!/usr/bin/env bash
# Usage: swarm_status.sh <repo-root> <integration-branch> <run-dir> [worktree-glob]
# Prints every WP worktree: branch, commits ahead of the integration branch, uncommitted files, push state, progress tail.
# Worktrees are expected as <repo-root>/<glob> (default: wp*) each on a wp/* branch; progress files at <run-dir>/progress/<WP>.md.
R="${1:?repo root}"; INTEG="${2:?integration branch}"; RUN="${3:?run dir}"; GLOB="${4:-wp*}"
echo "integration $INTEG: $(git -C "$R/$(ls "$R" | rg -m1 -i 'harden|integ' || echo .)" log --oneline -1 2>/dev/null | cut -c1-90)"
for d in $R/$GLOB; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  n=$(basename "$d"); b=$(git -C "$d" branch --show-current)
  ahead=$(git -C "$d" rev-list --count "$INTEG..HEAD" 2>/dev/null)
  dirty=$(git -C "$d" status --short | wc -l | tr -d ' ')
  remote=$(git -C "$d" ls-remote --heads origin "$b" 2>/dev/null | cut -c1-8); local=$(git -C "$d" rev-parse --short=8 HEAD)
  push="NOT PUSHED"; [ -n "$remote" ] && { [ "$remote" = "$local" ] && push="pushed (in sync)" || push="pushed (behind local)"; }
  echo "== $n [$b] ahead=$ahead uncommitted=$dirty $push"
  git -C "$d" log --oneline -3 | sed 's/^/     /' | cut -c1-110
  for f in "$RUN/progress/$n.md" "$RUN/progress/$(echo "$b" | sed 's#wp/##;s#-.*##' | tr a-z A-Z | sed 's/^/WP-/').md"; do
    [ -f "$f" ] && { echo "   progress tail ($(basename "$f")):"; tail -3 "$f" | sed 's/^/     /' | cut -c1-140; break; }
  done
done
