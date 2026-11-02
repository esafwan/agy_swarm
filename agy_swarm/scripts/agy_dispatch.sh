#!/usr/bin/env bash
# Usage: agy_dispatch.sh [--deep] --role <ROLE> <worktree-abs-path> <prompt-file> <log-dir> [conversation-id]
# Runs one agy worker from inside the worktree, blocking. Model comes from agy_models.sh (env > config file > default);
# fails loudly if the resolved model is empty or not in `agy models`. Writes <log-dir>/<name>.json and prints the
# independent `git diff --stat` check. Run with `&` / run_in_background for parallelism.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; FL=""; ROLE=""
while [ $# -gt 0 ]; do case "$1" in --deep) FL="--deep"; shift;; --role) ROLE="${2:?role}"; shift 2;; *) break;; esac; done
[ -n "$ROLE" ] || { echo "missing --role <ROLE>" >&2; exit 2; }
WT="${1:?worktree abs path}"; PF="${2:?prompt file}"; LOGS="${3:?log dir}"; CONV="${4:-}"
MODEL=$("$HERE/agy_models.sh" $FL get "$ROLE") || exit 2
[ -n "$MODEL" ] || { echo "role $ROLE resolves to empty model (disabled)" >&2; exit 2; }
agy models 2>/dev/null | cut -f2 | grep -qxF "$MODEL" || { echo "model \"$MODEL\" (role $ROLE) not in 'agy models'" >&2; exit 2; }
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
