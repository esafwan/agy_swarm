#!/usr/bin/env bash
# Usage: agy_models.sh [--deep] show | get <ROLE> | init | check
# Precedence: env var (same name as role) > config file > built-in default.
# Files: ~/.config/agy_swarm/models.env (agy_swarm), models.deep.env (agy_swarm_deep).
ROLES="MAIN PLANNER EXECUTOR EXECUTOR_LIGHT EXECUTOR_HARD STEERING CROSS_REVIEW FINAL_REVIEW STUCK_HANDOFF"
DIR="${AGY_SWARM_CONFIG_DIR:-$HOME/.config/agy_swarm}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$HERE/../.."
DEEP=0; [ "${1:-}" = "--deep" ] && { DEEP=1; shift; }
if [ $DEEP = 1 ]; then FILE="$DIR/models.deep.env"; EX="models.deep.env.example"; else FILE="$DIR/models.env"; EX="models.env.example"; fi

default() { # built-in defaults
  case "$DEEP:$1" in
    0:MAIN|0:STEERING|0:EXECUTOR_HARD|0:FINAL_REVIEW) echo "Gemini 3.8 Flash (High)";;
    0:PLANNER|0:CROSS_REVIEW) echo "GPT-OSS 120B (Medium)";;
    1:MAIN) echo "Gemini 4 Argon (High)";;
    1:PLANNER|1:CROSS_REVIEW|1:FINAL_REVIEW) echo "Gemini 4 Argon (Medium)";;
    1:STEERING|1:EXECUTOR_HARD) echo "Gemini 3.8 Flash (High)";;
    *:EXECUTOR) echo "Gemini 3.8 Flash (Medium)";;
    *:EXECUTOR_LIGHT) echo "Gemini 3.8 Flash (Low)";;
    *:STUCK_HANDOFF) echo "";;
    *) return 1;;
  esac
}
resolve() { # ROLE -> model string (may be empty for STUCK_HANDOFF)
  local r="$1" v
  case " $ROLES " in *" $r "*) ;; *) echo "unknown role: $r (roles: $ROLES)" >&2; return 2;; esac
  if [ -n "${!r+x}" ]; then printf '%s' "${!r}"; return; fi
  if [ -f "$FILE" ]; then
    v=$( unset "$r"; . "$FILE" >/dev/null 2>&1; [ -n "${!r+x}" ] && printf 'S%s' "${!r}" )
    [ -n "$v" ] && { printf '%s' "${v#S}"; return; }
  fi
  default "$r"
}
check() {
  local avail rc=0 r m; avail=$(agy models 2>/dev/null | cut -f2)
  [ -z "$avail" ] && { echo "FAIL: 'agy models' returned nothing" >&2; return 1; }
  for r in $ROLES; do
    m=$(resolve "$r")
    if [ -z "$m" ]; then echo "SKIP  $r (empty/disabled)"
    elif printf '%s\n' "$avail" | grep -qxF "$m"; then echo "OK    $r = $m"
    else echo "FAIL  $r = \"$m\" not in 'agy models'" >&2; rc=1; fi
  done; return $rc
}
case "${1:-}" in
  get) resolve "${2:?role}";;
  show) for r in $ROLES; do printf '%-15s %s\n' "$r" "$(resolve "$r")"; done; echo "(file: $FILE $([ -f "$FILE" ] && echo present || echo absent); env overrides win)";;
  init) mkdir -p "$DIR"; [ -f "$FILE" ] && { echo "exists: $FILE"; exit 0; }; cp "$REPO/config/$EX" "$FILE" && echo "created $FILE";;
  check) check;;
  *) echo "usage: agy_models.sh [--deep] show|get ROLE|init|check" >&2; exit 2;;
esac
