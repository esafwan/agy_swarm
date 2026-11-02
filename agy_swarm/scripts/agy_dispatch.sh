#!/usr/bin/env bash
# Usage: agy_dispatch.sh <worktree-abs-path> <model-string> <prompt-file> <log-dir> [conversation-id]
# Runs one agy worker from inside the worktree, blocking. Writes <log-dir>/<name>.json (conversation_id, status, response)
# and prints the independent `git diff --stat` check. Run it with `&` / run_in_background for parallelism.
# Models: use the exact strings from `agy models`.
set -u
WT="${1:?worktree abs path}"; MODEL="${2:?model}"; PF="${3:?prompt file}"; LOGS="${4:?log dir}"; CONV="${5:-}"
mkdir -p "$LOGS"; name=$(basename "$WT"); out="$LOGS/$name.json"
GUARD="FIRST run: pwd && git rev-parse --show-toplevel. If the resolved directory is not exactly $WT, STOP and report 'WRONG DIRECTORY' without editing anything. Work only inside $WT.

"
cd "$WT" || exit 2
if [ -n "$CONV" ]; then
  agy --conversation "$CONV" --model "$MODEL" --dangerously-skip-permissions --print-timeout "${PRINT_TIMEOUT:-30m}" --output-format json -p "$GUARD$(cat "$PF")" >"$out" 2>"$LOGS/$name.err"
else
  agy --new-project --model "$MODEL" --dangerously-skip-permissions --print-timeout "${PRINT_TIMEOUT:-30m}" --output-format json -p "$GUARD$(cat "$PF")" >"$out" 2>"$LOGS/$name.err"
fi
echo "agy exit=$? conversation_id=$(jq -r .conversation_id "$out" 2>/dev/null) status=$(jq -r .status "$out" 2>/dev/null)"
echo "--- independent check in $WT ---"; git -C "$WT" rev-parse --show-toplevel; git -C "$WT" status --short | head -30; git -C "$WT" diff --stat HEAD
[ -z "$(git -C "$WT" status --short)" ] && echo "WARNING: empty diff; check file:// paths in $out response for a wrong-directory edit"
